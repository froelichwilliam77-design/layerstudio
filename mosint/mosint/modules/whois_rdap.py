from __future__ import annotations

import json
import shutil
import subprocess
from typing import Any

import httpx

from mosint.models import WhoisRecord

RDAP_URLS = (
    "https://rdap.org/domain/{domain}",
    "https://rdap.verisign.com/com/v1/domain/{domain}",
)


def _first_str(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    if isinstance(value, list) and value:
        return _first_str(value[0])
    if isinstance(value, dict):
        for key in ("name", "fullName", "handle", "value"):
            if key in value:
                found = _first_str(value[key])
                if found:
                    return found
    return None


def _vcard_field(entity: dict[str, Any], field: str) -> str | None:
    vcard = entity.get("vcardArray")
    if not (isinstance(vcard, list) and len(vcard) >= 2 and isinstance(vcard[1], list)):
        return None
    for item in vcard[1]:
        if isinstance(item, list) and item and item[0] == field:
            return _first_str(item[-1])
    return None


def _parse_rdap(domain: str, data: dict[str, Any], source: str) -> WhoisRecord:
    record = WhoisRecord(domain=domain, source=source)
    record.status = [str(s) for s in data.get("status") or [] if s]
    record.nameservers = sorted(
        {
            str(ns.get("ldhName") or ns.get("unicodeName") or "").rstrip(".").lower()
            for ns in data.get("nameservers") or []
            if isinstance(ns, dict)
        }
        - {""}
    )
    events = {str(ev.get("eventAction")): str(ev.get("eventDate")) for ev in data.get("events") or [] if isinstance(ev, dict)}
    record.created = events.get("registration")
    record.expires = events.get("expiration")
    record.updated = events.get("last changed") or events.get("last update of RDAP database")
    secure = data.get("secureDNS") or {}
    if isinstance(secure, dict):
        record.dnssec = "enabled" if secure.get("delegationSigned") else "unsigned"

    for entity in data.get("entities") or []:
        if not isinstance(entity, dict):
            continue
        roles = {str(r).lower() for r in entity.get("roles") or []}
        name = _vcard_field(entity, "fn") or _first_str(entity.get("fn"))
        org = _vcard_field(entity, "org")
        email = _vcard_field(entity, "email")
        adr = _vcard_field(entity, "adr")
        if "registrar" in roles and name:
            record.registrar = record.registrar or name
        if "registrant" in roles:
            record.registrant = record.registrant or name
            record.organization = record.organization or org
            record.email = record.email or email
            record.country = record.country or adr

    record.raw_summary = {
        "handle": data.get("handle"),
        "ldhName": data.get("ldhName"),
        "port43": data.get("port43"),
    }
    return record


def lookup_rdap(domain: str, client: httpx.Client) -> WhoisRecord | None:
    last_error: str | None = None
    urls = [template.format(domain=domain) for template in RDAP_URLS]
    if not domain.endswith(".com"):
        urls = urls[:1]
    for url in urls:
        try:
            response = client.get(url, follow_redirects=True)
            if response.status_code == 404:
                last_error = f"RDAP 404 for {url}"
                continue
            response.raise_for_status()
            data = response.json()
            if isinstance(data, dict):
                return _parse_rdap(domain, data, source=url)
        except (httpx.HTTPError, json.JSONDecodeError, ValueError) as exc:
            last_error = str(exc)
    if last_error:
        return WhoisRecord(domain=domain, error=last_error)
    return None


def _parse_whois_text(domain: str, text: str) -> WhoisRecord:
    record = WhoisRecord(domain=domain, source="whois")
    mapping = {
        "registrar": ("Registrar:", "registrar:"),
        "registrant": ("Registrant Name:", "Registrant:"),
        "organization": ("Registrant Organization:", "OrgName:", "organisation:"),
        "email": ("Registrant Email:", "Org Abuse Email:", "e-mail:"),
        "created": ("Creation Date:", "created:"),
        "expires": ("Registry Expiry Date:", "paid-till:", "Expiry Date:"),
        "updated": ("Updated Date:", "last-modified:"),
        "country": ("Registrant Country:", "country:"),
        "dnssec": ("DNSSEC:",),
    }
    lines = text.splitlines()
    for attr, prefixes in mapping.items():
        for line in lines:
            for prefix in prefixes:
                if line.lower().startswith(prefix.lower()):
                    value = line.split(":", 1)[-1].strip()
                    if value:
                        setattr(record, attr, value)
                        break
    nameservers = []
    for line in lines:
        lower = line.lower().strip()
        if lower.startswith("name server:") or lower.startswith("nserver:"):
            host = line.split(":", 1)[-1].strip().split()[0].rstrip(".").lower()
            if host:
                nameservers.append(host)
    record.nameservers = sorted(set(nameservers))
    statuses = []
    for line in lines:
        if line.lower().startswith("domain status:"):
            statuses.append(line.split(":", 1)[-1].strip())
    record.status = statuses
    return record


def lookup_whois_cli(domain: str, timeout: float) -> WhoisRecord | None:
    binary = shutil.which("whois")
    if not binary:
        return None
    try:
        proc = subprocess.run(
            [binary, domain],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        text = (proc.stdout or "") + (proc.stderr or "")
        if not text.strip():
            return WhoisRecord(domain=domain, source="whois", error="empty whois response")
        return _parse_whois_text(domain, text)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return WhoisRecord(domain=domain, source="whois", error=str(exc))


def lookup_ownership(domain: str, client: httpx.Client, timeout: float = 12.0) -> WhoisRecord:
    rdap = lookup_rdap(domain, client)
    if rdap and not rdap.error and (rdap.registrar or rdap.nameservers or rdap.created):
        return rdap
    whois = lookup_whois_cli(domain, timeout=timeout)
    if whois and not whois.error:
        return whois
    if rdap:
        return rdap
    if whois:
        return whois
    return WhoisRecord(domain=domain, error="No RDAP or WHOIS data available")
