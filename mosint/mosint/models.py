from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any


@dataclass
class EmailIdentity:
    original: str
    local: str
    domain: str
    canonical: str
    syntax_valid: bool
    disposable: bool
    reason: str | None = None


@dataclass
class MxHost:
    preference: int
    host: str
    addresses: list[str] = field(default_factory=list)


@dataclass
class MailConfig:
    domain: str
    mx: list[MxHost] = field(default_factory=list)
    a: list[str] = field(default_factory=list)
    aaaa: list[str] = field(default_factory=list)
    ns: list[str] = field(default_factory=list)
    spf: list[str] = field(default_factory=list)
    dmarc: list[str] = field(default_factory=list)
    dkim: list[dict[str, str]] = field(default_factory=list)
    provider: str | None = None
    smtp_banner: str | None = None
    smtp_banner_error: str | None = None
    notes: list[str] = field(default_factory=list)
    error: str | None = None


@dataclass
class WhoisRecord:
    domain: str
    source: str | None = None
    registrar: str | None = None
    organization: str | None = None
    registrant: str | None = None
    email: str | None = None
    created: str | None = None
    expires: str | None = None
    updated: str | None = None
    nameservers: list[str] = field(default_factory=list)
    status: list[str] = field(default_factory=list)
    dnssec: str | None = None
    country: str | None = None
    raw_summary: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


@dataclass
class BreachHit:
    name: str
    title: str | None = None
    domain: str | None = None
    breach_date: str | None = None
    added_date: str | None = None
    data_classes: list[str] = field(default_factory=list)
    pwn_count: int | None = None
    source: str = "haveibeenpwned"


@dataclass
class PasteHit:
    source: str
    title: str | None = None
    date: str | None = None
    email_count: int | None = None


@dataclass
class DehashedEntry:
    username: str | None = None
    name: str | None = None
    email: str | None = None
    obtained_from: str | None = None
    password_present: bool = False
    password_hash_type: str | None = None


@dataclass
class BreachReport:
    hibp_skipped: str | None = None
    hibp_breaches: list[BreachHit] = field(default_factory=list)
    hibp_pastes: list[PasteHit] = field(default_factory=list)
    dehashed_skipped: str | None = None
    dehashed_entries: list[DehashedEntry] = field(default_factory=list)
    dehashed_usernames: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


@dataclass
class SocialProfile:
    platform: str
    url: str
    found: bool
    detail: str | None = None


@dataclass
class SocialReport:
    username_candidates: list[str] = field(default_factory=list)
    gravatar_hash: str | None = None
    profiles: list[SocialProfile] = field(default_factory=list)


@dataclass
class IpInfo:
    ip: str
    city: str | None = None
    region: str | None = None
    country: str | None = None
    org: str | None = None
    asn: str | None = None
    error: str | None = None


@dataclass
class RelatedEmail:
    value: str
    first_name: str | None = None
    last_name: str | None = None
    position: str | None = None
    department: str | None = None


@dataclass
class ScanResult:
    email: EmailIdentity
    mail: MailConfig
    whois: WhoisRecord
    breaches: BreachReport
    social: SocialReport
    ip: list[IpInfo] = field(default_factory=list)
    related_emails: list[RelatedEmail] = field(default_factory=list)
    related_skipped: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
