import json

import pytest

from mosint.cli import main


def test_list_modules(capsys):
    rc = main(["--list-modules"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "validation" in out
    assert "breaches" in out


def test_invalid_email_returns_2(capsys):
    rc = main(["not-an-email"])
    err = capsys.readouterr().err
    assert rc == 2
    assert "not a valid email" in err


def test_unknown_module_returns_2(capsys):
    rc = main(["jane@example.com", "-m", "bogus"])
    err = capsys.readouterr().err
    assert rc == 2
    assert "unknown module" in err


def test_json_output_validation_only(capsys, monkeypatch):
    for var in ["MOSINT_HIBP_API_KEY", "MOSINT_DEHASHED_EMAIL", "MOSINT_DEHASHED_API_KEY"]:
        monkeypatch.delenv(var, raising=False)
    rc = main(["jane.doe@example.com", "-m", "validation", "-o", "json"])
    out = capsys.readouterr().out
    assert rc == 0
    data = json.loads(out)
    assert data["email"] == "jane.doe@example.com"
    assert data["results"][0]["name"] == "validation"
    assert data["results"][0]["status"] == "ok"
