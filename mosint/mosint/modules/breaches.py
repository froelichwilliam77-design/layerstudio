"""Public data-breach lookups via Have I Been Pwned and DeHashed.

Both providers require the caller's own API credentials. When they are absent
the corresponding lookup is skipped rather than failing the whole scan.
"""

from __future__ import annotations

from urllib.parse import quote

import requests

from .base import Module, ModuleResult, Status, Target

HIBP_ENDPOINT = "https://haveibeenpwned.com/api/v3/breachedaccount/{account}"
DEHASHED_ENDPOINT = "https://api.dehashed.com/search"

# Fields DeHashed may return that are sensitive and should be redactable.
SENSITIVE_FIELDS = ("password", "hashed_password")


class BreachModule(Module):
    """Query breach corpora for records tied to the target email."""

    name = "breaches"
    title = "Data breaches"

    def is_available(self) -> bool:
        return self.config.has_hibp or self.config.has_dehashed

    def run(self, target: Target) -> ModuleResult:
        if not self.is_available():
            return self._skipped(
                "No breach provider configured (set HIBP and/or DeHashed credentials)."
            )

        session = self.session or requests.Session()
        data: dict[str, object] = {}
        findings: list[str] = []
        errored = False

        if self.config.has_hibp:
            hibp = self._query_hibp(session, target)
            data["hibp"] = hibp
            if hibp.get("error"):
                errored = True
                findings.append(f"HIBP error: {hibp['error']}")
            else:
                breaches = hibp.get("breaches", [])
                findings.append(f"HIBP: {len(breaches)} breach(es).")
        else:
            findings.append("HIBP: skipped (no API key).")

        if self.config.has_dehashed:
            dehashed = self._query_dehashed(session, target)
            data["dehashed"] = dehashed
            if dehashed.get("error"):
                errored = True
                findings.append(f"DeHashed error: {dehashed['error']}")
            else:
                entries = dehashed.get("entries", [])
                findings.append(f"DeHashed: {len(entries)} record(s).")
        else:
            findings.append("DeHashed: skipped (no credentials).")

        found_any = bool(data.get("hibp", {}).get("breaches")) or bool(
            data.get("dehashed", {}).get("entries")
        )
        if errored and not found_any:
            status = Status.ERROR
        elif found_any:
            status = Status.OK
        else:
            status = Status.NOT_FOUND

        return ModuleResult(
            name=self.name,
            title=self.title,
            status=status,
            data=data,
            findings=findings,
        )

    def _query_hibp(self, session: requests.Session, target: Target) -> dict[str, object]:
        url = HIBP_ENDPOINT.format(account=quote(target.email, safe=""))
        headers = {"hibp-api-key": self.config.hibp_api_key or ""}
        try:
            resp = session.get(
                url,
                headers=headers,
                params={"truncateResponse": "false"},
                timeout=self.config.timeout,
            )
        except requests.RequestException as exc:
            return {"error": str(exc)}

        if resp.status_code == 404:
            return {"breaches": []}
        if resp.status_code == 401:
            return {"error": "unauthorized (invalid HIBP API key)"}
        if resp.status_code == 429:
            return {"error": "rate limited"}
        if resp.status_code != 200:
            return {"error": f"unexpected status {resp.status_code}"}

        try:
            payload = resp.json()
        except ValueError:
            return {"error": "invalid JSON from HIBP"}

        breaches = [
            {
                "name": item.get("Name"),
                "domain": item.get("Domain"),
                "breach_date": item.get("BreachDate"),
                "pwn_count": item.get("PwnCount"),
                "data_classes": item.get("DataClasses", []),
            }
            for item in payload
        ]
        return {"breaches": breaches}

    def _query_dehashed(self, session: requests.Session, target: Target) -> dict[str, object]:
        try:
            resp = session.get(
                DEHASHED_ENDPOINT,
                params={"query": f"email:{target.email}", "size": 100},
                headers={"Accept": "application/json"},
                auth=(self.config.dehashed_email or "", self.config.dehashed_api_key or ""),
                timeout=self.config.timeout,
            )
        except requests.RequestException as exc:
            return {"error": str(exc)}

        if resp.status_code == 401:
            return {"error": "unauthorized (invalid DeHashed credentials)"}
        if resp.status_code == 429:
            return {"error": "rate limited"}
        if resp.status_code != 200:
            return {"error": f"unexpected status {resp.status_code}"}

        try:
            payload = resp.json()
        except ValueError:
            return {"error": "invalid JSON from DeHashed"}

        raw_entries = payload.get("entries") or []
        entries = []
        for item in raw_entries:
            entries.append(
                {
                    "email": item.get("email"),
                    "username": item.get("username"),
                    "password": item.get("password"),
                    "hashed_password": item.get("hashed_password"),
                    "name": item.get("name"),
                    "database_name": item.get("database_name"),
                }
            )
        return {"entries": entries, "total": payload.get("total")}
