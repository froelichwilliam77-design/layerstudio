from __future__ import annotations

import json
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from mosint.models import ScanResult

BANNER = r"""
 ███╗   ███╗ ██████╗ ███████╗██╗███╗   ██╗████████╗
 ████╗ ████║██╔═══██╗██╔════╝██║████╗  ██║╚══██╔══╝
 ██╔████╔██║██║   ██║███████╗██║██╔██╗ ██║   ██║
 ██║╚██╔╝██║██║   ██║╚════██║██║██║╚██╗██║   ██║
 ██║ ╚═╝ ██║╚██████╔╝███████║██║██║ ╚████║   ██║
 ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝
"""

COFFEE = r"""
        ( (
         ) )
      ........
      |      |]
      \      /
       `----'

  enjoy your coffee
"""


def render_report(result: ScanResult, console: Console) -> None:
    identity = result.email
    header = Text.assemble(
        ("Target  ", "bold dim"),
        (identity.original, "bold yellow"),
        ("\nDomain  ", "bold dim"),
        (identity.domain, "cyan"),
    )
    if identity.canonical != identity.original:
        header.append("\nCanon   ", style="bold dim")
        header.append(identity.canonical, style="green")
    if identity.disposable:
        header.append("\nFlag    ", style="bold dim")
        header.append("disposable / throwaway domain", style="red")
    console.print(Panel(header, title="email", border_style="magenta"))

    mail = result.mail
    mx_table = Table(title="MX / mail configuration", show_header=True, header_style="bold")
    mx_table.add_column("Pref", justify="right")
    mx_table.add_column("Host")
    mx_table.add_column("Addresses")
    if mail.mx:
        for row in mail.mx:
            mx_table.add_row(str(row.preference), row.host, ", ".join(row.addresses) or "—")
    else:
        mx_table.add_row("—", "no MX records", "—")
    console.print(mx_table)

    cfg = Table(show_header=True, header_style="bold", title="Mail policy")
    cfg.add_column("Record")
    cfg.add_column("Value")
    cfg.add_row("Provider", mail.provider or "unknown")
    cfg.add_row("SPF", "; ".join(mail.spf) or "missing")
    cfg.add_row("DMARC", "; ".join(mail.dmarc) or "missing")
    if mail.dkim:
        cfg.add_row("DKIM", ", ".join(f"{item['selector']}" for item in mail.dkim))
    else:
        cfg.add_row("DKIM", "no common selectors")
    if mail.smtp_banner:
        cfg.add_row("SMTP banner", mail.smtp_banner)
    elif mail.smtp_banner_error:
        cfg.add_row("SMTP banner", f"unavailable ({mail.smtp_banner_error})")
    for note in mail.notes:
        cfg.add_row("Note", note)
    if mail.error:
        cfg.add_row("Error", mail.error)
    console.print(cfg)

    whois = result.whois
    own = Table(title="Domain ownership", show_header=True, header_style="bold")
    own.add_column("Field")
    own.add_column("Value")
    own.add_row("Source", whois.source or "—")
    own.add_row("Registrar", whois.registrar or "—")
    own.add_row("Registrant", whois.registrant or "—")
    own.add_row("Organization", whois.organization or "—")
    own.add_row("Created", whois.created or "—")
    own.add_row("Expires", whois.expires or "—")
    own.add_row("Nameservers", ", ".join(whois.nameservers) or "—")
    own.add_row("Status", ", ".join(whois.status) or "—")
    own.add_row("DNSSEC", whois.dnssec or "—")
    if whois.error:
        own.add_row("Error", whois.error)
    console.print(own)

    if result.ip:
        ip_table = Table(title="IP / hosting", show_header=True, header_style="bold")
        ip_table.add_column("IP")
        ip_table.add_column("Org")
        ip_table.add_column("Location")
        for info in result.ip:
            loc = ", ".join(p for p in (info.city, info.region, info.country) if p) or "—"
            ip_table.add_row(info.ip, info.org or info.error or "—", loc)
        console.print(ip_table)

    breaches = result.breaches
    br = Table(title="HaveIBeenPwned", show_header=True, header_style="bold")
    br.add_column("Breach")
    br.add_column("Date")
    br.add_column("Data classes")
    if breaches.hibp_skipped:
        br.add_row(breaches.hibp_skipped, "", "")
    elif not breaches.hibp_breaches:
        br.add_row("No breaches returned for this address", "", "")
    else:
        for hit in breaches.hibp_breaches:
            br.add_row(hit.title or hit.name, hit.breach_date or "—", ", ".join(hit.data_classes) or "—")
    console.print(br)

    if breaches.hibp_pastes:
        pastes = Table(title="HIBP pastes", show_header=True, header_style="bold")
        pastes.add_column("Source")
        pastes.add_column("Title")
        pastes.add_column("Date")
        for paste in breaches.hibp_pastes:
            pastes.add_row(paste.source, paste.title or "—", paste.date or "—")
        console.print(pastes)

    dh = Table(title="DeHashed (usernames only)", show_header=True, header_style="bold")
    dh.add_column("Username")
    dh.add_column("Name")
    dh.add_column("Source")
    dh.add_column("Password in record")
    if breaches.dehashed_skipped:
        dh.add_row(breaches.dehashed_skipped, "", "", "")
    elif not breaches.dehashed_entries:
        dh.add_row("No DeHashed entries", "", "", "")
    else:
        for entry in breaches.dehashed_entries:
            present = "yes" if entry.password_present else "no"
            if entry.password_hash_type:
                present = f"yes ({entry.password_hash_type} hash)"
            dh.add_row(entry.username or "—", entry.name or "—", entry.obtained_from or "—", present)
    console.print(dh)

    social = Table(title="Social / public profiles", show_header=True, header_style="bold")
    social.add_column("Platform")
    social.add_column("Found")
    social.add_column("URL / detail")
    hits = [p for p in result.social.profiles if p.found]
    misses = [p for p in result.social.profiles if not p.found]
    rows = hits + misses
    if not rows:
        social.add_row("—", "—", "no probes")
    for profile in rows:
        mark = "[green]yes[/green]" if profile.found else "[dim]no[/dim]"
        detail = profile.url if profile.found else (profile.detail or profile.url)
        if profile.found and profile.detail:
            detail = f"{profile.url}  ({profile.detail})"
        social.add_row(profile.platform, mark, detail)
    console.print(social)
    if result.social.username_candidates:
        console.print(
            "[dim]Social handles are guessed from the local-part "
            f"({', '.join(result.social.username_candidates)}); not proof of inbox ownership.[/dim]"
        )

    if result.related_emails:
        rel = Table(title="Related addresses (Hunter.io)", show_header=True, header_style="bold")
        rel.add_column("Email")
        rel.add_column("Name")
        rel.add_column("Role")
        for item in result.related_emails:
            name = " ".join(p for p in (item.first_name, item.last_name) if p) or "—"
            rel.add_row(item.value, name, item.position or item.department or "—")
        console.print(rel)
    elif result.related_skipped:
        console.print(f"[dim]{result.related_skipped}[/dim]")

    for note in breaches.notes:
        console.print(f"[dim]{note}[/dim]")


def write_json(result: ScanResult, path: str) -> None:
    target = Path(path)
    target.write_text(json.dumps(result.to_dict(), indent=2) + "\n", encoding="utf-8")


def dumps_json(result: ScanResult) -> str:
    return json.dumps(result.to_dict(), indent=2)
