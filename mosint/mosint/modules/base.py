"""Base types shared by every OSINT module."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

import requests

from ..config import Config


class Status(str, Enum):
    """Outcome of running a module."""

    OK = "ok"
    NOT_FOUND = "not_found"
    SKIPPED = "skipped"
    ERROR = "error"


@dataclass
class ModuleResult:
    """Structured result returned by a module."""

    name: str
    title: str
    status: Status
    data: dict[str, Any] = field(default_factory=dict)
    findings: list[str] = field(default_factory=list)
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "title": self.title,
            "status": self.status.value,
            "data": self.data,
            "findings": self.findings,
            "error": self.error,
        }


@dataclass
class Target:
    """A parsed email target passed to each module."""

    email: str
    local_part: str
    domain: str


class Module:
    """Base class for OSINT modules.

    Subclasses implement :meth:`run`. They should never raise for expected
    conditions (missing keys, no records, HTTP errors); instead they return a
    :class:`ModuleResult` with the appropriate :class:`Status`.
    """

    name: str = "module"
    title: str = "Module"

    def __init__(self, config: Config, session: requests.Session | None = None) -> None:
        self.config = config
        self.session = session

    def is_available(self) -> bool:
        """Whether the module can run (e.g. required credentials present)."""

        return True

    def run(self, target: Target) -> ModuleResult:  # pragma: no cover - abstract
        raise NotImplementedError

    def _skipped(self, reason: str) -> ModuleResult:
        return ModuleResult(
            name=self.name,
            title=self.title,
            status=Status.SKIPPED,
            findings=[reason],
        )

    def _error(self, message: str) -> ModuleResult:
        return ModuleResult(
            name=self.name,
            title=self.title,
            status=Status.ERROR,
            error=message,
        )
