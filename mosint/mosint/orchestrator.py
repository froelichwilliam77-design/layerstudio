"""Scan orchestration: run the selected modules against a target email."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Iterable

import requests

from .config import Config
from .http import build_session
from .modules import ALL_MODULES, MODULES_BY_NAME
from .modules.base import Module, ModuleResult, Status, Target
from .modules.validation import parse_email


@dataclass
class Report:
    """Aggregated result of a scan."""

    email: str
    results: list[ModuleResult] = field(default_factory=list)
    started_at: float = 0.0
    finished_at: float = 0.0

    @property
    def duration(self) -> float:
        return max(0.0, self.finished_at - self.started_at)

    def to_dict(self) -> dict:
        return {
            "email": self.email,
            "duration_seconds": round(self.duration, 3),
            "results": [result.to_dict() for result in self.results],
        }


def select_modules(names: Iterable[str] | None) -> list[type[Module]]:
    """Resolve module names to classes, preserving the canonical order.

    ``names`` of ``None`` selects every module. Unknown names raise
    :class:`KeyError`.
    """

    if names is None:
        return list(ALL_MODULES)
    requested = set(names)
    unknown = requested - set(MODULES_BY_NAME)
    if unknown:
        raise KeyError(", ".join(sorted(unknown)))
    return [cls for cls in ALL_MODULES if cls.name in requested]


class Scanner:
    """Runs modules against a target and produces a :class:`Report`."""

    def __init__(
        self,
        config: Config,
        modules: list[type[Module]] | None = None,
        session: requests.Session | None = None,
    ) -> None:
        self.config = config
        self.module_classes = modules if modules is not None else list(ALL_MODULES)
        self.session = session or build_session(config)

    def scan(self, email: str) -> Report:
        target: Target = parse_email(email)
        report = Report(email=target.email, started_at=time.monotonic())

        for module_cls in self.module_classes:
            module = module_cls(self.config, self.session)
            if not module.is_available():
                report.results.append(
                    ModuleResult(
                        name=module.name,
                        title=module.title,
                        status=Status.SKIPPED,
                        findings=["Module unavailable (missing dependency or credentials)."],
                    )
                )
                continue
            try:
                result = module.run(target)
            except Exception as exc:  # defensive: a module must never crash the scan
                result = ModuleResult(
                    name=module.name,
                    title=module.title,
                    status=Status.ERROR,
                    error=f"unexpected error: {exc}",
                )
            report.results.append(result)

        report.finished_at = time.monotonic()
        return report
