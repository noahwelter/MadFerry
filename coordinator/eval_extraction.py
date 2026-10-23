"""Compare live LLM extraction against the hand-transcribed fixtures.

Usage (from coordinator/):  LLM_API_KEY=<gemini key> python3 eval_extraction.py
"""

import datetime as dt
import json
import sys
from pathlib import Path

from madferry_coordinator import build, extract, validate

FIX = Path(__file__).parent / "tests" / "fixtures"


def key(d):
    return (d["from"], d["time"], tuple(d["days"]), d["restricted"])


def diff(name, got, want):
    problems = validate.validate_season(got)
    for field in ("kind", "startDate", "endDate"):
        if got.get(field) != want.get(field):
            problems.append(f"{field}: got {got.get(field)!r}, want {want.get(field)!r}")
    g, w = {key(d) for d in got["departures"]}, {key(d) for d in want["departures"]}
    problems += [f"missing {k}" for k in sorted(w - g)] + [f"extra {k}" for k in sorted(g - w)]
    print(f"{'✅' if not problems else '❌'} {name}")
    for p in problems:
        print("   ", p)
    return not problems


def main():
    ok = True
    page = json.loads((FIX / "page-2909.json").read_text())
    for img in sorted(FIX.glob("*.jpg")):
        want = build.normalize_season(json.loads((FIX / "expected" / f"{img.stem}.json").read_text()))
        got = build.normalize_season(
            extract.extract_ferry_image(img.read_bytes(), img.stem, page["title"]["rendered"], dt.date(2026, 10, 23))
        )
        ok &= diff(img.stem, got, want)
    wpage = json.loads((FIX / "page-4987.json").read_text())
    from madferry_coordinator.fetch import html_to_text

    got = build.normalize_season(extract.extract_windsled_text(html_to_text(wpage["content"]["rendered"])))
    want = build.normalize_season(json.loads((FIX / "expected" / "windsled.json").read_text()))
    ok &= diff("windsled", got, want)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
