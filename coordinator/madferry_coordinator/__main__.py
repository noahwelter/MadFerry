"""CLI: python -m madferry_coordinator run --data ../data --out ../out"""

import argparse
import datetime as dt
import html
import json
import os
import sys
import traceback
from pathlib import Path

from zoneinfo import ZoneInfo

from . import ALERTS_PAGE_ID, SCHEDULE_PAGE_ID, SCHEMA_VERSION, TIME_ZONE, WINDSLED_PAGE_ID
from . import build, extract, fetch, live, validate


def now_local() -> dt.datetime:
    return dt.datetime.now(ZoneInfo(TIME_ZONE))


def _set_output(name: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as fh:
            fh.write(f"{name}={value}\n")


def _strip_volatile(schedule):
    return {k: v for k, v in (schedule or {}).items() if k != "updatedAt"}


def run(data: Path, out: Path, use_llm: bool) -> int:
    now = now_local()
    today = now.date()
    store = data / "extractions"
    records = build.load_records(store)
    problems, new_seasons, report = [], [], []

    # 1. Ferry schedule images
    page = fetch.get_page(SCHEDULE_PAGE_ID)
    page_title = html.unescape(page["title"]["rendered"])
    images = fetch.schedule_images(page["content"]["rendered"])
    if not images:
        problems.append("No schedule images found on the schedule page (layout changed?)")
    on_site = {}
    for img in images:
        blob = fetch.fetch_image(img["url"])
        h = fetch.sha256(blob)
        on_site[h] = img
        if h in records:
            continue
        if not use_llm:
            problems.append(f"New image needs extraction: {img['url']}")
            continue
        try:
            season = build.normalize_season(extract.extract_ferry_image(blob, img["title"], page_title, today))
        except Exception as exc:  # noqa: BLE001 - surface any extraction failure in the report
            problems.append(f"Extraction failed for {img['url']}: {exc}")
            continue
        errs = validate.validate_season(season) + validate.plausibility_errors(season, today)
        if season["kind"] != "ferry":
            errs.append("expected a ferry season")
        record = {"sourceHash": h, "sourceUrl": img["url"], "sourceTitle": img["title"],
                  "firstSeen": today.isoformat(), "season": season}
        if errs:
            problems += [f"{img['url']}: {e}" for e in errs]
            build.write_json(out / "failed" / f"{h}.json", record)
            continue
        build.save_record(store, record)
        records[h] = record
        new_seasons.append(record)

    # 2. Windsled schedule (text page)
    windsled_hash = None
    try:
        wpage = fetch.get_page(WINDSLED_PAGE_ID)
        wtext = fetch.html_to_text(wpage["content"]["rendered"])
        windsled_hash = fetch.sha256(wtext.encode())
        if windsled_hash not in records and use_llm:
            season = build.normalize_season(extract.extract_windsled_text(wtext))
            errs = validate.validate_season(season)
            record = {"sourceHash": windsled_hash, "sourceUrl": wpage["link"], "sourceTitle": "Windsled",
                      "firstSeen": today.isoformat(), "season": season}
            if errs or season["kind"] != "windsled":
                problems += [f"windsled: {e}" for e in errs or ["expected kind windsled"]]
                build.write_json(out / "failed" / f"{windsled_hash}.json", record)
            else:
                build.save_record(store, record)
                records[windsled_hash] = record
                new_seasons.append(record)
    except Exception as exc:  # noqa: BLE001
        problems.append(f"Windsled page failed: {exc}")

    # 3. Assemble + validate schedule
    schedule = build.build_schedule(records, on_site, windsled_hash, page.get("modified"), today)
    problems += validate.validate_schedule(schedule)
    warnings = validate.gap_warnings(schedule)
    for start, end in build.uncovered_ranges(schedule, today, 60):
        warnings.append(f"No ferry schedule published for {start} → {end}")

    schedule_path = data / "v1" / "schedule.json"
    current = build.read_json(schedule_path)
    changed = not problems and _strip_volatile(current) != _strip_volatile(schedule)
    if changed:
        schedule["updatedAt"] = now.isoformat(timespec="seconds")
        build.write_json(schedule_path, schedule)
    published = schedule if (changed or current is None) else current

    # 4. Live: advisories + status (low risk, published without review)
    try:
        apage = fetch.get_page(ALERTS_PAGE_ID)
        items = live.advisories(fetch.paragraphs(apage["content"]["rendered"]))
        override = build.read_json(data / "overrides.json")
        live_doc = {
            "schemaVersion": SCHEMA_VERSION,
            "generatedAt": now.isoformat(timespec="seconds"),
            "status": live.status(published, items, override, today),
            "advisories": items,
            "alertsUrl": live.ALERTS_URL,
            "textAlerts": live.TEXT_ALERTS,
            "windsledHotline": live.WINDSLED_HOTLINE,
        }
        build.write_json(data / "v1" / "live.json", live_doc)
    except Exception as exc:  # noqa: BLE001
        problems.append(f"Advisories failed: {exc}")

    # 5. Report
    report.append("# Ferry schedule update\n")
    if problems:
        report.append("## ❌ Problems (schedule NOT published)\n")
        report += [f"- {p}" for p in problems]
        report.append("")
    if warnings:
        report.append("## ⚠️ Warnings\n")
        report += [f"- {w}" for w in warnings]
        report.append("")
    if new_seasons:
        report.append("## New extractions — compare against the source images\n")
        for rec in new_seasons:
            report.append(f"![source]({rec['sourceUrl']})\n" if rec["season"]["kind"] == "ferry" else "")
            report.append(build.render_season(dict(rec["season"], source={"url": rec["sourceUrl"]})))
    report.append("## Published seasons\n")
    for s in schedule["seasons"]:
        report.append(build.render_season(s))
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.md").write_text("\n".join(report))

    _set_output("schedule_changed", "true" if changed else "false")
    _set_output("problems", "true" if problems else "false")
    print("\n".join(report))
    return 3 if problems else 0


def render(data: Path) -> int:
    schedule = build.read_json(data / "v1" / "schedule.json")
    for s in schedule["seasons"]:
        print(build.render_season(s))
    return 0


def check(data: Path) -> int:
    schedule = build.read_json(data / "v1" / "schedule.json")
    errors = validate.validate_schedule(schedule)
    for rec in build.load_records(data / "extractions").values():
        errors += [f"extraction {rec['sourceHash'][:12]}: {e}" for e in validate.validate_season(rec["season"])]
    print("\n".join(errors) or "schedule OK")
    return 1 if errors else 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="madferry_coordinator")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run", help="scrape, extract, validate and write data/v1/*.json")
    p_run.add_argument("--data", type=Path, default=Path("data"))
    p_run.add_argument("--out", type=Path, default=Path("out"))
    p_run.add_argument("--no-llm", action="store_true", help="never call the LLM; report new images instead")
    p_render = sub.add_parser("render", help="print the published schedule as markdown")
    p_render.add_argument("--data", type=Path, default=Path("data"))
    p_check = sub.add_parser("check", help="validate the published schedule and extraction records")
    p_check.add_argument("--data", type=Path, default=Path("data"))
    args = parser.parse_args(argv)
    try:
        if args.cmd == "run":
            return run(args.data, args.out, not args.no_llm)
        if args.cmd == "check":
            return check(args.data)
        return render(args.data)
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
