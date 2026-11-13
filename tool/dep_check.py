#!/usr/bin/env python3
"""dep_check.py - how far behind are the things this repo depends on?

Two kinds of "connected app" live in this repo, and they update differently:

  1. `admin_api_key_manager` is a `git:` pub dependency pinned to a commit.
     A `flutter pub upgrade` will NOT move it — a commit pin is a wall, not a
     range. It moves only when someone edits the ref and runs `pub get`.
  2. `flutter-builder` reusable workflows are pinned by tag in
     `.github/workflows/*.yml`. Same wall: nothing bumps a `@v1.15.2` by itself.

So "get the latest version" is never automatic here, which is exactly why this
script exists. It reads the pins out of the repo and asks GitHub for the truth.

    python3 tool/dep_check.py            # report; exit 1 if anything is behind
    python3 tool/dep_check.py --quiet    # no output unless something is behind

Token: $GITHUB_TOKEN, else ../agent-bootstrap/secrets/gh_token.txt.
Network down or unauthenticated is reported, never treated as "up to date" —
a checker that says "fine" when it could not look is worse than no checker.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN_PATHS = [
    Path(os.environ.get("GITHUB_TOKEN_FILE", "")),
    ROOT.parent / "agent-bootstrap" / "secrets" / "gh_token.txt",
]


def token() -> str:
    if os.environ.get("GITHUB_TOKEN"):
        return os.environ["GITHUB_TOKEN"].strip()
    for p in TOKEN_PATHS:
        if p and p.is_file():
            return p.read_text().strip()
    return ""


def api(path: str):
    req = urllib.request.Request("https://api.github.com" + path)
    tok = token()
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001 - any network failure is one outcome
        return None, type(e).__name__


def parse_pubspec_git_pins() -> list[tuple[str, str]]:
    """[(slug, sha)] for every `git:` dependency pinned to a ref."""
    text = (ROOT / "pubspec.yaml").read_text()
    lines = text.splitlines()
    pins = []
    for i, line in enumerate(lines):
        m = re.match(r"^  ([a-z0-9_]+):\s*$", line)
        if not m:
            continue
        block = []
        for nxt in lines[i + 1 : i + 8]:
            if re.match(r"^  \S", nxt):
                break
            block.append(nxt)
        body = "\n".join(block)
        if "git:" not in body:
            continue
        url = re.search(r"url:\s*(\S+)", body)
        ref = re.search(r"ref:\s*(\S+)", body)
        if not url or not ref:
            continue
        slug = "/".join(url.group(1).rstrip("/").split("/")[-2:])
        pins.append((slug, ref.group(1)))
    return pins


def workflow_tags() -> dict[str, list[str]]:
    """{slug: [tags]} for every `uses: owner/repo/...@tag` in workflows."""
    found: dict[str, list[str]] = {}
    for f in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
        for m in re.finditer(
            r"uses:\s*([\w-]+)/([\w-]+)/[^\s@]+@(v[\d.]+)", f.read_text()
        ):
            slug = f"{m.group(1)}/{m.group(2)}"
            found.setdefault(slug, [])
            if m.group(3) not in found[slug]:
                found[slug].append(m.group(3))
    return found


def tag_key(tag: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", tag))


def main() -> int:
    quiet = "--quiet" in sys.argv
    problems: list[str] = []
    notes: list[str] = []

    for slug, sha in parse_pubspec_git_pins():
        repo, err = api(f"/repos/{slug}")
        if err:
            problems.append(f"{slug}: could not check ({err})")
            continue
        branch = repo.get("default_branch", "main")
        head, err = api(f"/repos/{slug}/branches/{branch}")
        if err:
            problems.append(f"{slug}: could not read {branch} ({err})")
            continue
        head_sha = head["commit"]["sha"]
        tags, _ = api(f"/repos/{slug}/tags?per_page=100")
        tag_of = next(
            (t["name"] for t in (tags or []) if t["commit"]["sha"] == sha), None
        )
        if head_sha == sha:
            notes.append(f"{slug}: pin {sha[:7]} IS {branch} head"
                         + (f" (tag {tag_of})" if tag_of else " — no tag cut"))
        else:
            log, _ = api(f"/repos/{slug}/compare/{sha}...{head_sha}")
            ahead = log.get("ahead_by", "?") if log else "?"
            names = [
                c["commit"]["message"].splitlines()[0]
                for c in (log or {}).get("commits", [])[:5]
            ]
            current = tag_of or sha[:7]
            problems.append(
                f"{slug}: pinned at {current}, {branch} is {head_sha[:7]} "
                f"({ahead} commit(s) ahead)\n"
                + "".join(f"      - {n}\n" for n in names)
                + f"      bump: pubspec.yaml ref {sha[:12]}… -> {head_sha}"
            )
            if tags:
                latest = max((t["name"] for t in tags), key=tag_key)
                notes.append(f"{slug}: newest tag is {latest}")

    for slug, used in workflow_tags().items():
        tags, err = api(f"/repos/{slug}/tags?per_page=100")
        if err:
            problems.append(f"{slug}: could not check tags ({err})")
            continue
        names = [t["name"] for t in tags or []]
        if not names:
            notes.append(f"{slug}: no tags published; pins cannot be bumped")
            continue
        latest = max(names, key=tag_key)
        for u in used:
            if tag_key(u) < tag_key(latest):
                problems.append(
                    f"{slug}: workflows pin {u}, latest is {latest}\n"
                    f"      bump: .github/workflows/*.yml @{u} -> @{latest}"
                )
            else:
                notes.append(f"{slug}: workflows at {u} (latest)")

    if problems or not quiet:
        for n in notes:
            print(f"ok   {n}")
        for p in problems:
            print(f"BEHIND {p}")
        print(
            f"\ndep_check: {len(problems)} behind, {len(notes)} up to date"
            if problems
            else f"\ndep_check: everything pinned here is current"
        )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
