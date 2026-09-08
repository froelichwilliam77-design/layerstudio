"""Rendering of scan reports as text or JSON."""

from __future__ import annotations

import copy
import json

from .modules.base import Status
from .modules.breaches import SENSITIVE_FIELDS
from .orchestrator import Report

REDACTED = "[REDACTED]"

_STATUS_LABEL = {
    Status.OK.value: "OK",
    Status.NOT_FOUND.value: "none",
    Status.SKIPPED.value: "skip",
    Status.ERROR.value: "ERR",
}


def redact_report_dict(report: dict) -> dict:
    """Return a deep copy of a report dict with breach secrets redacted."""

    clone = copy.deepcopy(report)
    for result in clone.get("results", []):
        if result.get("name") != "breaches":
            continue
        dehashed = (result.get("data") or {}).get("dehashed") or {}
        for entry in dehashed.get("entries") or []:
            for field_name in SENSITIVE_FIELDS:
                if entry.get(field_name):
                    entry[field_name] = REDACTED
    return clone


def render_json(report: Report, *, show_secrets: bool = False, indent: int = 2) -> str:
    data = report.to_dict()
    if not show_secrets:
        data = redact_report_dict(data)
    return json.dumps(data, indent=indent, ensure_ascii=False)


def _render_breach_findings(data: dict, show_secrets: bool) -> list[str]:
    lines: list[str] = []
    hibp = data.get("hibp") or {}
    for breach in hibp.get("breaches") or []:
        classes = ", ".join(breach.get("data_classes") or [])
        lines.append(
            f"      - HIBP {breach.get('name')} ({breach.get('breach_date')}): {classes}"
        )
    dehashed = data.get("dehashed") or {}
    for entry in dehashed.get("entries") or []:
        password = entry.get("password")
        if password and not show_secrets:
            password = REDACTED
        bits = []
        if entry.get("username"):
            bits.append(f"user={entry['username']}")
        if password:
            bits.append(f"password={password}")
        if entry.get("hashed_password"):
            hashed = entry["hashed_password"] if show_secrets else REDACTED
            bits.append(f"hash={hashed}")
        if entry.get("database_name"):
            bits.append(f"db={entry['database_name']}")
        lines.append("      - DeHashed " + " ".join(bits))
    return lines


def render_text(report: Report, *, show_secrets: bool = False) -> str:
    lines: list[str] = []
    lines.append(f"Mosint report for {report.email}")
    lines.append(f"Completed in {report.duration:.2f}s")
    lines.append("=" * 60)

    for result in report.results:
        label = _STATUS_LABEL.get(result.status.value, result.status.value)
        lines.append(f"[{label:>4}] {result.title}")
        if result.error:
            lines.append(f"      ! {result.error}")
        for finding in result.findings:
            lines.append(f"      - {finding}")
        if result.name == "breaches" and result.status == Status.OK:
            lines.extend(_render_breach_findings(result.data, show_secrets))
        lines.append("")

    if not show_secrets:
        lines.append("(secrets redacted; pass --show-secrets to reveal)")
    return "\n".join(lines).rstrip() + "\n"
