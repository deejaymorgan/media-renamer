#!/usr/bin/env python3
"""Build docs/quickstart.html from the template.

Inlines each `{{IMG:NAME}}` token as a base64 data URI of
docs/quickstart-assets/NAME.png, and fills in `{{DATE}}`.

The PDF (docs/quickstart.pdf) is produced separately by printing the page
to PDF from a browser — it is intentionally light-only (see the print CSS).

Usage: python3 scripts/build-quickstart.py
"""
from __future__ import annotations

import base64
import datetime
import pathlib
import re
import sys

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
TEMPLATE = DOCS / "quickstart.template.html"
ASSETS = DOCS / "quickstart-assets"
OUTPUT = DOCS / "quickstart.html"


def data_uri(name: str) -> str:
    png = ASSETS / f"{name}.png"
    if not png.exists():
        sys.exit(f"missing asset: {png}")
    b64 = base64.b64encode(png.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{b64}"


def main() -> None:
    html = TEMPLATE.read_text(encoding="utf-8")
    html = re.sub(r"\{\{IMG:([^}]+)\}\}", lambda m: data_uri(m.group(1)), html)
    # e.g. "22 June 2026" (strip the leading zero from the day for readability)
    today = datetime.date.today().strftime("%d %B %Y").lstrip("0")
    html = html.replace("{{DATE}}", today)
    if "{{" in html:
        sys.exit("unresolved template token remaining in output")
    OUTPUT.write_text(html, encoding="utf-8")
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
