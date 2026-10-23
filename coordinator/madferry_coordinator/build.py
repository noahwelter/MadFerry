"""Assemble published JSON from per-source extraction records.

The ferry site only shows the current/upcoming season images, so every extraction is kept in
data/extractions/<sha256>.json. The published schedule is the union of all records: seasons whose
image is currently on the site take precedence; archived seasons are trimmed around them and
pruned once they are more than a year old.
"""

import datetime as dt
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from . import CROSSING_MINUTES, SCHEMA_VERSION, TERMINALS, TIME_ZONE

DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
RETENTION_DAYS = 370


# ---------- extraction record store ----------

def load_records(directory: Path) -> Dict[str, Dict]:
    records = {}
    if directory.exists():
        for path in sorted(directory.glob("*.json")):
            rec = json.loads(path.read_text())
            records[rec["sourceHash"]] = rec
    return records


def save_record(directory: Path, record: Dict) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{record['sourceHash']}.json").write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")


def normalize_season(season: Dict) -> Dict:
    deps = sorted(
        (
            {
                "from": d["from"],
                "time": d["time"],
                "days": sorted(set(d["days"])),
                "note": d.get("note") or None,
                "restricted": bool(d.get("restricted", False)),
            }
            for d in season.get("departures", [])
        ),
        key=lambda d: (d["from"], d["time"], d["days"]),
    )
    return {
        "kind": season.get("kind"),
        "label": season.get("label"),
        "startDate": season.get("startDate"),
        "endDate": season.get("endDate"),
        "endNote": season.get("endNote") or None,
        "notes": [n for n in season.get("notes", []) if n],
        "departures": deps,
    }


# ---------- merging ----------

def _d(s: str) -> dt.date:
    return dt.date.fromisoformat(s)


def _trim(season: Dict, start: dt.date, end: Optional[dt.date], blockers: List[Tuple[dt.date, dt.date]]):
    """Trim [start, end] so it does not overlap any blocker. Keeps the earliest surviving piece."""
    far = dt.date.max
    for b_start, b_end in sorted(blockers):
        cur_end = end or far
        if b_end < start or b_start > cur_end:
            continue
        if b_start > start:
            end = b_start - dt.timedelta(days=1)
        elif b_end == far or b_end >= cur_end:
            return None
        else:
            start = b_end + dt.timedelta(days=1)
    if end is not None and end < start:
        return None
    out = dict(season)
    out["startDate"], out["endDate"] = start.isoformat(), end.isoformat() if end else None
    if end is not None and season.get("endDate") is None:
        out["endNote"] = None
    return out


def _span(season: Dict, following: Optional[Dict]) -> Tuple[dt.date, dt.date]:
    start = _d(season["startDate"])
    if season.get("endDate"):
        return start, _d(season["endDate"])
    if following:
        return start, _d(following["startDate"]) - dt.timedelta(days=1)
    return start, dt.date.max


def merge_seasons(records: Dict[str, Dict], on_site: Dict[str, Dict], today: dt.date) -> List[Dict]:
    ferry = [r for r in records.values() if r["season"]["kind"] == "ferry"]
    current = sorted((r for r in ferry if r["sourceHash"] in on_site), key=lambda r: r["season"]["startDate"])
    archived = sorted(
        (r for r in ferry if r["sourceHash"] not in on_site), key=lambda r: r["firstSeen"], reverse=True
    )

    accepted: List[Dict] = []
    for i, rec in enumerate(current):
        accepted.append(_with_source(rec["season"], rec, on_site))
    blockers = [_span(s, accepted[i + 1] if i + 1 < len(accepted) else None) for i, s in enumerate(accepted)]

    for rec in archived:  # newest archived first
        season = rec["season"]
        start = _d(season["startDate"])
        end = _d(season["endDate"]) if season.get("endDate") else None
        if end is None:
            later = [b for b in blockers if b[0] > start]
            if later:
                end = min(later)[0] - dt.timedelta(days=1)
        trimmed = _trim(season, start, end, blockers)
        if trimmed is None:
            continue
        accepted.append(_with_source(trimmed, rec, on_site))
        t_end = _d(trimmed["endDate"]) if trimmed["endDate"] else dt.date.max
        blockers.append((_d(trimmed["startDate"]), t_end))

    cutoff = today - dt.timedelta(days=RETENTION_DAYS)
    accepted.sort(key=lambda s: s["startDate"])
    kept = []
    for i, s in enumerate(accepted):
        nxt = accepted[i + 1] if i + 1 < len(accepted) else None
        if _span(s, nxt)[1] >= cutoff:
            kept.append(s)
    return kept


