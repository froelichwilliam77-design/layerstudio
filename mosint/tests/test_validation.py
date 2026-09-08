import pytest

from mosint.modules.validation import (
    EmailValidationModule,
    InvalidEmailError,
    parse_email,
)
from mosint.config import Config


@pytest.mark.parametrize(
    "email,local,domain",
    [
        ("Alice@Example.COM", "Alice", "example.com"),
        ("bob.smith+tag@sub.domain.org", "bob.smith+tag", "sub.domain.org"),
        ("  spaced@example.io  ", "spaced", "example.io"),
    ],
)
def test_parse_email_valid(email, local, domain):
    target = parse_email(email)
    assert target.local_part == local
    assert target.domain == domain
    assert target.email == f"{local}@{domain}"


@pytest.mark.parametrize(
    "email",
    ["", "not-an-email", "no@domain", "@example.com", "a@b", "spaces in@example.com"],
)
def test_parse_email_invalid(email):
    with pytest.raises(InvalidEmailError):
        parse_email(email)


def test_validation_flags_disposable_and_role():
    target = parse_email("admin@mailinator.com")
    result = EmailValidationModule(Config()).run(target)
    assert result.status.value == "ok"
    assert result.data["is_disposable"] is True
    assert result.data["is_role_account"] is True


def test_validation_normal_account():
    target = parse_email("jane.doe@gmail.com")
    result = EmailValidationModule(Config()).run(target)
    assert result.data["is_disposable"] is False
    assert result.data["is_role_account"] is False
