<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Focus, completion and History screens" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a 25-minute focus session, then take a 5-minute break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **One session at a time:** 25-minute focus, pause and resume, or cancel without recording (and undo the cancel for a few seconds). A 5-minute break starts manually and never counts as focus time.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts. A session that finished while the app was closed opens quietly, saying when it finished.
- **Keeps up with the clock:** "today" moves on at midnight, and on time zone and clock changes, everywhere at once. Setting the clock back can't add time to a session.
- **History:** today's focused minutes, this week as session columns, and every completed session grouped by day.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a landscape bedside layout inside the app.
- **Home Screen widget:** today's progress in small and medium sizes, including tinted and clear Home Screens; tapping it opens the Focus screen.
- **Feel:** subtle haptics on every transition, a custom Core Haptics pattern and a sunburst when a session completes, and calm fallbacks when Reduce Motion is on.

## Screenshots

| Focus | Running | Complete |
|:---:|:---:|:---:|
| <img src="docs/screenshots/focus-idle.png" width="250" alt="Focus screen, ready to start"> | <img src="docs/screenshots/focus-running.png" width="250" alt="A focus session running"> | <img src="docs/screenshots/focus-complete.png" width="250" alt="Session complete with the sunburst"> |

| History | Lock Screen | Home Screen widget |
|:---:|:---:|:---:|
| <img src="docs/screenshots/history.png" width="250" alt="History with the week's session columns"> | <img src="docs/screenshots/lock-screen.png" width="250" alt="Live Activity on the Lock Screen"> | <img src="docs/screenshots/widget.png" width="250" alt="Medium widget on the Home Screen"> |

| StandBy | Dynamic Island |
|:---:|:---:|
| <img src="docs/screenshots/standby.png" width="420" alt="StandBy bedside timer"> | <img src="docs/screenshots/dynamic-island.png" width="380" alt="Expanded Dynamic Island"> |

## Design

- **Warm 70s palette:** paper, ink, rust, burnt orange, mustard and avocado, with full light and dark modes.
- **One progress language:** the dial shows the running timer; pills show focus sessions (four per set, filling rust → orange → mustard → avocado). The same pills appear in the app, the widget, the Lock Screen and StandBy.
- **Typography:** serif display numerals for the countdown, small tracked labels and rounded text for details.
- **Liquid Glass:** a prominent glass primary button and a session field that morphs into the session chip.

## Requirements

- Xcode 26 or later (iOS 26 SDK)
- iOS 26 or later (iPhone)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting started

The Xcode project is generated from `project.yml` and is not checked in.

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Clockin.xcodeproj
```

To run on your own iPhone, change these in `project.yml`, then run `xcodegen generate` again:

- `DEVELOPMENT_TEAM`: your team ID
- `bundleIdPrefix` and the `PRODUCT_BUNDLE_IDENTIFIER` values
- `APP_GROUP_ID`: an App Group your team owns. Both targets' entitlements and the app's storage read it from there.

A free Personal Team is enough. The end-of-timer alert is marked time-sensitive, but the entitlement that lets it break through Focus needs a paid Apple Developer Program team. If you have one, uncomment `com.apple.developer.usernotifications.time-sensitive` in `project.yml`.

## Development

Debug builds accept these launch arguments (Product → Scheme → Edit Scheme → Arguments). None of them exist in Release builds.

| Argument | Effect |
|---|---|
| `-ShortTimers` | 10-second focus and 5-second break, for this run only |
| `-SlowAnimations` | Plays every animation 4× slower |
| `-DemoData` | Fills an empty store with a week of sample sessions and hides the debug menu |
| `-DemoFinishing` | Starts a 25-minute session that ends 3 seconds after launch |

Run the tests:

```bash
xcodebuild test -project Clockin.xcodeproj -scheme Clockin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI (`.github/workflows/ci.yml`) generates the project, runs the tests on an iPhone simulator and builds Release for devices on every push to `main` and every pull request.

Logs go to the unified log under the subsystem `com.moha.clockin` (categories `store`, `live-activity`, `notifications`). Filter for it in Console.app. Errors are logged in full, and session names are never logged.

### Data compatibility

- History is a SwiftData store with a versioned schema (`Shared/Model/ClockinSchema.swift`). Never edit a shipped version. Add a new one and a migration stage instead.
- The running session is saved as JSON in the App Group's defaults. Fields added after 1.0 must be optional.
- The widget doesn't open the store. The app writes today's totals to the App Group (`Shared/Store/WidgetSnapshot.swift`) after every change; until it has, the widget reads the store read-only, so it can never run a migration.
- `ClockinTests/StoreCompatibilityTests.swift` checks both against real data written by 1.0, including `ClockinTests/Fixtures/ClockinV1.store`.

## Project structure

```
Clockin/          App: Focus and History screens, services (Live Activity, haptics, notifications), debug tools
ClockinWidgets/   Widget extension: Home Screen widget, Live Activity, Dynamic Island
Shared/           Code used by both: session engine, SwiftData model, stores, design system, StandBy view
ClockinTests/     Swift Testing suite: engine, side effects, stats, data compatibility (with 1.0 fixtures), formatting
docs/screenshots/ Images used in this README
```

## License

No license has been chosen yet.
