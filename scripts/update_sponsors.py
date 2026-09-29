#!/usr/bin/env python3
"""Rewrite README.md's Supporter list from the website's sponsor wall.

The website lists every Supporter who turned the listing on in their account and
still holds a purchase that was not refunded, earliest first, and counts the ones
who stay private (https://www.wallpapermachine.app/#sponsors). It serves the same
list, names and months only, at /api/sponsors. This reads it and rewrites the block
between the `supporters:start` and `supporters:end` markers under README.md's
"Thank you. To every Supporter." heading, so a Supporter who turns the listing on,
off or renames it is followed here too. Nothing outside the markers changes.

    python3 scripts/update_sponsors.py                       # read the live wall, rewrite the list
    python3 scripts/update_sponsors.py --check               # exit 1 when the list is out of date
    python3 scripts/update_sponsors.py --input sponsors.json # a saved answer instead of the wall

The Supporters workflow (.github/workflows/supporters.yml) runs it every hour and
commits README.md when the list changed. A failed or malformed answer leaves
README.md as it was.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import NamedTuple
import urllib.error
import urllib.request

from lib.glyphs import markers
from lib.paths import ROOT

MARK = markers()
README = ROOT / "README.md"
SOURCE = "https://www.wallpapermachine.app/api/sponsors"
USER_AGENT = "WallpaperMachine/1.0 (README Supporter list; scripts/update_sponsors.py)"
TIMEOUT_SECONDS = 30

START = "<!-- supporters:start: written by scripts/update_sponsors.py from the website's sponsor wall; edits here are overwritten -->"
END = "<!-- supporters:end -->"
BLOCK = re.compile(r"<!-- supporters:start\b.*?-->.*?<!-- supporters:end -->", re.DOTALL)

# Characters HTML or Markdown give a meaning. Names are the Supporters' own words, so
# none of them may become a tag, a link, an image or one of the markers above.
SIGNIFICANT = re.compile(r"[&<>\"'`*_\[\]()\\~|#!]")
# Control and format characters, which the website already drops from names.
INVISIBLE = re.compile(r"[\x00-\x1f\x7f-\x9f​‎‏‪-‮⁦-⁩﻿]")


class Wall(NamedTuple):
    """The sponsor wall: listed names, earliest first, and the private count."""

    names: tuple[str, ...]
    hidden: int


def parse_wall(payload: object) -> Wall:
    """The wall from /api/sponsors' JSON; ValueError when it is not that shape."""
    if not isinstance(payload, dict):
        raise ValueError("the answer is not a JSON object")
    supporters = payload.get("supporters")
    hidden = payload.get("hidden")
    if not isinstance(supporters, list):
        raise ValueError("`supporters` is not a list")
    if not isinstance(hidden, int) or isinstance(hidden, bool) or hidden < 0:
        raise ValueError("`hidden` is not a count")
    names = []
    for supporter in supporters:
        name = supporter.get("name") if isinstance(supporter, dict) else None
        if not isinstance(name, str):
            raise ValueError("a Supporter has no name")
        name = " ".join(INVISIBLE.sub("", name).split())
        if name:
            names.append(name)
    return Wall(tuple(names), hidden)


def fetch_wall(source: str) -> Wall:
    """The wall as the website serves it now."""
    request = urllib.request.Request(
        source, headers={"Accept": "application/json", "User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        body = response.read()
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as error:
        raise ValueError(f"the answer is not JSON ({error.msg})") from error
    return parse_wall(payload)


def escape(name: str) -> str:
    """A name as literal text inside README.md's HTML."""
    return SIGNIFICANT.sub(lambda match: f"&#{ord(match.group())};", name)


def plural(count: int, one: str, many: str) -> str:
    return f"{count:,} {one if count == 1 else many}"


def count_line(wall: Wall) -> str:
    """The sentence under the names, worded as the website words its count."""
    shown = len(wall.names)
    if shown:
        line = f"{plural(shown, 'Supporter', 'Supporters')} on the list."
        if wall.hidden:
            line += f" {plural(wall.hidden, 'more supports', 'more support')} privately."
        return line
    if wall.hidden:
        return f"No one is on the list yet. {plural(wall.hidden, 'Supporter', 'Supporters')} so far, all private."
    return "No one is on the list yet."


def render(wall: Wall) -> str:
    """The block between the markers, markers included."""
    lines = [START]
    if wall.names:
        # One HTML block: GitHub renders its text as written, never as Markdown.
        lines += [
            '<p align="center">',
            "  " + "&ensp;·&ensp;".join(escape(name) for name in wall.names),
            "</p>",
            "",
            f'<p align="center"><sub>{count_line(wall)}</sub></p>',
        ]
    else:
        lines.append(count_line(wall))
    lines.append(END)
    return "\n".join(lines)


def rewrite(text: str, wall: Wall) -> str:
    """README.md's text with its Supporter list replaced; ValueError without the markers."""
    matches = BLOCK.findall(text)
    if len(matches) != 1:
        raise ValueError(f"expected one supporters:start … supporters:end block, found {len(matches)}")
    return BLOCK.sub(lambda _: render(wall), text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", default=SOURCE, help=f"the sponsor wall's JSON (default {SOURCE})")
    parser.add_argument("--input", type=Path, help="read the wall from this JSON file instead of --source")
    parser.add_argument("--check", action="store_true", help="change nothing; exit 1 when README.md is out of date")
    args = parser.parse_args()

    try:
        if args.input:
            wall = parse_wall(json.loads(args.input.read_text(encoding="utf-8")))
        else:
            wall = fetch_wall(args.source)
        before = README.read_text(encoding="utf-8")
        after = rewrite(before, wall)
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f"{MARK.missing} Could not update the Supporter list: {error}", file=sys.stderr)
        return 1

    summary = f"{plural(len(wall.names), 'Supporter', 'Supporters')} listed, {wall.hidden:,} private"
    if after == before:
        print(f"{MARK.ok} README.md is up to date: {summary}.")
        return 0
    if args.check:
        print(f"{MARK.warn} README.md is out of date: the wall has {summary}.")
        return 1
    README.write_text(after, encoding="utf-8")
    print(f"{MARK.step} README.md updated: {summary}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
