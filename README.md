# MadFerry

An unofficial iPhone / iPad / Mac / Apple Watch app for planning around the
[Madeline Island Ferry](https://madferry.com) (Bayfield ↔ La Pointe): next departures,
"leave by" times based on your drive to the terminal, widgets, complications, a Live
Activity countdown, advisories, and ice-season (windsled / ice road) status.

Not affiliated with the Madeline Island Ferry Line. Always confirm with the official site.

## Architecture

```
madferry.com ──(GitHub Actions, daily)──► coordinator (Python)
   schedule images, windsled page, alerts page
        │  vision LLM extraction → validation → merge with archive
        ▼
   data/v1/schedule.json  (changes arrive as a PR for human review)
   data/v1/live.json      (advisories + service status, committed directly)
        │  GitHub Pages
        ▼
   FerryKit (Swift package) ── App Group cache ── app · widgets · watch · Live Activity
```

- **Coordinator** (`coordinator/`, stdlib-only Python 3.9+): the ferry site publishes each
  season as a JPG whose title and date range change over the year, and only current/upcoming
  seasons are shown. Every extraction is archived in `data/extractions/` (keyed by image hash),
  and the published schedule is the merge of all of them: images currently on the site win,
  older seasons are trimmed around them, and anything that ended more than ~a year ago is pruned.
  Uncovered upcoming dates are reported as warnings.
- **Daily workflow** (`.github/workflows/daily-scrape.yml`): commits `live.json` directly; opens
  a `schedule-update` PR (label `schedule-review`) when the schedule changes; opens a
  `scrape-problem` issue if extraction or validation fails. Merging deploys Pages.
- **App** (`app/`): SwiftUI using standard system components (Liquid Glass tab bar/sidebar,
  toolbars, lists), WidgetKit (home/lock screen, desktop, watch complications), ActivityKit,
  MapKit travel-time estimates, and local leave-by notifications.

## One-time setup

1. Create a **public** GitHub repo `MadFerry` (free Pages needs public) and push.
   If the owner/name differs, update `FerryConfig.feedBaseURL` in
   `app/FerryKit/Sources/FerryKit/FeedClient.swift`.
2. Settings → Pages → Source: **GitHub Actions**.
3. Settings → Secrets → Actions: add `LLM_API_KEY` (a Google Gemini API key).
   Optional repository variables: `LLM_MODEL` (default `gemini-3.8-flash`) and `LLM_BASE_URL`
   (any OpenAI-compatible endpoint).
4. Settings → Actions → General: allow GitHub Actions to create pull requests.
5. Run **Daily scrape** once via *Run workflow*, then check
   `https://<owner>.github.io/MadFerry/v1/schedule.json`.

## Coordinator

```sh
cd coordinator
python3 -m unittest discover -s tests -t .                  # tests
python3 -m madferry_coordinator run --data ../data --out ../out --no-llm   # offline run (archive only)
LLM_API_KEY=… python3 -m madferry_coordinator run --data ../data --out ../out
python3 -m madferry_coordinator check --data ../data        # validate published data
LLM_API_KEY=… python3 eval_extraction.py                    # compare LLM output with hand transcriptions
```

Exit codes: `0` OK, `3` problems found (see `out/report.md`), `1` crash.

**Fixing a bad extraction:** edit the record in `data/extractions/<hash>.json` (or in the PR
branch), then rerun `run --no-llm` to rebuild `data/v1/schedule.json`.

**Manual status override** (e.g. unexpected closure): create `data/overrides.json`:

```json
{ "mode": "closed", "message": "No crossings due to high winds", "until": "2026-11-05", "disrupted": true }
```

`mode` is one of `ferry`, `windsled`, `ice_road`, `closed`; `until` is an inclusive date. The
override is applied the next time the scrape runs (trigger **Daily scrape** manually for
immediate effect). Remove the file (or let `until` pass) to return to automatic status.

## App

Requires Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd app
xcodegen generate            # creates MadFerry.xcodeproj (not committed)
open MadFerry.xcodeproj
swift test --package-path FerryKit
```

Targets: `MadFerry` (iOS/iPadOS/macOS), `MadFerryWidgets`, `MadFerryWatch`,
`MadFerryWatchWidgets`. All share the App Group `group.com.noahwelter.madferry`.

The app ships with a bundled copy of the schedule as an offline fallback. Refresh it before
release builds:

```sh
cp data/v1/schedule.json app/FerryKit/Sources/FerryKit/Resources/BundledSchedule.json
```

### Signing / TestFlight

1. Set `DEVELOPMENT_TEAM` in `app/Config/Signing.xcconfig`.
2. In the developer portal (or let Xcode manage signing) register the App Group
   `group.com.noahwelter.madferry` for all four bundle IDs (`com.noahwelter.madferry`,
   `.widgets`, `.watchkitapp`, `.watchkitapp.widgets`).
3. `xcodegen generate`, then Product → Archive → Distribute → TestFlight
   (repeat with the *My Mac* destination for the macOS build).
