from __future__ import annotations

import re

from mosint.models import EmailIdentity

# Pragmatic RFC 5321 / 5322 subset used by OSINT tools: local@idn-or-ascii-domain.
EMAIL_RE = re.compile(
    r"^(?P<local>[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+)@"
    r"(?P<domain>(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+"
    r"[A-Za-z]{2,}|localhost)$"
)

DISPOSABLE_DOMAINS = frozenset(
    {
        "10minutemail.com",
        "guerrillamail.com",
        "guerrillamail.net",
        "mailinator.com",
        "tempmail.com",
        "temp-mail.org",
        "throwawaymail.com",
        "yopmail.com",
        "getnada.com",
        "sharklasers.com",
        "trashmail.com",
        "maildrop.cc",
        "discard.email",
        "fakeinbox.com",
        "moakt.com",
        "emailondeck.com",
        "mintemail.com",
        "mytemp.email",
        "tempail.com",
        "mailnesia.com",
        "dispostable.com",
        "getairmail.com",
        "inboxbear.com",
        "spamgourmet.com",
        "mailcatch.com",
        "tmpeml.com",
        "dropmail.me",
    }
)

GMAIL_DOMAINS = frozenset({"gmail.com", "googlemail.com"})


def parse_email(raw: str) -> EmailIdentity:
    value = (raw or "").strip().lower()
    match = EMAIL_RE.match(value)
    if not match:
        return EmailIdentity(
            original=raw.strip() if raw else "",
            local="",
            domain="",
            canonical="",
            syntax_valid=False,
            disposable=False,
            reason="Email syntax is not valid",
        )
    local = match.group("local")
    domain = match.group("domain").rstrip(".")
    canonical_local = local
    if domain in GMAIL_DOMAINS:
        plus = canonical_local.split("+", 1)[0]
        canonical_local = plus.replace(".", "")
        domain = "gmail.com"
    canonical = f"{canonical_local}@{domain}"
    return EmailIdentity(
        original=value,
        local=local,
        domain=domain,
        canonical=canonical,
        syntax_valid=True,
        disposable=domain in DISPOSABLE_DOMAINS,
    )


def username_candidates(identity: EmailIdentity) -> list[str]:
    """Derive likely social handles from the local-part without guessing wildly."""
    if not identity.syntax_valid:
        return []
    local = identity.local.split("+", 1)[0]
    seen: list[str] = []
    for candidate in (
        local,
        local.replace(".", ""),
        local.replace(".", "-"),
        local.replace("_", ""),
        identity.canonical.split("@", 1)[0],
    ):
        cleaned = re.sub(r"[^A-Za-z0-9._-]", "", candidate)
        if len(cleaned) < 2 or cleaned in seen:
            continue
        seen.append(cleaned)
    return seen[:4]
