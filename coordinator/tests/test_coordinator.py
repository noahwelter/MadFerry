import datetime as dt
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from madferry_coordinator import build, extract, fetch, live, validate

FIX = Path(__file__).parent / "fixtures"
EXPECTED = FIX / "expected"


def expected(name):
    return build.normalize_season(json.loads((EXPECTED / f"{name}.json").read_text()))


def record(h, season, first_seen="2026-01-01", url=None):
    return {"sourceHash": h, "sourceUrl": url or f"https://x/{h}.jpg", "firstSeen": first_seen, "season": season}


def ferry(start, end, end_note=None, label=None):
    return build.normalize_season({
        "kind": "ferry", "label": label or start, "startDate": start, "endDate": end, "endNote": end_note,
        "departures": [{"from": "bayfield", "time": "08:00", "days": [1, 2, 3, 4, 5, 6, 7]},
                       {"from": "lapointe", "time": "08:30", "days": [1, 2, 3, 4, 5, 6, 7]}],
    })


class FetchTests(unittest.TestCase):
    def test_schedule_images_resolve_original_upload_urls_in_page_order(self):
        page = json.loads((FIX / "page-2909.json").read_text())
        urls = [i["url"] for i in fetch.schedule_images(page["content"]["rendered"])]
        self.assertEqual(urls, [
            "https://madferry.com/wp-content/uploads/2026/02/SEPTEMBER-8-NOVEMBER-1-2026-1.jpg",
            "https://madferry.com/wp-content/uploads/2026/02/NOVEMBER-2-thru-29-26.jpg",
            "https://madferry.com/wp-content/uploads/2026/02/NOVEMBER-30-ICE-2026-1.jpg",
        ])

    def test_alerts_boilerplate_is_not_an_advisory(self):
        page = json.loads((FIX / "page-570.json").read_text())
        self.assertEqual(live.advisories(fetch.paragraphs(page["content"]["rendered"])), [])


class ExtractTests(unittest.TestCase):
    def test_chat_sends_bearer_api_key(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = (
            b'{"choices":[{"message":{"content":"{}"}}]}'
        )
        with patch.object(extract, "_config", return_value=("https://example.test", "test-key", "test-model")):
            with patch.object(extract.urllib.request, "urlopen", return_value=response) as urlopen:
                self.assertEqual(extract._chat([]), {})

        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("Authorization"), "Bearer test-key")


class ValidateTests(unittest.TestCase):
    def test_hand_transcribed_fixtures_are_valid(self):
        for path in EXPECTED.glob("*.json"):
            with self.subTest(path.name):
                self.assertEqual(validate.validate_season(expected(path.stem)), [])

    def test_detects_bad_times_days_and_duplicates(self):
        season = ferry("2026-05-01", "2026-06-01")
        season["departures"] += [
            {"from": "bayfield", "time": "8:00", "days": [1], "note": None, "restricted": False},
            {"from": "lapointe", "time": "08:30", "days": [1], "note": None, "restricted": False},
            {"from": "lapointe", "time": "09:30", "days": [0, 8], "note": None, "restricted": False},
        ]
        errors = " ".join(validate.validate_season(season))
        self.assertIn("HH:MM", errors)
        self.assertIn("duplicate", errors)
        self.assertIn("ISO weekdays", errors)

    def test_open_ended_needs_end_note_and_wrong_year_is_flagged(self):
        self.assertTrue(validate.validate_season(ferry("2026-11-30", None)))
        self.assertTrue(validate.plausibility_errors(ferry("2028-05-01", "2028-06-01"), dt.date(2026, 10, 23)))

    def test_open_ended_season_followed_by_later_season_is_allowed(self):
        sched = {"seasons": [dict(ferry("2026-11-30", None, "Until heavy ice"), id="a"),
                             dict(ferry("2027-04-01", "2027-06-01"), id="b")]}
        self.assertEqual(validate.validate_schedule(sched), [])


class MergeTests(unittest.TestCase):
    today = dt.date(2026, 10, 23)

    def test_archived_seasons_are_kept_after_images_leave_the_site(self):
        records = {"old": record("old", ferry("2026-05-15", "2026-09-07")),
                   "cur": record("cur", ferry("2026-09-08", "2026-11-01"))}
        seasons = build.merge_seasons(records, {"cur": {}}, self.today)
        self.assertEqual([(s["startDate"], s["source"]["onSiteNow"]) for s in seasons],
                         [("2026-05-15", False), ("2026-09-08", True)])

    def test_on_site_images_supersede_overlapping_archived_seasons(self):
        records = {"old": record("old", ferry("2026-09-01", "2026-11-15")),
                   "cur": record("cur", ferry("2026-09-08", "2026-11-01"))}
        seasons = build.merge_seasons(records, {"cur": {}}, self.today)
        self.assertEqual([(s["startDate"], s["endDate"]) for s in seasons],
                         [("2026-09-01", "2026-09-07"), ("2026-09-08", "2026-11-01")])

    def test_archived_open_ended_season_ends_before_next_season(self):
        records = {"ice": record("ice", ferry("2026-11-30", None, "Until heavy ice")),
                   "spring": record("spring", ferry("2027-04-01", "2027-06-01"))}
        seasons = build.merge_seasons(records, {"spring": {}}, dt.date(2027, 3, 1))
        self.assertEqual(seasons[0]["endDate"], "2027-03-31")
        self.assertIsNone(seasons[0]["endNote"])

    def test_seasons_older_than_retention_are_pruned(self):
        records = {"old": record("old", ferry("2025-05-01", "2025-06-01"))}
        self.assertEqual(build.merge_seasons(records, {}, self.today), [])

    def test_uncovered_ranges_report_missing_future_schedule(self):
        records = {"cur": record("cur", ferry("2026-09-08", "2026-11-01"))}
        sched = build.build_schedule(records, {"cur": {}}, None, None, self.today)
        self.assertEqual(build.uncovered_ranges(sched, self.today, 20),
                         [(dt.date(2026, 11, 2), dt.date(2026, 11, 12))])


class LiveTests(unittest.TestCase):
    sched = {"seasons": [dict(ferry("2026-11-30", None, "Until heavy ice"), id="ice")]}

    def test_status_from_schedule_and_advisories(self):
        today = dt.date(2027, 1, 20)
        self.assertEqual(live.status(self.sched, [], None, today)["mode"], "ferry")
        st = live.status(self.sched, [{"text": "The windsled is now running. Ferry service has ended."}], None, today)
        self.assertEqual(st["mode"], "windsled")
        st = live.status(self.sched, [{"text": "The ice road is open to vehicles."}], None, today)
        self.assertEqual(st["mode"], "ice_road")
        self.assertEqual(live.status({"seasons": []}, [], None, today)["mode"], "unknown")

    def test_override_wins_until_expiry(self):
        override = {"mode": "closed", "message": "Freeze-up", "until": "2027-01-21"}
        self.assertEqual(live.status(self.sched, [], override, dt.date(2027, 1, 21))["mode"], "closed")
        self.assertEqual(live.status(self.sched, [], override, dt.date(2027, 1, 22))["mode"], "ferry")


if __name__ == "__main__":
    unittest.main()
