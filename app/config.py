"""Application configuration loaded from environment variables."""

import os
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Config:
    """Immutable application configuration sourced from environment variables."""

    app_port: int = field(default_factory=lambda: int(os.getenv("APP_PORT", "8080")))
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "info").lower())
    environment: str = field(default_factory=lambda: os.getenv("ENVIRONMENT", "development"))


def get_config() -> Config:
    """Return a new Config instance reflecting current environment variables."""
    return Config()