def _with_source(season: Dict, rec: Dict, on_site: Dict[str, Dict]) -> Dict:
    out = dict(season)
    out["id"] = f"{season['kind']}-{season['startDate']}"
    out["source"] = {
        "url": rec["sourceUrl"],
        "hash": rec["sourceHash"],
        "onSiteNow": rec["sourceHash"] in on_site,
    }
    return out


def build_schedule(records: Dict[str, Dict], on_site: Dict[str, Dict], windsled_hash: Optional[str],
                   page_modified: Optional[str], today: dt.date) -> Dict:
    seasons = merge_seasons(records, on_site, today)
    windsled = [r for r in records.values() if r["season"]["kind"] == "windsled"]
    chosen = None
    if windsled_hash and windsled_hash in records:
        chosen = records[windsled_hash]
    elif windsled:
        chosen = max(windsled, key=lambda r: r["firstSeen"])
    if chosen:
        s = dict(chosen["season"])
        s["id"] = "windsled"
        s["source"] = {"url": chosen["sourceUrl"], "hash": chosen["sourceHash"], "onSiteNow": chosen["sourceHash"] == windsled_hash}
        seasons.append(s)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "timeZone": TIME_ZONE,
        "crossingMinutes": CROSSING_MINUTES,
        "sourcePageModified": page_modified,
        "terminals": TERMINALS,
        "seasons": seasons,
    }


def uncovered_ranges(schedule: Dict, start: dt.date, days: int) -> List[Tuple[dt.date, dt.date]]:
    from .live import season_for

    gaps, gap_start = [], None
    for n in range(days + 1):
        day = start + dt.timedelta(days=n)
        covered = season_for(schedule, day) is not None
        if not covered and gap_start is None:
            gap_start = day
        if covered and gap_start is not None:
            gaps.append((gap_start, day - dt.timedelta(days=1)))
            gap_start = None
    if gap_start is not None:
        gaps.append((gap_start, start + dt.timedelta(days=days)))
    return gaps


# ---------- report ----------

def days_label(days: List[int]) -> str:
    if days == list(range(1, 8)):
        return "Daily"
    if days == list(range(days[0], days[-1] + 1)) and len(days) > 2:
        return f"{DAY_NAMES[days[0] - 1]}–{DAY_NAMES[days[-1] - 1]}"
    return ", ".join(DAY_NAMES[d - 1] for d in days)


def render_season(season: Dict) -> str:
    end = season.get("endDate") or season.get("endNote") or "open-ended"
    src = season.get("source", {})
    lines = [f"### {season['label']} ({season['kind']}: {season.get('startDate') or '—'} → {end})", ""]
    if src.get("url"):
        lines += [f"Source: {src['url']}" + ("" if src.get("onSiteNow", True) else " _(no longer on site)_"), ""]
    lines += ["| From Bayfield (to Island) | Days | From La Pointe (to Bayfield) | Days |", "|---|---|---|---|"]
    by = {t: [d for d in season["departures"] if d["from"] == t] for t in ("bayfield", "lapointe")}
    for i in range(max(len(by["bayfield"]), len(by["lapointe"]))):
        row = []
        for t in ("bayfield", "lapointe"):
            if i < len(by[t]):
                d = by[t][i]
                extra = f" — {d['note']}" if d.get("note") else ""
                row += [d["time"] + (" 🔒" if d.get("restricted") else ""), days_label(d["days"]) + extra]
            else:
                row += ["", ""]
        lines.append("| " + " | ".join(row) + " |")
    for n in season.get("notes", []):
        lines.append(f"\n> {n}")
    return "\n".join(lines) + "\n"


def write_json(path: Path, data: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def read_json(path: Path) -> Optional[Dict]:
    return json.loads(path.read_text()) if path.exists() else None
