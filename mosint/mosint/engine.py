from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed

import httpx

from mosint.config import MosintConfig
from mosint.models import EmailIdentity, ScanResult
from mosint.modules.breaches import USER_AGENT, collect_breaches
from mosint.modules.dns_mail import inspect_mail
from mosint.modules.enrichment import domain_ips, hunter_related, lookup_ip
from mosint.modules.social import scrape_social
from mosint.modules.validate import parse_email
from mosint.modules.whois_rdap import lookup_ownership


class InvalidEmailError(ValueError):
    pass


def _client(timeout: float) -> httpx.Client:
    return httpx.Client(
        timeout=timeout,
        follow_redirects=True,
        headers={"User-Agent": USER_AGENT},
    )


def scan_email(
    raw_email: str,
    config: MosintConfig,
    *,
    probe_smtp: bool = True,
    client: httpx.Client | None = None,
) -> ScanResult:
    identity = parse_email(raw_email)
    if not identity.syntax_valid:
        raise InvalidEmailError(identity.reason or "Invalid email")

    own_client = client is None
    http = client or _client(config.settings.timeout_seconds)
    try:
        with ThreadPoolExecutor(max_workers=5) as pool:
            mail_f = pool.submit(
                inspect_mail,
                identity.domain,
                config.settings.timeout_seconds,
                probe_smtp,
            )
            whois_f = pool.submit(
                lookup_ownership,
                identity.domain,
                http,
                config.settings.timeout_seconds,
            )
            social_f = pool.submit(scrape_social, identity, http)
            breach_f = pool.submit(
                collect_breaches,
                identity.original,
                hibp_key=config.hibp_api_key,
                dehashed_key=config.dehashed_api_key,
                client=http,
                dehashed_max_results=config.settings.dehashed_max_results,
            )
            hunter_f = pool.submit(hunter_related, identity.domain, config.hunter_api_key, http)

            mail = mail_f.result()
            whois = whois_f.result()
            social = social_f.result()
            breaches = breach_f.result()
            related, related_skip = hunter_f.result()

        mx_ips = [ip for mx in mail.mx for ip in mx.addresses]
        ip_targets = domain_ips(mail.a, mx_ips)
        ip_info = []
        if ip_targets:
            with ThreadPoolExecutor(max_workers=3) as pool:
                futures = [pool.submit(lookup_ip, ip, http) for ip in ip_targets]
                for fut in as_completed(futures):
                    ip_info.append(fut.result())
            ip_info.sort(key=lambda item: item.ip)

        return ScanResult(
            email=identity,
            mail=mail,
            whois=whois,
            breaches=breaches,
            social=social,
            ip=ip_info,
            related_emails=related,
            related_skipped=related_skip,
        )
    finally:
        if own_client:
            http.close()


def describe_identity(identity: EmailIdentity) -> str:
    bits = [identity.original]
    if identity.canonical != identity.original:
        bits.append(f"canonical {identity.canonical}")
    if identity.disposable:
        bits.append("disposable domain")
    return " · ".join(bits)
