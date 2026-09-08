from mosint.config import Config
from mosint.modules.domain import DomainModule
from mosint.modules.validation import parse_email

from .helpers import FakeResponse, FakeSession

TARGET = parse_email("user@example.com")


def test_domain_rdap_parsed():
    payload = {
        "events": [
            {"eventAction": "registration", "eventDate": "1995-08-14T04:00:00Z"},
            {"eventAction": "expiration", "eventDate": "2026-08-13T04:00:00Z"},
        ],
        "status": ["client transfer prohibited"],
        "nameservers": [{"ldhName": "a.iana-servers.net"}],
        "entities": [
            {
                "roles": ["registrar"],
                "vcardArray": ["vcard", [["fn", {}, "text", "RESERVED-IANA"]]],
            },
            {
                "roles": ["registrant"],
                "vcardArray": ["vcard", [["org", {}, "text", "Example Org"]]],
            },
        ],
    }
    session = FakeSession(responses=[FakeResponse(200, payload)])
    result = DomainModule(Config(), session).run(TARGET)
    assert result.status.value == "ok"
    assert result.data["registrar"] == "RESERVED-IANA"
    assert result.data["registrant_org"] == "Example Org"
    assert result.data["events"]["registration"].startswith("1995")
    assert result.data["nameservers"] == ["a.iana-servers.net"]


def test_domain_not_found():
    session = FakeSession(responses=[FakeResponse(404)])
    result = DomainModule(Config(), session).run(TARGET)
    assert result.status.value == "not_found"
