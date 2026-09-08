from mosint.config import Config
from mosint.modules.mailserver import MailServerModule
from mosint.modules.validation import parse_email

from .helpers import FakeMX, FakeResolver, FakeTXT


def _run(mapping):
    resolver = FakeResolver(mapping)
    module = MailServerModule(Config(), resolver=resolver)
    return module.run(parse_email("user@example.com"))


def test_mailserver_full_config():
    mapping = {
        ("example.com", "MX"): [FakeMX(10, "mx1.example.com."), FakeMX(5, "mx0.example.com.")],
        ("example.com", "TXT"): [FakeTXT("v=spf1 include:_spf.example.com ~all")],
        ("_dmarc.example.com", "TXT"): [FakeTXT("v=DMARC1; p=reject")],
        ("_mta-sts.example.com", "TXT"): [FakeTXT("v=STSv1; id=2024")],
    }
    result = _run(mapping)
    assert result.status.value == "ok"
    assert result.data["has_mx"] is True
    # Sorted by preference: mx0 (5) first.
    assert result.data["mx_records"][0]["exchange"] == "mx0.example.com"
    assert result.data["spf"].startswith("v=spf1")
    assert result.data["dmarc"].startswith("v=DMARC1")
    assert result.data["mta_sts"].startswith("v=STSv1")


def test_mailserver_no_mx_returns_not_found():
    result = _run({("example.com", "TXT"): [FakeTXT("v=spf1 ~all")]})
    assert result.status.value == "not_found"
    assert result.data["has_mx"] is False
    assert result.data["dmarc"] is None
