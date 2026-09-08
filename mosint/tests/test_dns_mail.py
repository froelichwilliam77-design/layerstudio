from mosint.modules.dns_mail import _dkim_has_key, infer_provider, inspect_mail


def test_infer_google_and_microsoft_providers():
    assert infer_provider(["aspmx.l.google.com"]) == "Google Workspace / Gmail"
    assert infer_provider(["example-com.mail.protection.outlook.com"]) == "Microsoft 365"
    assert infer_provider(["mx.unknown.example"]) is None


def test_empty_dkim_key_is_rejected():
    assert _dkim_has_key("v=DKIM1; p=") is False
    assert _dkim_has_key("v=DKIM1; p=MIGfMA0GCSqGSIb3") is True
    assert _dkim_has_key("not dkim") is False


def test_example_null_mx_live():
    mail = inspect_mail("example.com", timeout=8.0, probe_smtp=False)
    assert mail.error is None
    assert all(row.host for row in mail.mx)
    assert any("Null MX" in note for note in mail.notes) or not mail.mx
    assert mail.dkim == []


def test_gmail_mx_live():
    mail = inspect_mail("gmail.com", timeout=8.0, probe_smtp=False)
    assert mail.error is None
    assert mail.mx, "gmail.com should publish MX records"
    assert mail.provider == "Google Workspace / Gmail"
    hosts = " ".join(row.host for row in mail.mx).lower()
    assert "google" in hosts
