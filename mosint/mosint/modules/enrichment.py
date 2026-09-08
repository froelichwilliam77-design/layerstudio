from __future__ import annotations

import httpx

from mosint.models import IpInfo, RelatedEmail


def lookup_ip(ip: str, client: httpx.Client) -> IpInfo:
    url = f"https://ipapi.co/{ip}/json/"
    try:
        response = client.get(url)
        if response.status_code != 200:
            return IpInfo(ip=ip, error=f"HTTP {response.status_code}")
        data = response.json()
        if data.get("error"):
            return IpInfo(ip=ip, error=str(data.get("reason") or data["error"]))
        return IpInfo(
            ip=ip,
            city=data.get("city"),
            region=data.get("region"),
            country=data.get("country_name") or data.get("country"),
            org=data.get("org"),
            asn=data.get("asn"),
        )
    except (httpx.HTTPError, ValueError) as exc:
        return IpInfo(ip=ip, error=str(exc))


def domain_ips(a_records: list[str], mx_addresses: list[str], limit: int = 3) -> list[str]:
    ordered: list[str] = []
    for ip in [*a_records, *mx_addresses]:
        if ip and ip not in ordered:
            ordered.append(ip)
        if len(ordered) >= limit:
            break
    return ordered


def hunter_related(domain: str, api_key: str, client: httpx.Client) -> tuple[list[RelatedEmail], str | None]:
    if not api_key:
        return ([], "Hunter.io skipped — set hunter_api_key in ~/.mosint.yaml")
    try:
        response = client.get(
            "https://api.hunter.io/v2/domain-search",
            params={"domain": domain, "api_key": api_key, "limit": 10},
        )
        if response.status_code in {401, 403}:
            return ([], "Hunter.io rejected the API key")
        response.raise_for_status()
        data = response.json().get("data") or {}
        emails = []
        for item in data.get("emails") or []:
            value = item.get("value")
            if not value:
                continue
            emails.append(
                RelatedEmail(
                    value=value,
                    first_name=item.get("first_name"),
                    last_name=item.get("last_name"),
                    position=item.get("position"),
                    department=item.get("department"),
                )
            )
        return (emails, None)
    except httpx.HTTPError as exc:
        return ([], f"Hunter.io error: {exc}")
