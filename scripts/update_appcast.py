#!/usr/bin/env python3
"""Insert a new release <item> into docs/appcast.xml.

Reads release metadata from the environment and the version's bullet list from
CHANGELOG.md, then prepends a Sparkle <item> (including a <description> with the
release notes, which Sparkle renders in the update dialog).

Environment:
    VERSION        e.g. "1.7.1"
    BUILD_NUMBER   Sparkle <version> (monotonic build number)
    DMG_SIZE       enclosure length in bytes
    DOWNLOAD_URL   enclosure url
    PUB_DATE       RFC-822 date string
    ED_SIG         Sparkle EdDSA signature

Usage: python3 scripts/update_appcast.py
"""

import html
import os
import sys

APPCAST = "docs/appcast.xml"
CHANGELOG = "CHANGELOG.md"


def changelog_bullets(version: str) -> list[str]:
    """Return the bullet lines under the `## <version>` heading, or []."""
    try:
        with open(CHANGELOG, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return []

    bullets: list[str] = []
    collecting = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            if collecting:
                break  # reached the next version section
            heading = stripped[3:].strip()
            # Match "1.7.1", "v1.7.1", or "[1.7.1] - 2026-07-07"
            collecting = version in heading
            continue
        if collecting and (stripped.startswith("- ") or stripped.startswith("* ")):
            bullets.append(stripped[2:].strip())
    return bullets


def description_block(version: str) -> str:
    bullets = changelog_bullets(version)
    if not bullets:
        return ""
    items = "".join(f"<li>{html.escape(b)}</li>" for b in bullets)
    notes = f"<h2>Version {html.escape(version)}</h2><ul>{items}</ul>"
    return f"\n      <description><![CDATA[{notes}]]></description>"


def main() -> int:
    try:
        version = os.environ["VERSION"]
        build = os.environ["BUILD_NUMBER"]
        size = os.environ["DMG_SIZE"]
        url = os.environ["DOWNLOAD_URL"]
        date = os.environ["PUB_DATE"]
        sig = os.environ["ED_SIG"]
    except KeyError as exc:
        print(f"Missing required env var: {exc}", file=sys.stderr)
        return 1

    item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>{description_block(version)}
      <enclosure
        url="{url}"
        length="{size}"
        type="application/octet-stream"
        sparkle:edSignature="{sig}"
      />
    </item>"""

    with open(APPCAST, encoding="utf-8") as f:
        content = f.read()

    content = content.replace("</language>", "</language>\n" + item)

    with open(APPCAST, "w", encoding="utf-8") as f:
        f.write(content)

    print(item)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
