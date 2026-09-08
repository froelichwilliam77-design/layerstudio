from mosint.modules.validate import parse_email, username_candidates


def test_valid_gmail_canonicalizes_dots_and_plus():
    ident = parse_email("First.Last+news@Gmail.COM")
    assert ident.syntax_valid
    assert ident.domain == "gmail.com"
    assert ident.canonical == "firstlast@gmail.com"
    assert ident.local == "first.last+news"


def test_invalid_syntax():
    ident = parse_email("not-an-email")
    assert not ident.syntax_valid
    assert ident.reason


def test_disposable_flag():
    ident = parse_email("x@mailinator.com")
    assert ident.syntax_valid
    assert ident.disposable


def test_username_candidates_are_stable_and_limited():
    ident = parse_email("jane.doe+tag@example.com")
    cands = username_candidates(ident)
    assert "jane.doe" in cands
    assert "janedoe" in cands
    assert all("+" not in c for c in cands)
    assert len(cands) <= 4
