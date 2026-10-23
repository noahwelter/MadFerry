"""Schema + sanity validation for extracted seasons and the assembled schedule."""

import datetime as dt
import re
from typing import Dict, List
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from . import SCHEMA_VERSION

KINDS = {"ferry", "windsled"}
TERMINAL_IDS = {"bayfield", "lapointe"}
TIME_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SEASON_KEYS = {"kind", "label", "startDate", "endDate", "endNote", "notes", "departures"}
DEPARTURE_KEYS = {"from", "time", "days", "note", "restricted"}


def _date(value, field: str, errors: List[str]):
    if value is None:
        return None
    if not isinstance(value, str) or not DATE_RE.fullmatch(value):
        errors.append(f"{field}: invalid date {value!r}")
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
    if not isinstance(kind, str) or kind not in KINDS:
        errors.append(f"kind must be one of {sorted(KINDS)}, got {kind!r}")
    if not isinstance(season.get("label"), str) or not season.get("label"):
        errors.append("label is required")
    notes = season.get("notes", [])
    if not isinstance(notes, list) or any(not isinstance(note, str) for note in notes):
        errors.append("notes must be a list of strings")
    end_note = season.get("endNote")
    if end_note is not None and not isinstance(end_note, str):
        errors.append("endNote must be a string or null")

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
        if not isinstance(frm, str) or frm not in TERMINAL_IDS:
            errors.append(f"{where}: from must be bayfield|lapointe, got {frm!r}")
            continue
        per_dir[frm] += 1
        if not isinstance(time, str) or not TIME_RE.match(time):
            errors.append(f"{where}: time must be HH:MM (24h), got {time!r}")
            continue
        if not ("05:00" <= time <= "23:59"):
            errors.append(f"{where}: implausible departure time {time}")
        if not isinstance(days, list) or not days or any(type(x) is not int or not 1 <= x <= 7 for x in days):
            errors.append(f"{where}: days must be a sorted unique list of ISO weekdays 1-7, got {days!r}")
            continue
        if days != sorted(set(days)):
            errors.append(f"{where}: days must be a sorted unique list of ISO weekdays 1-7, got {days!r}")
            continue
        if d.get("note") is not None and not isinstance(d.get("note"), str):
            errors.append(f"{where}: note must be a string or null")
        if "restricted" in d and not isinstance(d["restricted"], bool):
            errors.append(f"{where}: restricted must be a boolean")
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
    if not isinstance(schedule, dict):
        return ["schedule is not an object"]
    errors: List[str] = []
    version = schedule.get("schemaVersion")
    if type(version) is not int or version != SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {SCHEMA_VERSION}")
    timezone = schedule.get("timeZone")
    if not isinstance(timezone, str):
        errors.append("timeZone must be a valid IANA timezone")
    else:
        try:
            ZoneInfo(timezone)
        except (ValueError, ZoneInfoNotFoundError):
            errors.append(f"timeZone must be a valid IANA timezone, got {timezone!r}")
    crossing = schedule.get("crossingMinutes")
    if type(crossing) is not int or crossing <= 0:
        errors.append("crossingMinutes must be a positive integer")

    terminals = schedule.get("terminals")
    if not isinstance(terminals, list):
        errors.append("terminals must be a list")
    else:
        terminal_ids = []
        for terminal in terminals:
            if not isinstance(terminal, dict):
                errors.append("every terminal must be an object")
                continue
            terminal_id = terminal.get("id")
            if not isinstance(terminal_id, str) or terminal_id not in TERMINAL_IDS:
                errors.append(f"terminal id must be one of {sorted(TERMINAL_IDS)}, got {terminal_id!r}")
            else:
                terminal_ids.append(terminal_id)
            for field in ("name", "address"):
                if not isinstance(terminal.get(field), str) or not terminal[field]:
                    errors.append(f"terminal {terminal_id!r}: {field} must be a non-empty string")
            for field, lower, upper in (("latitude", -90, 90), ("longitude", -180, 180)):
                value = terminal.get(field)
                if (isinstance(value, bool) or not isinstance(value, (int, float))
                        or not lower <= value <= upper):
                    errors.append(f"terminal {terminal_id!r}: {field} must be between {lower} and {upper}")
        if sorted(terminal_ids) != sorted(TERMINAL_IDS):
            errors.append("terminals must contain bayfield and lapointe exactly once")

    seasons = schedule.get("seasons")
    if not isinstance(seasons, list):
        return errors + ["seasons must be a list"]
    if any(not isinstance(season, dict) for season in seasons):
        return errors + ["every season must be an object"]
    ids = [s.get("id") for s in seasons]
    valid_ids = [season_id for season_id in ids if isinstance(season_id, str)]
    if len(valid_ids) != len(set(valid_ids)):
        errors.append("duplicate season ids")
    if any(not isinstance(season_id, str) or not season_id for season_id in ids):
        errors.append("every season must have a non-empty string id")
    for s in seasons:
        errors += [f"{s.get('id')}: {e}" for e in validate_season(s)]

    ferry = []
    for season in seasons:
        if season.get("kind") != "ferry":
            continue
        start = season.get("startDate")
        if not isinstance(start, str) or not DATE_RE.fullmatch(start):
            continue
        try:
            dt.date.fromisoformat(start)
        except ValueError:
            continue
        ferry.append(season)
    ferry.sort(key=lambda season: season["startDate"])
    if not ferry:
        errors.append("no ferry seasons")
    for prev, nxt in zip(ferry, ferry[1:]):
        # Open-ended seasons (e.g. "until heavy ice") implicitly end when the next season starts.
        end = prev.get("endDate")
        if isinstance(end, str) and DATE_RE.fullmatch(end):
            try:
                if dt.date.fromisoformat(end) >= dt.date.fromisoformat(nxt["startDate"]):
                    errors.append(f"{prev.get('id')} overlaps {nxt.get('id')}")
            except ValueError:
                pass
        if prev["startDate"] == nxt["startDate"]:
            errors.append(f"{prev.get('id')} and {nxt.get('id')} start on the same day")
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
