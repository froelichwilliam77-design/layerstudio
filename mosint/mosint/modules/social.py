"""Social-profile discovery from an email address.

Gravatar is the most reliable email->profile pivot available without scraping:
a public Gravatar profile can expose a display name and a list of linked social
accounts. We hash the address (Gravatar's documented lookup key) and read the
public JSON profile, if any.
"""

from __future__ import annotations

import hashlib

import requests

from .base import Module, ModuleResult, Status, Target

GRAVATAR_PROFILE = "https://www.gravatar.com/{hash}.json"
GRAVATAR_AVATAR = "https://www.gravatar.com/avatar/{hash}?d=404"


def gravatar_hash(email: str) -> str:
    """Return the Gravatar lookup hash (MD5 of the normalized address)."""

    normalized = email.strip().lower().encode("utf-8")
    return hashlib.md5(normalized).hexdigest()


class SocialModule(Module):
    """Look up a public Gravatar profile and any linked social accounts."""

    name = "social"
    title = "Social profiles"

    def run(self, target: Target) -> ModuleResult:
        session = self.session or requests.Session()
        digest = gravatar_hash(target.email)

        try:
            resp = session.get(
                GRAVATAR_PROFILE.format(hash=digest),
                timeout=self.config.timeout,
                headers={"User-Agent": self.config.user_agent},
            )
        except requests.RequestException as exc:
            return self._error(f"Gravatar lookup failed: {exc}")

        avatar_url = GRAVATAR_AVATAR.format(hash=digest)

        if resp.status_code == 404:
            return ModuleResult(
                name=self.name,
                title=self.title,
                status=Status.NOT_FOUND,
                data={"gravatar_hash": digest, "has_gravatar": False},
                findings=["No public Gravatar profile."],
            )
        if resp.status_code != 200:
            return self._error(f"Gravatar returned status {resp.status_code}")

        try:
            payload = resp.json()
        except ValueError:
            return self._error("invalid JSON from Gravatar")

        entries = payload.get("entry") or []
        profile = entries[0] if entries else {}

        accounts = [
            {
                "provider": acct.get("shortname") or acct.get("name"),
                "url": acct.get("url"),
                "username": acct.get("username"),
            }
            for acct in (profile.get("accounts") or [])
        ]
        display_name = None
        if isinstance(profile.get("name"), dict):
            display_name = profile["name"].get("formatted")
        display_name = display_name or profile.get("displayName")

        findings = [f"Public Gravatar profile found ({len(accounts)} linked account(s))."]
        if display_name:
            findings.append(f"Display name: {display_name}.")

        return ModuleResult(
            name=self.name,
            title=self.title,
            status=Status.OK,
            data={
                "gravatar_hash": digest,
                "has_gravatar": True,
                "profile_url": profile.get("profileUrl"),
                "avatar_url": avatar_url,
                "display_name": display_name,
                "location": profile.get("currentLocation"),
                "accounts": accounts,
            },
            findings=findings,
        )
