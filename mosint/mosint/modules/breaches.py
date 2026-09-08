from __future__ import annotations

from urllib.parse import quote

import httpx

from mosint.models import BreachHit, BreachReport, DehashedEntry, PasteHit

USER_AGENT = "mosint/1.0 (email OSINT research; +https://github.com/alpkeskin/mosint)"

PASSWORD_KEYS = frozenset(
    {
        "password",
        "hashed_password",
        "hashedpassword",
        "hash",
        "passwd",
        "pass",
        "secret",
        "plaintext",
    }
)


def infer_hash_type(value: str) -> str | None:
    text = value.strip()
    if not text:
        return None
    lower = text.lower()
    if lower.startswith("$2a$") or lower.startswith("$2b$") or lower.startswith("$2y$"):
        return "bcrypt"
    if lower.startswith("$argon2"):
        return "argon2"
    if lower.startswith("$1$"):
        return "md5crypt"
    hexish = all(c in "0123456789abcdefABCDEF" for c in text)
    if hexish and len(text) == 32:
        return "md5"
    if hexish and len(text) == 40:
        return "sha1"
    if hexish and len(text) == 64:
        return "sha256"
    return "unknown"


def sanitize_dehashed_record(record: dict) -> DehashedEntry:
    """Keep usernames / sources. Never copy password or hash material into the report."""
    password_present = False
    hash_type: str | None = None
    for key, value in record.items():
        if str(key).lower().replace(" ", "_") not in PASSWORD_KEYS:
            continue
        if value:
            password_present = True
            if str(key).lower() in {"hashed_password", "hashedpassword", "hash"} and isinstance(value, str):
                hash_type = infer_hash_type(value)
    obtained = record.get("obtained_from") or record.get("database_name") or record.get("database")
    return DehashedEntry(
        username=_clean(record.get("username") or record.get("user")),
        name=_clean(record.get("name") or record.get("full_name")),
        email=_clean(record.get("email")),
        obtained_from=_clean(obtained),
        password_present=password_present,
        password_hash_type=hash_type,
    )


def _clean(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def query_hibp(email: str, api_key: str, client: httpx.Client) -> tuple[list[BreachHit], list[PasteHit], str | None]:
    if not api_key:
        return ([], [], "HaveIBeenPwned skipped — set haveibeenpwned_api_key in ~/.mosint.yaml")

    headers = {
        "hibp-api-key": api_key,
        "user-agent": USER_AGENT,
    }
    breaches: list[BreachHit] = []
    pastes: list[PasteHit] = []
    encoded = quote(email, safe="")
    try:
        response = client.get(
            f"https://haveibeenpwned.com/api/v3/breachedaccount/{encoded}",
            params={"truncateResponse": "false"},
            headers=headers,
        )
        if response.status_code == 404:
            pass
        elif response.status_code == 401:
            return ([], [], "HaveIBeenPwned rejected the API key")
        else:
            response.raise_for_status()
            for item in response.json() or []:
                breaches.append(
                    BreachHit(
                        name=str(item.get("Name") or ""),
                        title=item.get("Title"),
                        domain=item.get("Domain"),
                        breach_date=item.get("BreachDate"),
                        added_date=item.get("AddedDate"),
                        data_classes=list(item.get("DataClasses") or []),
                        pwn_count=item.get("PwnCount"),
                    )
                )
    except httpx.HTTPError as exc:
        return ([], [], f"HaveIBeenPwned error: {exc}")

    try:
        paste_resp = client.get(
            f"https://haveibeenpwned.com/api/v3/pasteaccount/{encoded}",
            headers=headers,
        )
        if paste_resp.status_code == 200:
            for item in paste_resp.json() or []:
                pastes.append(
                    PasteHit(
                        source=str(item.get("Source") or "paste"),
                        title=item.get("Title"),
                        date=item.get("Date"),
                        email_count=item.get("EmailCount"),
                    )
                )
        elif paste_resp.status_code not in {404, 401}:
            paste_resp.raise_for_status()
    except httpx.HTTPError:
        pass

    return (breaches, pastes, None)


def query_dehashed(email: str, api_key: str, client: httpx.Client, max_results: int = 25) -> tuple[list[DehashedEntry], str | None]:
    if not api_key:
        return ([], "DeHashed skipped — set dehashed_api_key in ~/.mosint.yaml")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    }
    payload = {
        "query": f'email:"{email}"',
        "page": 1,
        "size": max(1, min(max_results, 100)),
        "wildcard": False,
        "regex": False,
        "de_dupe": True,
    }
    try:
        response = client.post("https://api.dehashed.com/v2/search", headers=headers, json=payload)
        if response.status_code in {401, 403}:
            return ([], "DeHashed rejected the API key")
        response.raise_for_status()
        data = response.json()
        if isinstance(data, dict):
            entries = data.get("entries") or []
        elif isinstance(data, list):
            entries = data
        else:
            entries = []
        sanitized = [sanitize_dehashed_record(item) for item in entries if isinstance(item, dict)]
        return (sanitized, None)
    except httpx.HTTPError as exc:
        return ([], f"DeHashed error: {exc}")


def collect_breaches(
    email: str,
    *,
    hibp_key: str,
    dehashed_key: str,
    client: httpx.Client,
    dehashed_max_results: int = 25,
) -> BreachReport:
    report = BreachReport(
        notes=[
            "HaveIBeenPwned returns breach names and data classes, not passwords.",
            "DeHashed usernames are included when an API key is set; password values are never stored or printed.",
        ]
    )
    breaches, pastes, hibp_skip = query_hibp(email, hibp_key, client)
    report.hibp_breaches = breaches
    report.hibp_pastes = pastes
    report.hibp_skipped = hibp_skip

    entries, dehashed_skip = query_dehashed(email, dehashed_key, client, max_results=dehashed_max_results)
    report.dehashed_entries = entries
    report.dehashed_skipped = dehashed_skip
    usernames = []
    for entry in entries:
        if entry.username and entry.username not in usernames:
            usernames.append(entry.username)
    report.dehashed_usernames = usernames
    return report
