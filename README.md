# MadFerry

Unofficial schedule and trip-planning app for the Madeline Island Ferry Line in
Bayfield, Wisconsin. MadFerry brings departure times, service advisories, travel
estimates, leave-by reminders, widgets, and Apple Watch support together in one
place.

> MadFerry is an independent project and is not affiliated with or endorsed by
> the Madeline Island Ferry Line. Schedules and service can change; confirm
> current information with the [official ferry website](https://madferry.com/).

## App

The app targets iPhone, iPad, Mac, and Apple Watch. It uses SwiftUI, MapKit,
WidgetKit, and ActivityKit. The schedule is bundled for offline use; the app can
also refresh schedule and advisory data from a static JSON feed.

### Build and run

Requirements:

- macOS with Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS/iPadOS 26 or later for iPhone and iPad; macOS 26 or later for Mac; watchOS
  26 or later for Apple Watch

From the repository root:

```sh
cd app
xcodegen generate
open MadFerry.xcodeproj
```

In Xcode, choose the `MadFerry` scheme and a destination, select a development
team for code signing, then build and run. To run on a personal device, connect
it to the Mac and follow Xcode's signing prompts. Widgets and Watch features
share data through an App Group; the App Group identifiers in `app/Config/`
must be registered for the signing team if those capabilities are to work.
This repository does not currently provide an App Store installation.

Run the FerryKit unit tests from the repository root:

```sh
swift test --package-path app/FerryKit
```

The Xcode project is generated from `app/project.yml` and is intentionally not
committed. The project defines the `MadFerry`, `MadFerryWidgets`,
`MadFerryWatch`, and `MadFerryWatchWidgets` targets.

## Data feed

The app's default feed is hosted at
[`noahwelter.github.io/MadFerry`](https://noahwelter.github.io/MadFerry/).
The feed contains:

- `v1/schedule.json` — ferry and windsled schedules
- `v1/live.json` — service status, advisories, and alert information

The app includes a bundled schedule as an offline fallback. A working hosted
feed is not required to build the app.

### Host your own feed

The included coordinator fetches the official ferry pages, extracts schedule
data, validates it, and writes the JSON files published by GitHub Pages. To run
the pipeline for a fork:

1. Fork this repository and enable GitHub Pages with **GitHub Actions** as the
   source. Public repositories can use GitHub Pages on GitHub Free.
2. In **Settings → Secrets and variables → Actions**, add an `LLM_API_KEY`
   secret for the OpenAI-compatible extraction provider. You can optionally set
   `LLM_MODEL` and `LLM_BASE_URL` as repository variables.
3. In **Settings → Actions → General**, allow GitHub Actions to create pull
   requests. The workflow uses this to open a review PR when the schedule
   changes.
4. Run **Daily schedule scrape** from the Actions tab once, then check the Pages
   site for `v1/schedule.json` and `v1/live.json`.
5. If you want the app to use your fork's feed, change
   `FerryConfig.feedBaseURL` in
   `app/FerryKit/Sources/FerryKit/FeedClient.swift` to your Pages URL, including
   the `/v1/` suffix.

The API key is only needed by the automated extraction workflow; it is not
needed to build or use the app with an existing feed. API provider usage may
incur charges. Keep the key in GitHub Actions secrets and never commit it.

The daily workflow commits live status updates directly. Schedule changes are
opened as a pull request for review before publication. For a manual correction
or unexpected closure, see [Manual status overrides](#manual-status-overrides).

## Coordinator development

The Python coordinator has no third-party Python dependencies and supports
Python 3.9 or later. Run commands from the `coordinator/` directory:

```sh
python3 -m unittest discover -s tests -t .
python3 -m madferry_coordinator check --data ../data
python3 -m madferry_coordinator render --data ../data
```

To run a scrape without calling the extraction provider:

```sh
python3 -m madferry_coordinator run --data ../data --out ../out --no-llm
```

To extract new or changed source material, set `LLM_API_KEY` in your environment
and run:

```sh
python3 -m madferry_coordinator run --data ../data --out ../out
```

`LLM_BASE_URL` and `LLM_MODEL` are optional environment variables for choosing
another compatible provider or model. Use an endpoint you trust with your API
key.

The `run` command writes a report to `out/report.md`:

- Exit code `0`: no problems were found.
- Exit code `3`: the run completed, but reported problems; review the report.
  Invalid or incomplete schedule data is not published.
- Exit code `1`: the command failed unexpectedly; the error is printed to
  standard error.

The `check` command exits `0` when the published schedule and extraction records
are valid, or `1` when validation fails. The `render` command prints the
published schedule as Markdown.

### Manual status overrides

Create `data/overrides.json` to override the automatically determined service
status. The `until` date is inclusive:

```json
{
  "mode": "closed",
  "message": "No crossings due to high winds",
  "until": "2026-11-05",
  "disrupted": true
}
```

`mode` must be `ferry`, `windsled`, `ice_road`, or `closed`. Omit `until` to
leave an override active until it is removed. Trigger **Daily schedule scrape**
manually to publish the change. Remove the file or let its expiration date pass
to resume automatic status.

### Schedule extraction records

Each source extraction is archived under `data/extractions/` by content hash.
The published schedule is assembled from current and archived records so that
seasons disappear from the source page without immediately disappearing from
the app. To correct an extraction, edit the matching record and rerun the
coordinator with `--no-llm`; the published schedule is rebuilt from the archive.

To refresh the app's offline fallback after changing the schedule:

```sh
# Run from the repository root.
cp data/v1/schedule.json app/FerryKit/Sources/FerryKit/Resources/BundledSchedule.json
```

## Project layout

```text
app/          SwiftUI app, widgets, Watch app, and FerryKit package
coordinator/  Python fetch, extraction, validation, and feed-generation tools
data/         Archived extractions and published JSON feeds
.github/      CI, daily scrape, and Pages deployment workflows
```

## License

No license file is currently provided. Contact the project maintainer before
reusing or redistributing the code.
