from __future__ import annotations

import re
import socket
from typing import Iterable

import dns.exception
import dns.resolver

from mosint.models import MailConfig, MxHost

COMMON_DKIM_SELECTORS = (
    "google",
    "default",
    "selector1",
    "selector2",
    "k1",
    "s1",
    "s2",
    "mail",
    "dkim",
    "smtp",
)

PROVIDER_HINTS: tuple[tuple[str, str], ...] = (
    ("google.com", "Google Workspace / Gmail"),
    ("googlemail.com", "Google Workspace / Gmail"),
    ("outlook.com", "Microsoft 365"),
    ("protection.outlook.com", "Microsoft 365"),
    ("pphosted.com", "Proofpoint"),
    ("proofpoint.com", "Proofpoint"),
    ("mimecast.com", "Mimecast"),
    ("zoho.com", "Zoho Mail"),
    ("zoho.eu", "Zoho Mail"),
    ("protonmail.ch", "Proton Mail"),
    ("yahoodns.net", "Yahoo"),
    ("icloud.com", "iCloud"),
    ("messagingengine.com", "Fastmail"),
    ("emailsrvr.com", "Rackspace Email"),
    ("secureserver.net", "GoDaddy"),
    ("mailgun.org", "Mailgun"),
    ("sendgrid.net", "SendGrid"),
    ("amazonses.com", "Amazon SES"),
)


def _resolver(timeout: float) -> dns.resolver.Resolver:
    resolver = dns.resolver.Resolver()
    resolver.lifetime = timeout
    resolver.timeout = timeout
    return resolver


def _txt_strings(rdata) -> str:
    try:
        parts = [s.decode("utf-8", "replace") if isinstance(s, bytes) else str(s) for s in rdata.strings]
        return "".join(parts)
    except Exception:
        return str(rdata).strip('"')


def _records(resolver: dns.resolver.Resolver, name: str, rdtype: str) -> list:
    try:
        return list(resolver.resolve(name, rdtype))
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers, dns.exception.Timeout):
        return []
    except dns.exception.DNSException:
        return []


def _dkim_has_key(record: str) -> bool:
    """True only when a DKIM TXT record includes a non-empty public key."""
    if "v=dkim1" not in record.lower():
        return False
    match = re.search(r"(?:^|;)\s*p=([A-Za-z0-9+/]*)", record, re.I)
    return bool(match and match.group(1))


def infer_provider(mx_hosts: Iterable[str]) -> str | None:
    joined = " ".join(h.lower().rstrip(".") for h in mx_hosts)
    for needle, label in PROVIDER_HINTS:
        if needle in joined:
            return label
    return None


def _resolve_host_ips(resolver: dns.resolver.Resolver, host: str) -> list[str]:
    addrs: list[str] = []
    for rdtype in ("A", "AAAA"):
        for rr in _records(resolver, host, rdtype):
            addrs.append(rr.to_text())
    return addrs


def grab_smtp_banner(host: str, timeout: float = 4.0) -> tuple[str | None, str | None]:
    """Read the SMTP 220 banner. Port 25 is often blocked on cloud networks."""
    try:
        with socket.create_connection((host, 25), timeout=timeout) as sock:
            sock.settimeout(timeout)
            banner = sock.recv(512).decode("utf-8", "replace").strip()
            try:
                sock.sendall(b"QUIT\r\n")
            except OSError:
                pass
            return (banner or None, None)
    except OSError as exc:
        return (None, str(exc))


def inspect_mail(domain: str, timeout: float = 12.0, probe_smtp: bool = True) -> MailConfig:
    resolver = _resolver(timeout)
    result = MailConfig(domain=domain)

    try:
        mx_records = []
        null_mx = False
        for rr in _records(resolver, domain, "MX"):
            host = str(rr.exchange).rstrip(".")
            if not host:
                null_mx = True
                continue
            mx_records.append(
                MxHost(
                    preference=int(rr.preference),
                    host=host,
                    addresses=_resolve_host_ips(resolver, host),
                )
            )
        result.mx = sorted(mx_records, key=lambda item: (item.preference, item.host))
        if null_mx:
            result.notes.append("Null MX (RFC 7505) — this domain does not accept mail.")
        result.a = [rr.to_text() for rr in _records(resolver, domain, "A")]
        result.aaaa = [rr.to_text() for rr in _records(resolver, domain, "AAAA")]
        result.ns = sorted({str(rr.target).rstrip(".") for rr in _records(resolver, domain, "NS")})

        txt = [_txt_strings(rr) for rr in _records(resolver, domain, "TXT")]
        result.spf = [t for t in txt if t.lower().startswith("v=spf1")]

        dmarc_txt = [_txt_strings(rr) for rr in _records(resolver, f"_dmarc.{domain}", "TXT")]
        result.dmarc = [t for t in dmarc_txt if "v=dmarc1" in t.lower()]

        empty_dkim: list[str] = []
        for selector in COMMON_DKIM_SELECTORS:
            name = f"{selector}._domainkey.{domain}"
            records = [_txt_strings(rr) for rr in _records(resolver, name, "TXT")]
            for record in records:
                if _dkim_has_key(record):
                    result.dkim.append({"selector": selector, "record": record})
                elif "v=dkim1" in record.lower():
                    empty_dkim.append(selector)
        if empty_dkim:
            result.notes.append(
                "DKIM selectors published with empty p= (no public key): " + ", ".join(empty_dkim)
            )

        result.provider = infer_provider(mx.host for mx in result.mx)

        if not result.mx and not null_mx:
            result.notes.append("No MX records — domain cannot receive mail unless it uses an A/AAAA fallback.")
        if not result.spf:
            result.notes.append("No SPF TXT record.")
        if not result.dmarc:
            result.notes.append("No DMARC record at _dmarc.")
        if not result.dkim and not empty_dkim:
            result.notes.append("No common DKIM selectors published (google/default/selector1/selector2/k1).")

        if probe_smtp and result.mx:
            banner, err = grab_smtp_banner(result.mx[0].host, timeout=min(timeout, 4.0))
            result.smtp_banner = banner
            result.smtp_banner_error = err
    except Exception as exc:  # noqa: BLE001 — surface DNS failures in the report
        result.error = str(exc)
    return result
