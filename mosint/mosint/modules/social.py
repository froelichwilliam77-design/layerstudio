from __future__ import annotations

import hashlib
from urllib.parse import quote

import httpx

from mosint.models import EmailIdentity, SocialProfile, SocialReport
from mosint.modules.validate import username_candidates

GITHUB_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


def gravatar_hash(email: str) -> str:
    return hashlib.md5(email.strip().lower().encode("utf-8")).hexdigest()


def _ok(status: int) -> bool:
    return status == 200


def check_gravatar(email: str, client: httpx.Client) -> SocialProfile:
    digest = gravatar_hash(email)
    url = f"https://www.gravatar.com/{digest}.json"
    try:
        response = client.get(url)
        if response.status_code == 404:
            return SocialProfile(platform="Gravatar", url=url, found=False, detail="No public Gravatar profile")
        if _ok(response.status_code):
            display = None
            try:
                payload = response.json()
                entry = (payload.get("entry") or [{}])[0]
                display = entry.get("displayName") or entry.get("preferredUsername")
            except ValueError:
                display = None
            return SocialProfile(
                platform="Gravatar",
                url=f"https://www.gravatar.com/{digest}",
                found=True,
                detail=display,
            )
        return SocialProfile(platform="Gravatar", url=url, found=False, detail=f"HTTP {response.status_code}")
    except httpx.HTTPError as exc:
        return SocialProfile(platform="Gravatar", url=url, found=False, detail=str(exc))


def check_github_username(username: str, client: httpx.Client) -> SocialProfile:
    url = f"https://api.github.com/users/{quote(username)}"
    html = f"https://github.com/{username}"
    try:
        response = client.get(url, headers=GITHUB_HEADERS)
        if response.status_code == 404:
            return SocialProfile(platform="GitHub", url=html, found=False)
        if _ok(response.status_code):
            payload = response.json()
            detail = payload.get("name") or payload.get("login")
            return SocialProfile(platform="GitHub", url=html, found=True, detail=detail)
        return SocialProfile(platform="GitHub", url=html, found=False, detail=f"HTTP {response.status_code}")
    except httpx.HTTPError as exc:
        return SocialProfile(platform="GitHub", url=html, found=False, detail=str(exc))


def check_gitlab_username(username: str, client: httpx.Client) -> SocialProfile:
    html = f"https://gitlab.com/{username}"
    url = f"https://gitlab.com/api/v4/users?username={quote(username)}"
    try:
        response = client.get(url)
        if response.status_code != 200:
            return SocialProfile(platform="GitLab", url=html, found=False, detail=f"HTTP {response.status_code}")
        items = response.json()
        if isinstance(items, list) and items:
            web = items[0].get("web_url") or html
            return SocialProfile(platform="GitLab", url=web, found=True, detail=items[0].get("username") or username)
        return SocialProfile(platform="GitLab", url=html, found=False)
    except (httpx.HTTPError, ValueError) as exc:
        return SocialProfile(platform="GitLab", url=html, found=False, detail=str(exc))


def check_keybase_username(username: str, client: httpx.Client) -> SocialProfile:
    html = f"https://keybase.io/{username}"
    url = f"https://keybase.io/_/api/1.0/user/lookup.json?username={quote(username)}"
    try:
        response = client.get(url)
        if response.status_code != 200:
            return SocialProfile(platform="Keybase", url=html, found=False, detail=f"HTTP {response.status_code}")
        payload = response.json()
        code = (payload.get("status") or {}).get("code")
        if code == 0 and payload.get("them"):
            return SocialProfile(platform="Keybase", url=html, found=True, detail=username)
        return SocialProfile(platform="Keybase", url=html, found=False)
    except (httpx.HTTPError, ValueError) as exc:
        return SocialProfile(platform="Keybase", url=html, found=False, detail=str(exc))


def check_reddit_username(username: str, client: httpx.Client) -> SocialProfile:
    html = f"https://www.reddit.com/user/{username}"
    url = f"{html}/about.json"
    try:
        response = client.get(url)
        body = response.text[:2000].replace(" ", "")
        found = response.status_code == 200 and '"kind":"t2"' in body
        return SocialProfile(
            platform="Reddit",
            url=html,
            found=found,
            detail=username if found else f"HTTP {response.status_code}",
        )
    except httpx.HTTPError as exc:
        return SocialProfile(platform="Reddit", url=html, found=False, detail=str(exc))


def check_hackernews_username(username: str, client: httpx.Client) -> SocialProfile:
    html = f"https://news.ycombinator.com/user?id={username}"
    url = f"https://hacker-news.firebaseio.com/v0/user/{quote(username)}.json"
    try:
        response = client.get(url)
        body = response.text.strip()
        found = response.status_code == 200 and body not in {"", "null"}
        return SocialProfile(
            platform="Hacker News",
            url=html,
            found=found,
            detail=username if found else None,
        )
    except httpx.HTTPError as exc:
        return SocialProfile(platform="Hacker News", url=html, found=False, detail=str(exc))


def check_username_platforms(username: str, client: httpx.Client) -> list[SocialProfile]:
    return [
        check_gitlab_username(username, client),
        check_reddit_username(username, client),
        check_keybase_username(username, client),
        check_hackernews_username(username, client),
    ]


def scrape_social(identity: EmailIdentity, client: httpx.Client) -> SocialReport:
    candidates = username_candidates(identity)
    report = SocialReport(username_candidates=candidates, gravatar_hash=gravatar_hash(identity.original))
    report.profiles.append(check_gravatar(identity.original, client))

    seen_keys: set[tuple[str, str]] = {(p.platform, p.url) for p in report.profiles}
    # Only probe the first (most specific) handle to stay polite with rate limits.
    if candidates:
        user = candidates[0]
        gh = check_github_username(user, client)
        key = (gh.platform, gh.url)
        if key not in seen_keys:
            report.profiles.append(gh)
            seen_keys.add(key)
        for profile in check_username_platforms(user, client):
            key = (profile.platform, profile.url)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            report.profiles.append(profile)
    return report
