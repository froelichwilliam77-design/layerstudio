"""Mail server configuration checks: MX, SPF, DMARC, MTA-STS."""

from __future__ import annotations

from .base import Module, ModuleResult, Status, Target

try:  # dnspython is a hard dependency, but keep import failures graceful.
    import dns.exception
    import dns.resolver

    _DNS_AVAILABLE = True
except Exception:  # pragma: no cover - only hit when dependency missing
    _DNS_AVAILABLE = False


def _resolve_txt(domain: str, resolver: "dns.resolver.Resolver") -> list[str]:
    records: list[str] = []
    try:
        answers = resolver.resolve(domain, "TXT")
    except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
        return records
    except dns.exception.DNSException:
        return records
    for rdata in answers:
        # TXT records are a sequence of byte strings; join and decode.
        parts = getattr(rdata, "strings", None)
        if parts is not None:
            value = b"".join(parts).decode("utf-8", "replace")
        else:  # pragma: no cover - defensive
            value = str(rdata).strip('"')
        records.append(value)
    return records


class MailServerModule(Module):
    """Inspect MX records and the domain's email authentication posture."""

    name = "mailserver"
    title = "Mail server configuration"

    def __init__(self, config, session=None, resolver=None) -> None:
        super().__init__(config, session)
        self._resolver = resolver

    def is_available(self) -> bool:
        return _DNS_AVAILABLE

    def _get_resolver(self):
        if self._resolver is not None:
            return self._resolver
        resolver = dns.resolver.Resolver()
        resolver.lifetime = float(self.config.timeout)
        resolver.timeout = float(self.config.timeout)
        return resolver

    def run(self, target: Target) -> ModuleResult:
        if not _DNS_AVAILABLE:
            return self._error("dnspython is not installed")

        resolver = self._get_resolver()
        domain = target.domain

        mx_hosts: list[dict[str, object]] = []
        try:
            answers = resolver.resolve(domain, "MX")
            for rdata in answers:
                mx_hosts.append(
                    {
                        "preference": int(rdata.preference),
                        "exchange": str(rdata.exchange).rstrip("."),
                    }
                )
        except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
            mx_hosts = []
        except dns.exception.DNSException as exc:
            return self._error(f"MX lookup failed: {exc}")

        mx_hosts.sort(key=lambda item: item["preference"])  # type: ignore[index]

        txt_records = _resolve_txt(domain, resolver)
        spf = next((r for r in txt_records if r.lower().startswith("v=spf1")), None)

        dmarc_records = _resolve_txt(f"_dmarc.{domain}", resolver)
        dmarc = next((r for r in dmarc_records if r.lower().startswith("v=dmarc1")), None)

        mta_sts_records = _resolve_txt(f"_mta-sts.{domain}", resolver)
        mta_sts = next((r for r in mta_sts_records if r.lower().startswith("v=stsv1")), None)

        findings: list[str] = []
        if mx_hosts:
            top = mx_hosts[0]["exchange"]
            findings.append(f"{len(mx_hosts)} MX record(s); primary exchange {top}.")
        else:
            findings.append("No MX records - domain cannot receive mail (or is misconfigured).")
        findings.append("SPF present." if spf else "No SPF record found.")
        findings.append("DMARC present." if dmarc else "No DMARC record found.")
        if mta_sts:
            findings.append("MTA-STS present.")

        status = Status.OK if mx_hosts else Status.NOT_FOUND
        return ModuleResult(
            name=self.name,
            title=self.title,
            status=status,
            data={
                "mx_records": mx_hosts,
                "has_mx": bool(mx_hosts),
                "spf": spf,
                "dmarc": dmarc,
                "mta_sts": mta_sts,
            },
            findings=findings,
        )
