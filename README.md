<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Focus, completion and History screens" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a 25-minute focus session, then take a 5-minute break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **One session at a time:** 25-minute focus, pause and resume, or cancel without recording. A 5-minute break starts manually and never counts as focus time.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts.
- **History:** today's focused minutes, this week as session columns, and every completed session grouped by day.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a landscape bedside layout inside the app.
- **Home Screen widget:** today's progress in small and medium sizes; tapping it opens the Focus screen.
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
- the App Group `group.com.moha.clockin`, in both targets' entitlements

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

## Project structure

```
Clockin/          App: Focus and History screens, services (Live Activity, haptics, notifications), debug tools
ClockinWidgets/   Widget extension: Home Screen widget, Live Activity, Dynamic Island
Shared/           Code used by both: session engine, SwiftData model, stores, design system, StandBy view
ClockinTests/     Swift Testing suite for the engine, stats, persistence and formatting
docs/screenshots/ Images used in this README
```

## License

No license has been chosen yet.
