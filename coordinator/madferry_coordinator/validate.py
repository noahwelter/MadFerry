"""Schema + sanity validation for extracted seasons and the assembled schedule."""

import datetime as dt
import re
from typing import Dict, List

KINDS = {"ferry", "windsled"}
TERMINAL_IDS = {"bayfield", "lapointe"}
TIME_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
SEASON_KEYS = {"kind", "label", "startDate", "endDate", "endNote", "notes", "departures"}
DEPARTURE_KEYS = {"from", "time", "days", "note", "restricted"}


def _date(value, field: str, errors: List[str]):
    if value is None:
        return None
    try:
        return dt.date.fromisoformat(value)
    except (TypeError, ValueError):
        errors.append(f"{field}: invalid date {value!r}")
        return None


def validate_season(season: Dict) -> List[str]:
    """Return a list of human-readable problems (empty list means valid)."""
    errors: List[str] = []
    if not isinstance(season, dict):
        return ["season is not an object"]
    unknown = set(season) - SEASON_KEYS - {"id", "source"}
    if unknown:
        errors.append(f"unknown season keys: {sorted(unknown)}")
    kind = season.get("kind")
    if kind not in KINDS:
        errors.append(f"kind must be one of {sorted(KINDS)}, got {kind!r}")
    if not isinstance(season.get("label"), str) or not season.get("label"):
        errors.append("label is required")
    if not isinstance(season.get("notes", []), list):
        errors.append("notes must be a list")

    start = _date(season.get("startDate"), "startDate", errors)
    end = _date(season.get("endDate"), "endDate", errors)
    if kind == "ferry":
        if start is None:
            errors.append("ferry season requires startDate")
        if end is None and not season.get("endNote"):
            errors.append("open-ended season requires endNote (e.g. 'Until heavy ice')")
    if start and end and end < start:
        errors.append(f"endDate {end} before startDate {start}")
    if start and end and (end - start).days > 366:
        errors.append("season longer than a year")

    deps = season.get("departures")
    if not isinstance(deps, list) or not deps:
        return errors + ["departures must be a non-empty list"]

    slots = {}
    per_dir = {t: 0 for t in TERMINAL_IDS}
    for i, d in enumerate(deps):
        where = f"departures[{i}]"
        if not isinstance(d, dict):
            errors.append(f"{where}: not an object")
            continue
        unknown = set(d) - DEPARTURE_KEYS
        if unknown:
            errors.append(f"{where}: unknown keys {sorted(unknown)}")
        frm, time, days = d.get("from"), d.get("time"), d.get("days")
        if frm not in TERMINAL_IDS:
            errors.append(f"{where}: from must be bayfield|lapointe, got {frm!r}")
            continue
        per_dir[frm] += 1
        if not isinstance(time, str) or not TIME_RE.match(time):
            errors.append(f"{where}: time must be HH:MM (24h), got {time!r}")
            continue
        if not ("05:00" <= time <= "23:59"):
            errors.append(f"{where}: implausible departure time {time}")
        if (
            not isinstance(days, list)
            or not days
            or any(not isinstance(x, int) or not 1 <= x <= 7 for x in days)
            or days != sorted(set(days))
        ):
            errors.append(f"{where}: days must be a sorted unique list of ISO weekdays 1-7, got {days!r}")
            continue
        for day in days:
            key = (frm, time, day)
            if key in slots:
                errors.append(f"{where}: duplicate departure {frm} {time} on weekday {day}")
            slots[key] = True

    for terminal, count in per_dir.items():
        if count == 0:
            errors.append(f"no departures from {terminal}")
        elif count > 40:
            errors.append(f"implausibly many departures from {terminal}: {count}")
    return errors


def validate_schedule(schedule: Dict) -> List[str]:
    errors: List[str] = []
    seasons = schedule.get("seasons", [])
    ids = [s.get("id") for s in seasons]
    if len(ids) != len(set(ids)):
        errors.append("duplicate season ids")
    for s in seasons:
        errors += [f"{s.get('id')}: {e}" for e in validate_season(s)]

    ferry = sorted(
        (s for s in seasons if s.get("kind") == "ferry" and s.get("startDate")),
        key=lambda s: s["startDate"],
    )
    if not ferry:
        errors.append("no ferry seasons")
    for prev, nxt in zip(ferry, ferry[1:]):
        # Open-ended seasons (e.g. "until heavy ice") implicitly end when the next season starts.
        if prev.get("endDate") and prev["endDate"] >= nxt["startDate"]:
            errors.append(f"{prev['id']} overlaps {nxt['id']}")
        if prev["startDate"] == nxt["startDate"]:
            errors.append(f"{prev['id']} and {nxt['id']} start on the same day")
    return errors


def plausibility_errors(season: Dict, today: dt.date) -> List[str]:
    """Catch year mistakes: seasons should be within roughly a year of today."""
    errors = []
    for field in ("startDate", "endDate"):
        value = season.get(field)
        if value:
            delta = (dt.date.fromisoformat(value) - today).days
            if not -400 <= delta <= 400:
                errors.append(f"{field} {value} is not within ~a year of {today} (wrong year?)")
    return errors


def gap_warnings(schedule: Dict) -> List[str]:
    ferry = sorted(
        (s for s in schedule.get("seasons", []) if s.get("kind") == "ferry" and s.get("startDate")),
        key=lambda s: s["startDate"],
    )
    warnings = []
    for prev, nxt in zip(ferry, ferry[1:]):
        if prev.get("endDate"):
            gap = (dt.date.fromisoformat(nxt["startDate"]) - dt.date.fromisoformat(prev["endDate"])).days
            if gap > 1:
                warnings.append(f"{gap - 1} day gap between {prev['id']} and {nxt['id']}")
    return warnings
