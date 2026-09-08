"""Domain ownership lookup for the email's domain via RDAP.

RDAP (RFC 7483) is the structured, JSON successor to WHOIS. We use the IANA
RDAP bootstrap service so no per-TLD server list has to be maintained.
"""

from __future__ import annotations

import requests

from .base import Module, ModuleResult, Status, Target

RDAP_BOOTSTRAP = "https://rdap.org/domain/{domain}"


def _extract_registrar(entities: list[dict]) -> str | None:
    for entity in entities:
        roles = entity.get("roles") or []
        if "registrar" in roles:
            vcard = entity.get("vcardArray")
            name = _vcard_field(vcard, "fn")
            if name:
                return name
    return None


def _extract_registrant_org(entities: list[dict]) -> str | None:
    for entity in entities:
        roles = entity.get("roles") or []
        if "registrant" in roles:
            vcard = entity.get("vcardArray")
            return _vcard_field(vcard, "org") or _vcard_field(vcard, "fn")
    return None


def _vcard_field(vcard, field_name: str) -> str | None:
    # vcardArray is ["vcard", [[name, params, type, value], ...]]
    if not vcard or len(vcard) < 2:
        return None
    for entry in vcard[1]:
        if len(entry) >= 4 and entry[0] == field_name:
            value = entry[3]
            if isinstance(value, list):
                value = " ".join(str(v) for v in value if v)
            return str(value) if value else None
    return None


def _events(events: list[dict]) -> dict[str, str]:
    result: dict[str, str] = {}
    for event in events:
        action = event.get("eventAction")
        date = event.get("eventDate")
        if action and date:
            result[action] = date
    return result


class DomainModule(Module):
    """Look up domain registration/ownership records via RDAP."""

    name = "domain"
    title = "Domain ownership"

    def run(self, target: Target) -> ModuleResult:
        session = self.session or requests.Session()
        url = RDAP_BOOTSTRAP.format(domain=target.domain)
        try:
            resp = session.get(
                url,
                timeout=self.config.timeout,
                headers={"Accept": "application/rdap+json, application/json"},
            )
        except requests.RequestException as exc:
            return self._error(f"RDAP lookup failed: {exc}")

        if resp.status_code == 404:
            return ModuleResult(
                name=self.name,
                title=self.title,
                status=Status.NOT_FOUND,
                data={"domain": target.domain},
                findings=["No RDAP record for the domain."],
            )
        if resp.status_code != 200:
            return self._error(f"RDAP returned status {resp.status_code}")

        try:
            payload = resp.json()
        except ValueError:
            return self._error("invalid JSON from RDAP")

        entities = payload.get("entities") or []
        events = _events(payload.get("events") or [])
        registrar = _extract_registrar(entities)
        registrant_org = _extract_registrant_org(entities)
        statuses = payload.get("status") or []
        nameservers = [ns.get("ldhName") for ns in (payload.get("nameservers") or []) if ns.get("ldhName")]

        findings = []
        if registrar:
            findings.append(f"Registrar: {registrar}.")
        if registrant_org:
            findings.append(f"Registrant org: {registrant_org}.")
        if events.get("registration"):
            findings.append(f"Registered: {events['registration']}.")
        if not findings:
            findings.append("RDAP record found (ownership fields redacted by registry).")

        return ModuleResult(
            name=self.name,
            title=self.title,
            status=Status.OK,
            data={
                "domain": target.domain,
                "registrar": registrar,
                "registrant_org": registrant_org,
                "events": events,
                "status": statuses,
                "nameservers": nameservers,
            },
            findings=findings,
        )
