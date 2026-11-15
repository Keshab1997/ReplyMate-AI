#!/usr/bin/env python3
"""Render app screens to PNGs, locally, in seconds.

    python3 tool/screenshots.py --list
    python3 tool/screenshots.py --shot settings-reply
    python3 tool/screenshots.py --shot settings-hub,about
    python3 tool/screenshots.py                  # every shot
    python3 tool/screenshots.py --shot about --open

Why this exists next to tool/see_screen.py: that one asks CI to build the web
app and photograph *routes*, which costs a run and cannot reach a screen you
have to tap into (every Settings sub-screen, About). This one renders the widget
in the test harness with the real theme and the real fonts, so it is a couple of
seconds, works offline, and can photograph a pushed screen.

What it is not: a test. It writes throwaway evidence to .agent-screens/local/
(git-ignored), it never compares anything, and `flutter test` never discovers it
- the file lives in tool/, and the runner is a no-op without --dart-define=SHOTS=1.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNNER = "tool/screenshots/shot_runner_test.dart"
REGISTRY = ROOT / "tool" / "screenshots" / "shot_registry.dart"
OUT_DIR = ROOT / ".agent-screens" / "local"

# The sandboxes this project is worked in wipe the SDK between turns, so the
# install location is a fact to look up, not to assume.
FLUTTER_CANDIDATES = ("/var/tmp/flutter/bin/flutter", "~/flutter/bin/flutter")


def find_flutter() -> str:
    on_path = shutil.which("flutter")
    if on_path:
        return on_path
    for candidate in FLUTTER_CANDIDATES:
        path = Path(os.path.expanduser(candidate))
        if path.exists():
            return str(path)
    sys.exit(
        "flutter not found. Install it first, e.g.\n"
        "  bash <(curl -fsSL https://raw.githubusercontent.com/"
        "Keshab1997/flutter-bootstrap/main/setup.sh) --root /var/tmp/flutter --quiet"
    )


def known_shots() -> list[str]:
    """Read the registry rather than keeping a second list that can drift."""
    source = REGISTRY.read_text()
    return re.findall(r"name:\s*'([^']+)'", source)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--shot",
        default="",
        help="comma-separated shot names (default: all of them)",
    )
    parser.add_argument("--list", action="store_true", help="print the shots and exit")
    parser.add_argument(
        "--open",
        action="store_true",
        help="open each PNG with the desktop viewer after rendering",
    )
    args = parser.parse_args()

    shots = known_shots()
    if args.list:
        print("shots:")
        for name in shots:
            print(f"  {name}")
        return

    if args.shot:
        wanted = [s.strip() for s in args.shot.split(",") if s.strip()]
        unknown = [s for s in wanted if s not in shots]
        if unknown:
            sys.exit(
                f"unknown shot(s): {', '.join(unknown)}\n"
                f"known: {', '.join(shots)}"
            )

    flutter = find_flutter()
    env = dict(os.environ)
    env.setdefault("PUB_CACHE", "/var/tmp/pub-cache")

    command = [
        flutter,
        "test",
        RUNNER,
        "--update-goldens",
        "--dart-define=SHOTS=1",
        f"--dart-define=SHOT={args.shot}",
    ]
    result = subprocess.run(command, cwd=ROOT, env=env)
    if result.returncode != 0:
        sys.exit(result.returncode)

    written = sorted(OUT_DIR.glob("*.png"))
    if args.shot:
        wanted = {s.strip() for s in args.shot.split(",") if s.strip()}
        written = [p for p in written if p.stem in wanted]

    if not written:
        sys.exit(f"no PNGs in {OUT_DIR.relative_to(ROOT)} - did the run fail?")

    print("\nrendered:")
    for path in written:
        size_kb = path.stat().st_size / 1024
        print(f"  {path.relative_to(ROOT)}  ({size_kb:.0f} KB)")

    if args.open:
        for path in written:
            subprocess.run(["open" if sys.platform == "darwin" else "xdg-open", path])


if __name__ == "__main__":
    main()
