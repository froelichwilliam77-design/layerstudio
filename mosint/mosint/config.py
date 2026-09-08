"""Configuration loading for Mosint.

Configuration is resolved from (in order of increasing precedence):
  1. built-in defaults
  2. a TOML config file (``config.toml`` by default)
  3. environment variables (``MOSINT_*``)
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping

DEFAULT_TIMEOUT = 15
DEFAULT_USER_AGENT = "mosint/0.1 (+authorized-osint)"


@dataclass
class Config:
    """Resolved runtime configuration."""

    hibp_api_key: str | None = None
    dehashed_email: str | None = None
    dehashed_api_key: str | None = None
    timeout: int = DEFAULT_TIMEOUT
    user_agent: str = DEFAULT_USER_AGENT
    extra: Mapping[str, Any] = field(default_factory=dict)

    @property
    def has_hibp(self) -> bool:
        return bool(self.hibp_api_key)

    @property
    def has_dehashed(self) -> bool:
        return bool(self.dehashed_email and self.dehashed_api_key)


def _load_toml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as handle:
        return tomllib.load(handle)


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


def load_config(config_path: str | os.PathLike[str] | None = None) -> Config:
    """Build a :class:`Config` from a TOML file overlaid with env vars.

    ``config_path`` may be omitted; when the default ``config.toml`` is absent
    the loader falls back to defaults + environment variables so the tool still
    runs (individual modules simply skip when their credentials are missing).
    """

    path = Path(config_path) if config_path is not None else Path("config.toml")
    data = _load_toml(path)

    api_keys = data.get("api_keys", {}) or {}
    http = data.get("http", {}) or {}

    hibp = _clean(os.environ.get("MOSINT_HIBP_API_KEY")) or _clean(api_keys.get("hibp"))
    dehashed_email = _clean(os.environ.get("MOSINT_DEHASHED_EMAIL")) or _clean(
        api_keys.get("dehashed_email")
    )
    dehashed_key = _clean(os.environ.get("MOSINT_DEHASHED_API_KEY")) or _clean(
        api_keys.get("dehashed_key")
    )

    timeout_raw = os.environ.get("MOSINT_TIMEOUT") or http.get("timeout") or DEFAULT_TIMEOUT
    try:
        timeout = int(timeout_raw)
    except (TypeError, ValueError):
        timeout = DEFAULT_TIMEOUT
    if timeout <= 0:
        timeout = DEFAULT_TIMEOUT

    user_agent = (
        _clean(os.environ.get("MOSINT_USER_AGENT"))
        or _clean(http.get("user_agent"))
        or DEFAULT_USER_AGENT
    )

    return Config(
        hibp_api_key=hibp,
        dehashed_email=dehashed_email,
        dehashed_api_key=dehashed_key,
        timeout=timeout,
        user_agent=user_agent,
        extra=data,
    )
