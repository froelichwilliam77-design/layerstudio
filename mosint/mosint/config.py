from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG_NAME = ".mosint.yaml"


@dataclass
class Settings:
    timeout_seconds: float = 12.0
    dehashed_max_results: int = 25


@dataclass
class MosintConfig:
    hibp_api_key: str = ""
    dehashed_api_key: str = ""
    hunter_api_key: str = ""
    settings: Settings = None  # type: ignore[assignment]
    path: Path | None = None

    def __post_init__(self) -> None:
        if self.settings is None:
            self.settings = Settings()


def _str_key(data: dict[str, Any], *names: str) -> str:
    for name in names:
        value = data.get(name)
        if isinstance(value, str) and value.strip() and not value.upper().startswith("SET_YOUR"):
            return value.strip()
    return ""


def default_config_path() -> Path:
    return Path.home() / DEFAULT_CONFIG_NAME


def load_config(path: str | Path | None = None) -> MosintConfig:
    """Load optional YAML config. Missing files are fine — APIs are skipped."""
    candidates: list[Path] = []
    if path:
        candidates.append(Path(path).expanduser())
    env_path = os.environ.get("MOSINT_CONFIG")
    if env_path:
        candidates.append(Path(env_path).expanduser())
    candidates.append(default_config_path())
    candidates.append(Path.cwd() / DEFAULT_CONFIG_NAME)

    chosen: Path | None = None
    raw: dict[str, Any] = {}
    for candidate in candidates:
        if candidate.is_file():
            chosen = candidate
            loaded = yaml.safe_load(candidate.read_text(encoding="utf-8")) or {}
            if isinstance(loaded, dict):
                raw = loaded
            break

    services = raw.get("services") if isinstance(raw.get("services"), dict) else raw
    settings_raw = raw.get("settings") if isinstance(raw.get("settings"), dict) else {}

    timeout = settings_raw.get("timeout_seconds", 12)
    max_results = settings_raw.get("dehashed_max_results", 25)
    try:
        timeout_f = float(timeout)
    except (TypeError, ValueError):
        timeout_f = 12.0
    try:
        max_results_i = int(max_results)
    except (TypeError, ValueError):
        max_results_i = 25

    return MosintConfig(
        hibp_api_key=_str_key(services, "haveibeenpwned_api_key", "hibp_api_key")
        or os.environ.get("MOSINT_HIBP_API_KEY", "").strip(),
        dehashed_api_key=_str_key(services, "dehashed_api_key")
        or os.environ.get("MOSINT_DEHASHED_API_KEY", "").strip(),
        hunter_api_key=_str_key(services, "hunter_api_key")
        or os.environ.get("MOSINT_HUNTER_API_KEY", "").strip(),
        settings=Settings(timeout_seconds=timeout_f, dehashed_max_results=max_results_i),
        path=chosen,
    )
