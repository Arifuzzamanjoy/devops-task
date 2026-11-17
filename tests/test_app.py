"""Unit tests for the FastAPI application endpoints."""

from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(name="client")
def fixture_client() -> TestClient:
    return TestClient(app)


def metric_lines(client: TestClient, name: str) -> list[str]:
    return [line for line in client.get("/metrics").text.splitlines() if line.startswith(name)]


class TestRootEndpoint:
    def test_returns_200(self, client: TestClient) -> None:
        assert client.get("/").status_code == 200

    def test_body(self, client: TestClient) -> None:
        body = client.get("/").json()
        assert body["message"] == "Hello from DevOps Task!"
        assert body["status"] == "running"
        assert body["version"]


class TestHealthEndpoint:
    def test_returns_200(self, client: TestClient) -> None:
        assert client.get("/health").status_code == 200

    def test_status_is_healthy(self, client: TestClient) -> None:
        assert client.get("/health").json()["status"] == "healthy"

    def test_timestamp_is_iso_format(self, client: TestClient) -> None:
        datetime.fromisoformat(client.get("/health").json()["timestamp"])


class TestMetricsEndpoint:
    def test_content_type_is_prometheus(self, client: TestClient) -> None:
        response = client.get("/metrics")
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/plain")

    def test_request_count_and_latency(self, client: TestClient) -> None:
        client.get("/")
        body = client.get("/metrics").text
        assert 'http_requests_total{endpoint="/",method="GET",status="200"}' in body
        assert "http_request_duration_seconds_bucket" in body

    def test_errors_are_counted(self, client: TestClient) -> None:
        client.get("/does-not-exist")
        assert any('status="404"' in line for line in metric_lines(client, "http_errors_total"))

    def test_unknown_paths_share_one_label(self, client: TestClient) -> None:
        for path in ("/wp-admin", "/.env", "/random/123"):
            client.get(path)
        endpoints = {line.split('endpoint="')[1].split('"')[0] for line in metric_lines(client, "http_requests_total{")}
        assert "unmatched" in endpoints
        assert not {"/wp-admin", "/.env", "/random/123"} & endpoints

    def test_metrics_endpoint_is_not_counted(self, client: TestClient) -> None:
        client.get("/metrics")
        assert not any('endpoint="/metrics"' in line for line in metric_lines(client, "http_requests_total"))
