from mosint.config import Config
from mosint.modules.social import SocialModule, gravatar_hash
from mosint.modules.validation import parse_email

from .helpers import FakeResponse, FakeSession

TARGET = parse_email("beau.gravatar@gmail.com")


def test_gravatar_hash_is_md5_of_normalized_email():
    # Known Gravatar example hash for "MyEmailAddress@example.com ".
    assert (
        gravatar_hash("MyEmailAddress@example.com ")
        == "0bc83cb571cd1c50ba6f3e8a78ef1346"
    )


def test_social_profile_found_with_accounts():
    payload = {
        "entry": [
            {
                "profileUrl": "https://gravatar.com/beau",
                "displayName": "Beau",
                "name": {"formatted": "Beau Gravatar"},
                "accounts": [
                    {"shortname": "github", "url": "https://github.com/beau", "username": "beau"}
                ],
            }
        ]
    }
    session = FakeSession(responses=[FakeResponse(200, payload)])
    result = SocialModule(Config(), session).run(TARGET)
    assert result.status.value == "ok"
    assert result.data["display_name"] == "Beau Gravatar"
    assert result.data["accounts"][0]["provider"] == "github"


def test_social_profile_absent():
    session = FakeSession(responses=[FakeResponse(404)])
    result = SocialModule(Config(), session).run(TARGET)
    assert result.status.value == "not_found"
    assert result.data["has_gravatar"] is False
