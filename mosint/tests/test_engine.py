import json

import httpx

from mosint.config import MosintConfig
from mosint.engine import scan_email
from mosint.modules.breaches import collect_breaches, query_hibp
from mosint.modules.social import check_gravatar, scrape_social
from mosint.modules.validate import parse_email
from mosint.modules.whois_rdap import lookup_rdap


def test_hibp_parses_breach_payload():
    def handler(request: httpx.Request) -> httpx.Response:
        if "breachedaccount" in str(request.url):
            return httpx.Response(
                200,
                json=[
                    {
                        "Name": "Adobe",
                        "Title": "Adobe",
                        "Domain": "adobe.com",
                        "BreachDate": "2013-10-04",
                        "DataClasses": ["Email addresses", "Passwords"],
                        "PwnCount": 152_445_165,
                    }
                ],
            )
        if "pasteaccount" in str(request.url):
            return httpx.Response(404)
        raise AssertionError(request.url)

    transport = httpx.MockTransport(handler)
    client = httpx.Client(transport=transport)
    breaches, pastes, skip = query_hibp("a@b.com", "test-key", client)
    assert skip is None
    assert breaches[0].name == "Adobe"
    assert "Passwords" in breaches[0].data_classes
    assert pastes == []


def test_dehashed_never_keeps_password(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "POST"
        body = json.loads(request.content)
        assert "email:" in body["query"]
        return httpx.Response(
            200,
            json={
                "entries": [
                    {
                        "email": "a@b.com",
                        "username": "alice",
                        "password": "SHOULD-NOT-LEAK",
                        "obtained_from": "LeakDB",
                    }
                ]
            },
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    report = collect_breaches(
        "a@b.com",
        hibp_key="",
        dehashed_key="key",
        client=client,
    )
    assert report.dehashed_usernames == ["alice"]
    dumped = json.dumps(report.dehashed_entries[0].__dict__)
    assert "SHOULD-NOT-LEAK" not in dumped
    assert report.dehashed_entries[0].password_present is True


def test_gravatar_404():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    profile = check_gravatar("nobody@example.com", client)
    assert profile.platform == "Gravatar"
    assert profile.found is False


def test_social_github_user_hit():
    identity = parse_email("octocat@example.com")

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "gravatar.com" in url:
            return httpx.Response(404)
        if "api.github.com/users/octocat" in url:
            return httpx.Response(200, json={"login": "octocat", "name": "The Octocat"})
        if "gitlab.com/api/v4/users" in url:
            return httpx.Response(200, json=[])
        if "keybase.io" in url:
            return httpx.Response(200, json={"status": {"code": 205}, "them": []})
        if "hacker-news.firebaseio.com" in url:
            return httpx.Response(200, json=None)
        if "reddit.com" in url:
            return httpx.Response(404, text="{}")
        return httpx.Response(404, text="not found")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    report = scrape_social(identity, client)
    github = [p for p in report.profiles if p.platform == "GitHub" and p.found]
    assert github
    assert github[0].detail == "The Octocat"


def test_rdap_example_com_live():
    client = httpx.Client(timeout=12.0, follow_redirects=True)
    record = lookup_rdap("example.com", client)
    assert record is not None
    assert not record.error or record.registrar or record.nameservers
    # example.com is IANA reserved; RDAP should still name a registrar or nameservers
    assert record.registrar or record.nameservers


def test_scan_skips_paid_apis_without_keys(monkeypatch):
    def fake_mail(domain, timeout=12.0, probe_smtp=True):
        from mosint.models import MailConfig, MxHost

        return MailConfig(
            domain=domain,
            mx=[MxHost(preference=10, host="mx.example.com", addresses=["1.2.3.4"])],
            provider="Example",
        )

    def fake_whois(domain, client, timeout=12.0):
        from mosint.models import WhoisRecord

        return WhoisRecord(domain=domain, registrar="Example Registrar", source="test")

    def fake_social(identity, client):
        from mosint.models import SocialReport

        return SocialReport(username_candidates=["alice"])

    def fake_ip(ip, client):
        from mosint.models import IpInfo

        return IpInfo(ip=ip, org="Example Net", country="US")

    monkeypatch.setattr("mosint.engine.inspect_mail", fake_mail)
    monkeypatch.setattr("mosint.engine.lookup_ownership", fake_whois)
    monkeypatch.setattr("mosint.engine.scrape_social", fake_social)
    monkeypatch.setattr("mosint.engine.lookup_ip", fake_ip)

    client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(404)))
    result = scan_email(
        "alice@example.com",
        MosintConfig(),
        probe_smtp=False,
        client=client,
    )
    assert result.email.syntax_valid
    assert result.breaches.hibp_skipped
    assert result.breaches.dehashed_skipped
    assert result.mail.provider == "Example"
    assert result.whois.registrar == "Example Registrar"
