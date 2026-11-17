"""Structured JSON logging configuration."""

import logging
import sys

from pythonjsonlogger import jsonlogger


class _Formatter(jsonlogger.JsonFormatter):
    """JSON formatter with a lowercase level, used as a Loki label (info, error...)."""

    def process_log_record(self, log_record: dict) -> dict:
        # uvicorn's ANSI-coloured duplicate and asyncio task names are just noise
        log_record.pop("color_message", None)
        log_record.pop("taskName", None)
        if "level" in log_record:
            log_record["level"] = log_record["level"].lower()
        return log_record


def setup_logging(level: str = "info") -> None:
    """Send all logs, including uvicorn's, to stdout as JSON.

    Args:
        level: Logging level name (e.g. "info", "debug", "warning").
    """
    handler = logging.StreamHandler(stream=sys.stdout)
    handler.setFormatter(
        _Formatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            rename_fields={"asctime": "timestamp", "levelname": "level"},
            datefmt="%Y-%m-%dT%H:%M:%S%z",
        )
    )

    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(getattr(logging, level.upper(), logging.INFO))

    # uvicorn installs its own plain-text handlers before importing the app;
    # route its logs through the JSON handler instead.
    for name in ("uvicorn", "uvicorn.error"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers.clear()
        uv_logger.propagate = True

    # The app writes its own access log with method, path, status and duration
    logging.getLogger("uvicorn.access").disabled = True
