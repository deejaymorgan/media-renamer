#!/usr/bin/env python3
"""Build (or verify) docs/quickstart.html from the template.

Inlines each `{{IMG:NAME}}` token as a base64 data URI of
docs/quickstart-assets/NAME.png, and fills in `{{DATE}}`.

Usage:
  python3 scripts/build-quickstart.py            # regenerate docs/quickstart.html
  python3 scripts/build-quickstart.py --check    # exit 1 if it is stale (date ignored)

No PDF is committed — the hosted HTML guide is canonical. If you need one, print
the rendered page to PDF from a browser (the print CSS is intentionally light-only).
"""
from __future__ import annotations

import argparse
import base64
import datetime
import pathlib
import re
import sys

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
TEMPLATE = DOCS / "quickstart.template.html"
ASSETS = DOCS / "quickstart-assets"
OUTPUT = DOCS / "quickstart.html"

# The footer carries a build date; --check normalizes it out so the day the
# file was last built never counts as drift.
DATE_SPAN = re.compile(r'(Generated <span class="mono">)[^<]*(</span>)')


def data_uri(name: str) -> str:
    png = ASSETS / f"{name}.png"
    if not png.exists():
        sys.exit(f"missing asset: {png}")
    b64 = base64.b64encode(png.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{b64}"


def today_str() -> str:
    # e.g. "22 June 2026" (no leading zero on the day, for readability)
    return datetime.date.today().strftime("%d %B %Y").lstrip("0")


def render(date_str: str) -> str:
    html = TEMPLATE.read_text(encoding="utf-8")
    html = re.sub(r"\{\{IMG:([^}]+)\}\}", lambda m: data_uri(m.group(1)), html)
    html = html.replace("{{DATE}}", date_str)
    if "{{" in html:
        sys.exit("unresolved template token remaining in output")
    return html


def undate(html: str) -> str:
    """Blank the build-date stamp so comparisons ignore which day it was built."""
    return DATE_SPAN.sub(r"\1__DATE__\2", html)


def main() -> None:
    ap = argparse.ArgumentParser(description="Build or verify docs/quickstart.html")
    ap.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if quickstart.html is stale vs the template/assets "
        "(the build date is ignored)",
    )
    args = ap.parse_args()

    expected = render(today_str())

    if args.check:
        if not OUTPUT.exists():
            sys.exit(f"{OUTPUT.name} does not exist — run: python3 scripts/build-quickstart.py")
        current = OUTPUT.read_text(encoding="utf-8")
        if undate(current) != undate(expected):
            sys.exit(
                f"{OUTPUT.name} is out of date relative to {TEMPLATE.name}.\n"
                f"Rebuild it with:  python3 scripts/build-quickstart.py"
            )
        print(f"{OUTPUT.name} is up to date with {TEMPLATE.name}")
        return

    OUTPUT.write_text(expected, encoding="utf-8")
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
