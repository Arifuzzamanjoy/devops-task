"""FastAPI application entry-point."""

import logging
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import AsyncIterator, Awaitable, Callable

from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)

from app.config import get_config
from app.logging_config import setup_logging

config = get_config()
setup_logging(config.log_level)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Prometheus metrics (own registry, so tests don't share default collectors)
# ---------------------------------------------------------------------------
REGISTRY = CollectorRegistry()

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status"],
    registry=REGISTRY,
)

ERROR_COUNT = Counter(
    "http_errors_total",
    "Total number of HTTP error responses (4xx/5xx)",
    ["method", "endpoint", "status"],
    registry=REGISTRY,
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
    registry=REGISTRY,
)

# Paths that are polled constantly; logged at debug so they don't drown real traffic
QUIET_PATHS = {"/health", "/metrics"}

_VERSION_FILE = Path(__file__).resolve().parent.parent / "VERSION"
try:
    APP_VERSION = _VERSION_FILE.read_text().strip()
except FileNotFoundError:
    APP_VERSION = "0.0.0-unknown"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Log startup and shutdown.

    SIGTERM is handled by uvicorn: it stops accepting connections, waits for
    in-flight requests, then runs the code after ``yield``.
    """
    logger.info(
        "Application started",
        extra={"version": APP_VERSION, "environment": config.environment, "port": config.app_port},
    )
    yield
    logger.info("Application shutdown complete")


app = FastAPI(title="DevOps Task API", version=APP_VERSION, lifespan=lifespan)


def _route_template(request: Request) -> str:
    """Matched route path (e.g. "/items/{id}"), so metric labels stay bounded.

    Unknown URLs share one label; otherwise every scanner request would create
    a new time series.
    """
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


@app.middleware("http")
async def observe_requests(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Record metrics and an access log line for every request."""
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        elapsed = time.perf_counter() - start
        endpoint = _route_template(request)
        method = request.method

        if request.url.path != "/metrics":
            REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=str(status)).inc()
            REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(elapsed)
            if status >= 400:
                ERROR_COUNT.labels(method=method, endpoint=endpoint, status=str(status)).inc()

        level = logging.DEBUG if request.url.path in QUIET_PATHS else logging.INFO
        if status >= 500:
            level = logging.ERROR
        elif status >= 400:
            level = logging.WARNING
        logger.log(
            level,
            "request",
            extra={
                "method": method,
                "path": request.url.path,
                "status": status,
                "duration_ms": round(elapsed * 1000, 2),
            },
        )


@app.get("/")
async def root() -> dict:
    """Return basic application information."""
    return {
        "message": "Hello from DevOps Task!",
        "status": "running",
        "version": APP_VERSION,
    }


@app.get("/health")
async def health() -> dict:
    """Liveness / readiness check."""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/metrics")
async def metrics() -> Response:
    """Expose Prometheus-format metrics."""
    return Response(content=generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)
