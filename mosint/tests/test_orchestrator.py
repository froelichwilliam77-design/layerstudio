import pytest

from mosint.config import Config
from mosint.modules import ALL_MODULES
from mosint.orchestrator import Scanner, select_modules

from .helpers import FakeSession


def test_select_modules_all():
    assert select_modules(None) == list(ALL_MODULES)


def test_select_modules_subset_preserves_order():
    chosen = select_modules(["domain", "validation"])
    names = [cls.name for cls in chosen]
    # Canonical order has validation before domain.
    assert names == ["validation", "domain"]


def test_select_modules_unknown_raises():
    with pytest.raises(KeyError):
        select_modules(["validation", "bogus"])


def test_scanner_runs_only_available_modules():
    # No credentials -> breaches is skipped; DNS/network modules use a fake
    # session and empty responses via matcher returning 404-like behavior.
    config = Config()
    scanner = Scanner(
        config,
        modules=select_modules(["validation", "breaches"]),
        session=FakeSession(),
    )
    report = scanner.scan("jane@example.com")
    statuses = {r.name: r.status.value for r in report.results}
    assert statuses["validation"] == "ok"
    assert statuses["breaches"] == "skipped"


def test_scanner_isolates_module_exceptions(monkeypatch):
    config = Config()
    scanner = Scanner(config, modules=select_modules(["validation"]), session=FakeSession())

    from mosint.modules.validation import EmailValidationModule

    def boom(self, target):
        raise RuntimeError("kaboom")

    monkeypatch.setattr(EmailValidationModule, "run", boom)
    report = scanner.scan("jane@example.com")
    assert report.results[0].status.value == "error"
    assert "kaboom" in report.results[0].error
