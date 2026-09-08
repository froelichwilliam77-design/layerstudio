from mosint.modules.whois_rdap import _parse_whois_text


def test_whois_text_parser():
    text = """
Domain Name: EXAMPLE.COM
Registrar: RESERVED-Internet Assigned Numbers Authority
Creation Date: 1995-08-14T04:00:00Z
Registry Expiry Date: 2026-08-13T04:00:00Z
Name Server: A.IANA-SERVERS.NET
Name Server: B.IANA-SERVERS.NET
Domain Status: clientDeleteProhibited
DNSSEC: unsigned
"""
    record = _parse_whois_text("example.com", text)
    assert record.registrar and "Assigned Numbers" in record.registrar
    assert "a.iana-servers.net" in record.nameservers
    assert record.dnssec == "unsigned"
    assert record.created.startswith("1995")
