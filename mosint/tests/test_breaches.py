from mosint.modules.breaches import infer_hash_type, sanitize_dehashed_record


def test_sanitize_strips_password_material():
    entry = sanitize_dehashed_record(
        {
            "email": "a@b.com",
            "username": "alice",
            "name": "Alice",
            "password": "super-secret-value",
            "hashed_password": "5f4dcc3b5aa765d61d8327deb882cf99",
            "obtained_from": "ExampleLeak",
        }
    )
    raw = str(entry)
    assert "super-secret-value" not in raw
    assert "5f4dcc3b5aa765d61d8327deb882cf99" not in raw
    assert entry.username == "alice"
    assert entry.password_present is True
    assert entry.password_hash_type == "md5"
    assert entry.obtained_from == "ExampleLeak"


def test_hash_type_detection():
    assert infer_hash_type("$2b$12$abcdefgh") == "bcrypt"
    assert infer_hash_type("a" * 40) == "sha1"
    assert infer_hash_type("") is None
