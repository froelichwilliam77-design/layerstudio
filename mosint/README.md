# Mosint

All-in-one **automated email OSINT** framework written in Python.

Investigate an address from one command: mail-server configuration, public breach indexes, associated social profiles, and domain ownership. Built for security researchers looking at accounts they are authorized to assess.

```text
python -m mosint alice@example.com
```

## What it does

| Module | What it reveals |
| --- | --- |
| **Mail / MX** | MX hosts and IPs, inferred provider (Google, Microsoft 365, Proofpoint, …), SPF, DMARC, common DKIM selectors, optional SMTP banner |
| **HaveIBeenPwned** | Breach *names*, dates, and data classes (not passwords — HIBP does not return secrets) |
| **DeHashed** | Usernames / names / dump sources previously paired with the address. **Password values are never stored or printed** — only whether a record contained a password and the hash *type* if present |
| **Social** | Gravatar plus GitHub / GitLab / Reddit / Keybase / Hacker News handles derived from the local-part |
| **Ownership** | RDAP (WHOIS-equivalent) registrar, dates, nameservers, status; `whois` CLI fallback |
| **Enrichment** | ipapi.co geo/org for domain/MX IPs; optional Hunter.io related inboxes |

Paid APIs are optional. Without keys, Mosint still returns DNS, RDAP, social, and IP data.

## Install

```bash
cd mosint
python3 -m pip install -e ".[dev]"
```

Optional config (copy and fill only the keys you have):

```bash
cp example-config.yaml ~/.mosint.yaml
```

```yaml
services:
  haveibeenpwned_api_key: ""
  dehashed_api_key: ""
  hunter_api_key: ""
```

Keys can also be set with `MOSINT_HIBP_API_KEY`, `MOSINT_DEHASHED_API_KEY`, and `MOSINT_HUNTER_API_KEY`.

## Usage

```bash
mosint person@company.com
mosint person@company.com --no-smtp -o report.json
mosint person@company.com --json
mosint --coffee
```

## Tests

```bash
cd mosint
pytest
```

Network tests talk to public DNS/RDAP only (for example `gmail.com` MX and `example.com` RDAP). They do not call HIBP or DeHashed without keys.

## Responsible use

Use this on addresses you own or have permission to investigate. Do not use it to break into accounts, stalk people, or reuse leaked credentials. Mosint redacts DeHashed password fields on purpose.
