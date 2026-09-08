# Mosint

**An all-in-one automated email OSINT framework, written in Python.**

Point Mosint at a single email address and it runs a set of reconnaissance
modules in one pass: it validates the address, inspects the domain's mail-server
configuration, checks public breach corpora, discovers linked social profiles,
and pulls domain-ownership records — then prints a consolidated report as text
or JSON.

> [!WARNING]
> **Authorised use only.** Mosint is built for legitimate security work:
> checking your **own** accounts and exposure, investigations you are
> **permitted** to run, and **sanctioned** penetration tests / threat-intel.
> You are responsible for complying with the terms of service of every data
> provider you query (HIBP, DeHashed, RDAP registries, Gravatar) and with all
> applicable laws. Do not use it to target people without authorisation.
>
> Mosint bundles **no** breach data and exploits nothing. Every provider that
> can return sensitive data requires **your own** API credentials, and breached
> passwords/hashes are **redacted by default** in output.

## What it reveals

| Module | What it does | Data source | Credentials |
|--------|--------------|-------------|-------------|
| `validation` | Validates syntax; flags disposable domains and role accounts | local | none |
| `mailserver` | MX records + SPF / DMARC / MTA-STS posture | DNS | none |
| `breaches` | Breaches and leaked records tied to the address | Have I Been Pwned, DeHashed | API key(s) |
| `social` | Public Gravatar profile and linked social accounts | Gravatar | none |
| `domain` | Registrar, registrant org, registration dates, nameservers | RDAP (WHOIS successor) | none |

The `breaches` module is skipped automatically when no provider credentials are
configured, so the rest of the scan still runs.

## Install

Requires Python 3.11+.

```bash
cd mosint
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
# or, without installing the package:
pip install -r requirements.txt
```

## Configure (optional)

Only needed for the `breaches` module. Copy the example and fill in the keys you
are authorised to use:

```bash
cp config.example.toml config.toml
```

```toml
[api_keys]
hibp = "your-hibp-key"          # https://haveibeenpwned.com/API/Key
dehashed_email = "you@corp.com"
dehashed_key = "your-dehashed-key"

[http]
timeout = 15
```

Environment variables override the file (handy for CI / secrets managers):

```bash
export MOSINT_HIBP_API_KEY=...
export MOSINT_DEHASHED_EMAIL=...
export MOSINT_DEHASHED_API_KEY=...
```

`config.toml` is git-ignored — keep real keys out of version control.

## Usage

```bash
# Full scan (text report; secrets redacted)
mosint target@example.com

# Or without installing the console script:
python -m mosint target@example.com

# Run specific modules only
mosint target@example.com -m validation,mailserver,domain

# JSON output (for piping into jq / storage)
mosint target@example.com -o json > result.mosint.json

# Reveal breached passwords/hashes (use responsibly)
mosint target@example.com --show-secrets

# List modules
mosint --list-modules
```

### Exit codes

- `0` — scan completed (findings may or may not be present)
- `1` — at least one module errored
- `2` — bad input (invalid email or unknown module)

## Output

Text output groups findings per module with a status tag (`OK`, `none`, `skip`,
`ERR`). JSON output mirrors the same structure:

```json
{
  "email": "target@example.com",
  "duration_seconds": 1.42,
  "results": [
    {"name": "validation", "title": "Email validation", "status": "ok", "data": {"...": "..."}, "findings": ["..."]},
    {"name": "breaches",   "title": "Data breaches",    "status": "ok", "data": {"dehashed": {"entries": [{"password": "[REDACTED]"}]}}}
  ]
}
```

## Architecture

```
mosint/
  mosint/
    cli.py            # argparse entry point
    config.py         # TOML + env config resolution
    orchestrator.py   # Scanner: runs modules -> Report
    reporting.py      # text / JSON rendering + secret redaction
    http.py           # shared requests session
    modules/
      base.py         # Module base class + ModuleResult / Status / Target
      validation.py   # email parsing + classification
      mailserver.py   # MX / SPF / DMARC / MTA-STS
      breaches.py     # HIBP + DeHashed
      social.py       # Gravatar profile + linked accounts
      domain.py       # RDAP domain ownership
  tests/              # pytest suite (network fully mocked)
```

Each module is self-contained, declares whether it `is_available()` (e.g. has
credentials), and returns a structured `ModuleResult` instead of raising — so one
failing provider never aborts the whole scan. Adding a module is a matter of
subclassing `Module` and registering it in `modules/__init__.py`.

## Testing

The suite mocks all network and DNS access, so it runs offline and hits no live
provider:

```bash
pip install -e ".[dev]"
pytest -q
```

## License

MIT (see the repository `LICENSE`).
