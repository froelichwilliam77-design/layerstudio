"""Email syntax validation and classification."""

from __future__ import annotations

import re

from .base import Module, ModuleResult, Status, Target

# Pragmatic RFC 5322-inspired pattern: good enough to reject obvious junk while
# accepting the addresses seen in the wild. Full RFC compliance is intentionally
# out of scope.
_EMAIL_RE = re.compile(
    r"^(?P<local>[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+"
    r"(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*)"
    r"@(?P<domain>(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+"
    r"[A-Za-z]{2,63})$"
)

# A small, well-known sample of disposable/temporary mail providers.
DISPOSABLE_DOMAINS = frozenset(
    {
        "mailinator.com",
        "guerrillamail.com",
        "10minutemail.com",
        "temp-mail.org",
        "throwawaymail.com",
        "yopmail.com",
        "getnada.com",
        "trashmail.com",
        "sharklasers.com",
        "dispostable.com",
    }
)

# Common role-based mailbox prefixes (not tied to a single human).
ROLE_LOCAL_PARTS = frozenset(
    {
        "admin",
        "administrator",
        "info",
        "support",
        "sales",
        "contact",
        "help",
        "noreply",
        "no-reply",
        "postmaster",
        "webmaster",
        "abuse",
        "security",
        "billing",
        "hello",
        "team",
    }
)


class InvalidEmailError(ValueError):
    """Raised when an email address cannot be parsed."""


def parse_email(email: str) -> Target:
    """Validate ``email`` and return a :class:`Target`.

    Raises :class:`InvalidEmailError` when the address is syntactically invalid.
    """

    candidate = (email or "").strip()
    match = _EMAIL_RE.match(candidate)
    if not match:
        raise InvalidEmailError(f"'{email}' is not a valid email address")
    local = match.group("local")
    domain = match.group("domain").lower()
    return Target(email=f"{local}@{domain}", local_part=local, domain=domain)


class EmailValidationModule(Module):
    """Classify the email address itself (syntax, disposable, role account)."""

    name = "validation"
    title = "Email validation"

    def run(self, target: Target) -> ModuleResult:
        is_disposable = target.domain in DISPOSABLE_DOMAINS
        is_role = target.local_part.lower() in ROLE_LOCAL_PARTS

        findings = ["Syntax is valid."]
        if is_disposable:
            findings.append("Domain is a known disposable/temporary mail provider.")
        if is_role:
            findings.append("Local part looks like a role account (not a single person).")

        return ModuleResult(
            name=self.name,
            title=self.title,
            status=Status.OK,
            data={
                "email": target.email,
                "local_part": target.local_part,
                "domain": target.domain,
                "is_disposable": is_disposable,
                "is_role_account": is_role,
            },
            findings=findings,
        )
