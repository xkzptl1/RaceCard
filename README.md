# RaceCard

A native macOS second-screen Formula 1 timing and race-visualization companion powered primarily by OpenF1.

**Source-available for personal and non-commercial use.** Commercial use is not permitted under the supplied [PolyForm Noncommercial License 1.0.0](LICENSE). This is not an open-source license. Modification and non-commercial redistribution are permitted only as provided by that license.

## Screenshots

No screenshots are included in this public source edition: previous captures contain third-party photographs, marks, or source-derived diagrams without confirmed redistribution permission. The application can be built and run to inspect its neutral fallback presentation.

## Features

- Historical Replay and an offline simulated demo
- Recorded vehicle positions and circuit visualization
- Race Control events, Safety Car, VSC and Red Flag state
- Tyre and stint history, pit timing and fastest-lap summaries
- Driver Focus telemetry where the provider supplies it
- Championship views and driver/team profiles
- Qualifying timing cards, phase ranking and cut lines
- English and Japanese interfaces
- Optional authenticated OpenF1 Live support

The public edition excludes proprietary branding and traced circuit presentation assets. Team badges use neutral text monograms. Driver photos are optional runtime downloads with a generic avatar fallback. Recorded XY maps remain available; official diagram layers and their associated calibrations are omitted. See [public-build differences](Documentation/PUBLIC_BUILD.md).

## Requirements

- macOS 15 or later; the supplied build instructions target Apple Silicon.
- Xcode 26.5 or later recommended for the pinned dependencies; the clean validation report records the tested version. Swift package tools minimum is 5.9; application sources use Swift 5 language mode.
- Python 3 for project generation and publication checks.
- Internet for initial Swift dependency resolution and uncached Historical data. The offline demo needs no Live credentials.

## Getting started

From this repository's root:

```sh
./Scripts/build.sh
open build/Products/RaceCard.app
```

Alternatively open `RaceCard.xcodeproj`, select the RaceCard scheme and My Mac, then Build/Run. You do not need a paid Apple signing identity for a local build. No developer replay cache or credentials are included.

The app opens the offline demo. Choose **Sessions**, select a year and a Historical Race or Qualifying session, wait for loading, and press Play. Uncached data depends on provider availability. During temporary access restrictions, cached timing stays available and location requests retry automatically, including while paused.

[English installation](INSTALL_EN.md) · [日本語インストール](INSTALL_JA.md)

## OpenF1 configuration

Historical requests normally work without authentication when the provider permits access. Live requires your own OpenF1 authorization, which may involve credentials, a paid tier, or other provider approval under its current terms. Enter credentials in the app's Settings; never commit them or put them in an issue.

RaceCard stores credentials in the macOS Keychain, scoped to its application bundle identifier. Access tokens remain in memory. Replay and image caches are stored in the user's standard Application Support/Caches directories and are not repository content. `RACECARD_STORAGE_ROOT` can point to an absolute, writable directory for an isolated test installation; it does not supply credentials.

## Data sources

RaceCard consumes [OpenF1](https://openf1.org/) data and RaceCard-maintained factual metadata with source provenance. Read the [OpenF1 documentation](https://openf1.org/docs/) and [upstream license](https://github.com/br-g/openf1/blob/main/LICENSE). OpenF1 and its data sources remain subject to their own conditions; RaceCard's license does not replace or override them. Users are responsible for compliance. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Project status

RaceCard is an unofficial personal/fan project, not a production service. Data coverage varies and no production SLA is offered. Public-source builds intentionally have fewer bundled visuals than the author's private preview. Existing private preview binaries are not cleared by this repository's publication pass and are not supplied here.

## License

RaceCard's original source code is source-available under [PolyForm Noncommercial 1.0.0](LICENSE). Source access, personal/non-commercial use and modification are allowed subject to its terms. Non-commercial redistribution must follow those terms. **Commercial use is not licensed by this repository.**

Anyone interested in commercial use must separately obtain all necessary permissions and licenses from every applicable rights holder and data provider. The RaceCard author cannot grant rights belonging to Formula 1, FIA, teams, drivers, OpenF1 or other third parties. Dependencies, third-party data and other third-party materials retain their own terms and are not relicensed by RaceCard.

## Disclaimer

RaceCard is an unofficial, non-commercial fan project. It is not affiliated with, endorsed by, or sponsored by Formula 1, Formula One Management, Formula One Licensing, the FIA, OpenF1, any Formula 1 constructor/team, or any driver.

All trademarks, logos, images, names, and other third-party materials remain the property of their respective rights holders. Formula 1/F1 and related marks, team names and logos, driver names and imagery, and event branding may be protected by trademark, copyright, publicity or other rights. RaceCard's source-code license grants no rights to those third-party materials or to third-party data.
