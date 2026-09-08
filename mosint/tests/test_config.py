import os

from mosint.config import load_config, DEFAULT_TIMEOUT


def test_env_overrides_take_precedence(tmp_path, monkeypatch):
    cfg_file = tmp_path / "config.toml"
    cfg_file.write_text(
        """
[api_keys]
hibp = "from-file"
[http]
timeout = 5
""".strip()
    )
    monkeypatch.setenv("MOSINT_HIBP_API_KEY", "from-env")
    config = load_config(cfg_file)
    assert config.hibp_api_key == "from-env"
    assert config.timeout == 5


def test_missing_file_falls_back_to_defaults(tmp_path, monkeypatch):
    for var in [
        "MOSINT_HIBP_API_KEY",
        "MOSINT_DEHASHED_EMAIL",
        "MOSINT_DEHASHED_API_KEY",
        "MOSINT_TIMEOUT",
        "MOSINT_USER_AGENT",
    ]:
        monkeypatch.delenv(var, raising=False)
    config = load_config(tmp_path / "does-not-exist.toml")
    assert config.hibp_api_key is None
    assert config.timeout == DEFAULT_TIMEOUT
    assert config.has_hibp is False
    assert config.has_dehashed is False


def test_dehashed_requires_both_parts(monkeypatch):
    monkeypatch.setenv("MOSINT_DEHASHED_EMAIL", "me@corp.com")
    monkeypatch.delenv("MOSINT_DEHASHED_API_KEY", raising=False)
    config = load_config(None)
    assert config.has_dehashed is False
