"""Advisories (madferry.com/weather-alerts) and current service status."""

import datetime as dt
import re
from typing import Dict, List, Optional

BOILERPLATE = [
    re.compile(r"no active alerts", re.I),
    re.compile(r"texting madferry", re.I),
]
ALERTS_URL = "https://madferry.com/weather-alerts"
TEXT_ALERTS = "Text MADFERRY to 715-200-9057 for schedule changes and cancellations."
WINDSLED_HOTLINE = "715-747-5400"


def advisories(paragraphs: List[str]) -> List[Dict[str, str]]:
    return [{"text": p} for p in paragraphs if not any(rx.search(p) for rx in BOILERPLATE)]


def season_for(schedule: Dict, day: dt.date) -> Optional[Dict]:
    """Ferry season covering `day`. Open-ended seasons run until the next season starts."""
    ferry = sorted(
        (s for s in schedule.get("seasons", []) if s["kind"] == "ferry"), key=lambda s: s["startDate"]
    )
    iso = day.isoformat()
    for i, s in enumerate(ferry):
        end = s.get("endDate")
        if end is None and i + 1 < len(ferry):
            end = (dt.date.fromisoformat(ferry[i + 1]["startDate"]) - dt.timedelta(days=1)).isoformat()
        if s["startDate"] <= iso and (end is None or iso <= end):
            return s
    return None


def status(schedule: Dict, items: List[Dict[str, str]], override: Optional[Dict], today: dt.date) -> Dict:
    if override and (not override.get("until") or override["until"] >= today.isoformat()):
        return {
            "mode": override["mode"],
            "disrupted": bool(override.get("disrupted", False)),
            "message": override.get("message"),
            "source": "override",
        }

    text = " ".join(i["text"] for i in items).lower()
    disrupted = bool(re.search(r"cancel|suspend|delay|not running|no service|closed", text))
    if "ice road" in text and re.search(r"ice road (is )?(now )?open", text):
        mode, source = "ice_road", "advisory"
    elif "windsled" in text and not re.search(r"windsled[^.]*(ended|done|finished|no longer)", text):
        mode, source = "windsled", "advisory"
    elif season_for(schedule, today):
        mode, source = "ferry", "schedule"
    else:
        mode, source = "unknown", "schedule"
    message = items[0]["text"] if items else None
    return {"mode": mode, "disrupted": disrupted, "message": message, "source": source}
