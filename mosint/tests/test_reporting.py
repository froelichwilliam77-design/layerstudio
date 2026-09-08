from mosint.modules.base import ModuleResult, Status
from mosint.orchestrator import Report
from mosint.reporting import REDACTED, render_json, render_text
import json


def _report_with_breach():
    breach = ModuleResult(
        name="breaches",
        title="Data breaches",
        status=Status.OK,
        data={
            "dehashed": {
                "entries": [
                    {"username": "v", "password": "hunter2", "hashed_password": "abc", "database_name": "Acme"}
                ]
            },
            "hibp": {"breaches": [{"name": "Acme", "breach_date": "2019", "data_classes": ["Passwords"]}]},
        },
        findings=["HIBP: 1 breach(es).", "DeHashed: 1 record(s)."],
    )
    return Report(email="v@example.com", results=[breach], started_at=0.0, finished_at=1.0)


def test_text_redacts_secrets_by_default():
    text = render_text(_report_with_breach())
    assert "hunter2" not in text
    assert REDACTED in text
    assert "secrets redacted" in text


def test_text_shows_secrets_when_requested():
    text = render_text(_report_with_breach(), show_secrets=True)
    assert "hunter2" in text
    assert "password=hunter2" in text


def test_json_redacts_secrets_by_default():
    data = json.loads(render_json(_report_with_breach()))
    entry = data["results"][0]["data"]["dehashed"]["entries"][0]
    assert entry["password"] == REDACTED
    assert entry["hashed_password"] == REDACTED


def test_json_shows_secrets_when_requested():
    data = json.loads(render_json(_report_with_breach(), show_secrets=True))
    entry = data["results"][0]["data"]["dehashed"]["entries"][0]
    assert entry["password"] == "hunter2"
