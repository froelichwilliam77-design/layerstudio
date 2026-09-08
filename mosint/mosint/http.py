"""Shared HTTP helpers."""

from __future__ import annotations

import requests

from .config import Config


def build_session(config: Config) -> requests.Session:
    """Create a :class:`requests.Session` seeded with the configured UA."""

    session = requests.Session()
    session.headers.update({"User-Agent": config.user_agent, "Accept": "application/json"})
    return session
