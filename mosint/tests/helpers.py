"""Shared test doubles."""

from __future__ import annotations

import json as _json
from dataclasses import dataclass, field
from typing import Any


class FakeResponse:
    def __init__(self, status_code: int = 200, payload: Any = None, text: str = ""):
        self.status_code = status_code
        self._payload = payload
        self.text = text if text else (_json.dumps(payload) if payload is not None else "")

    def json(self):
        if self._payload is None:
            raise ValueError("no json")
        return self._payload


@dataclass
class FakeSession:
    """Records requests and returns queued responses (by call order or matcher)."""

    responses: list[FakeResponse] = field(default_factory=list)
    matcher: Any = None
    calls: list[dict[str, Any]] = field(default_factory=list)
    headers: dict[str, str] = field(default_factory=dict)

    def get(self, url, **kwargs):
        self.calls.append({"url": url, **kwargs})
        if self.matcher is not None:
            return self.matcher(url, **kwargs)
        if not self.responses:
            raise AssertionError(f"no queued response for GET {url}")
        return self.responses.pop(0)


# --- DNS doubles -----------------------------------------------------------

class FakeMX:
    def __init__(self, preference: int, exchange: str):
        self.preference = preference
        self.exchange = exchange


class FakeTXT:
    def __init__(self, value: str):
        self.strings = [value.encode("utf-8")]


class FakeResolver:
    """Maps (name, rdtype) -> list of records or an exception to raise."""

    def __init__(self, mapping: dict[tuple[str, str], Any]):
        self.mapping = mapping
        self.lifetime = 0.0
        self.timeout = 0.0

    def resolve(self, name: str, rdtype: str):
        key = (name.rstrip("."), rdtype)
        result = self.mapping.get(key)
        if result is None:
            import dns.resolver

            raise dns.resolver.NoAnswer()
        if isinstance(result, Exception):
            raise result
        return result
