from mosint.config import Config
from mosint.modules.breaches import BreachModule
from mosint.modules.validation import parse_email

from .helpers import FakeResponse, FakeSession


TARGET = parse_email("victim@example.com")


def test_breaches_skipped_without_credentials():
    result = BreachModule(Config()).run(TARGET)
    assert result.status.value == "skipped"


def test_hibp_found_and_dehashed_records():
    config = Config(
        hibp_api_key="k",
        dehashed_email="me@corp.com",
        dehashed_api_key="secret",
    )

    def matcher(url, **kwargs):
        if "haveibeenpwned" in url:
            return FakeResponse(
                200,
                [
                    {
                        "Name": "Acme",
                        "Domain": "acme.com",
                        "BreachDate": "2019-01-01",
                        "PwnCount": 1000,
                        "DataClasses": ["Emails", "Passwords"],
                    }
                ],
            )
        return FakeResponse(
            200,
            {
                "total": 1,
                "entries": [
                    {
                        "email": "victim@example.com",
                        "username": "victim",
                        "password": "hunter2",
                        "database_name": "Acme",
                    }
                ],
            },
        )

    session = FakeSession(matcher=matcher)
    result = BreachModule(config, session).run(TARGET)
    assert result.status.value == "ok"
    assert result.data["hibp"]["breaches"][0]["name"] == "Acme"
    assert result.data["dehashed"]["entries"][0]["password"] == "hunter2"


def test_hibp_404_is_not_found():
    config = Config(hibp_api_key="k")
    session = FakeSession(responses=[FakeResponse(404)])
    result = BreachModule(config, session).run(TARGET)
    assert result.status.value == "not_found"
    assert result.data["hibp"]["breaches"] == []


def test_hibp_unauthorized_is_error():
    config = Config(hibp_api_key="bad")
    session = FakeSession(responses=[FakeResponse(401)])
    result = BreachModule(config, session).run(TARGET)
    assert result.status.value == "error"
    assert "unauthorized" in result.data["hibp"]["error"]
