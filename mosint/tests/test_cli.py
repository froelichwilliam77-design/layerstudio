import json
from pathlib import Path

from mosint.cli import main
from mosint.models import (
    BreachReport,
    EmailIdentity,
    MailConfig,
    ScanResult,
    SocialReport,
    WhoisRecord,
)
from mosint.report import dumps_json


def test_coffee_flag(capsys):
    assert main(["--coffee"]) == 0
    out = capsys.readouterr().out
    assert "enjoy your coffee" in out


def test_missing_email_prints_help():
    assert main([]) == 1


def test_invalid_email():
    assert main(["not-valid"]) == 2


def test_json_roundtrip_and_cli(tmp_path: Path, monkeypatch, capsys):
    fake = ScanResult(
        email=EmailIdentity(
            original="a@b.com",
            local="a",
            domain="b.com",
            canonical="a@b.com",
            syntax_valid=True,
            disposable=False,
        ),
        mail=MailConfig(domain="b.com"),
        whois=WhoisRecord(domain="b.com", registrar="Reg"),
        breaches=BreachReport(),
        social=SocialReport(),
    )

    monkeypatch.setattr("mosint.cli.scan_email", lambda *a, **k: fake)
    out_file = tmp_path / "report.json"
    assert main(["a@b.com", "--json", "-o", str(out_file), "--no-smtp"]) == 0
    printed = capsys.readouterr().out
    payload = json.loads(printed)
    assert payload["email"]["original"] == "a@b.com"
    saved = json.loads(out_file.read_text())
    assert saved["whois"]["registrar"] == "Reg"
    assert dumps_json(fake)
