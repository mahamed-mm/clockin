<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Focus, completion and History screens" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a focus session, then take a break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **One session at a time:** focus, pause and resume, or cancel without recording (and undo the cancel for a few seconds). The break starts manually and never counts as focus time.
- **Your rhythm:** Classic 25/5, Deep 50/10 or Short 15/3, and a 15-minute long break after every fourth full session of the day. "+5 min" in the last five minutes, and "Finish now" to stop early and keep the minutes. Changes in Settings apply from the next session.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts. A session that finished while the app was closed opens quietly, saying when it finished.
- **Keeps up with the clock:** "today" moves on at midnight, and on time zone and clock changes, everywhere at once. Setting the clock back can't add time to a session.
- **History:** today's focused minutes, then a week at a time as session columns and sessions by day, paging back to the first one. Swipe to delete (with undo), tap to rename.
- **Your data:** export History as CSV, back it up as JSON and restore it, or erase it, all from Settings. Nothing leaves the phone unless you export it.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a bedside clock inside the app: tap the moon during a session (it turns the screen even with orientation lock on) or turn the phone on its side. It uses a night palette, and the screen stays on only while the clock runs.
- **Home Screen widget:** today's progress in small and medium sizes, including tinted and clear Home Screens; tapping it opens the Focus screen. Away from Focus, a running session also sits above the tab bar.
- **Feel:** subtle haptics on every transition, a custom Core Haptics pattern and a sunburst when a session completes, and calm fallbacks when Reduce Motion is on.
- **Easy on the battery:** screens redraw only when something on them changes, so a paused or idle timer draws nothing. Low Power Mode and a hot phone stop the decoration.

## Accessibility

- **Contrast:** every colour that carries words reaches WCAG AA (4.5:1) on both paper tones, in light and dark, and AAA (7:1) with Increase Contrast. A test reads the colours from the asset catalog and checks every pair.
- **VoiceOver:** the dial says "24 minutes left", updating about once a minute, with Pause/Resume as an action and on the magic tap. Durations are read in words, the week strip names each date and says "today", and every widget and Lock Screen surface has its own labels.
- **Voice Control:** every control answers to what's on screen, e.g. "Tap What are you focusing on" or "Tap Add 5 minutes".
- **Large text:** the Focus screen scrolls rather than pushing controls off-screen, even at the largest sizes on an iPhone SE. Rows and the completion summary stack, and icon-only buttons offer the Large Content Viewer.
- **Reduce Motion and Differentiate Without Color:** every animation has a calm fallback, and the session in progress is a dashed pill, not just a different colour.

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
- **One progress language:** every ring and bar shows time left and drains as it runs, in the app, the widget, the Lock Screen, StandBy and the Dynamic Island; a finished phase is a full mustard ring. Pills show focus sessions (four per set, filling rust → orange → mustard → avocado), the same everywhere.
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
| `-ShortTimers` | 10-second focus and 5-second break (15-second long break), for this run only |
| `-SlowAnimations` | Plays every animation 4× slower |
| `-DemoData` | Fills an empty store with a week of sample sessions and hides the debug menu |
| `-DemoFinishing` | Starts a 25-minute session that ends 3 seconds after launch |

Run the tests:

```bash
xcodebuild test -project Clockin.xcodeproj -scheme Clockin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI (`.github/workflows/ci.yml`) generates the project, runs the tests on an iPhone simulator and builds Release for devices on every push to `main` and every pull request.

Copy lives in `Shared/Design/Copy.swift` (one phrase per moment) and `Shared/Localizable.xcstrings`, which holds the plural forms. Xcode adds new strings to the catalog when it builds; after a command-line build, run `scripts/sync-strings.sh`.

Logs go to the unified log under the subsystem `com.moha.clockin` (categories `store`, `live-activity`, `notifications`). Filter for it in Console.app. Errors are logged in full, and session names are never logged.

### Data compatibility

- History is a SwiftData store with a versioned schema (`Shared/Model/ClockinSchema.swift`). Never edit a shipped version. Add a new one and a migration stage instead. V2 added planned length, time zone and outcome, all optional, with a lightweight migration from 1.0.
- Settings are saved as JSON in the App Group's defaults and always load: a missing or unknown value falls back to its default.
- The running session is saved as JSON in the App Group's defaults. Fields added after 1.0 must be optional.
- The widget doesn't open the store. The app writes today's totals to the App Group (`Shared/Store/WidgetSnapshot.swift`) after every change; until it has, the widget reads the store read-only, so it can never run a migration.
- `ClockinTests/StoreCompatibilityTests.swift` checks both against real data written by 1.0, including `ClockinTests/Fixtures/ClockinV1.store`, which it migrates to V2.
- Backups (`Clockin/Settings/HistoryExport.swift`) carry a format number. A restore matches sessions by id, so restoring the same backup twice changes nothing.

## Project structure

```
Clockin/          App: Focus, History and Settings screens, services (Live Activity, haptics, notifications, history changes), export, debug tools
ClockinWidgets/   Widget extension: Home Screen widget, Live Activity, Dynamic Island
Shared/           Code used by both: session engine, SwiftData model, stores, design system, StandBy view
ClockinTests/     Swift Testing suite: engine, presets and long breaks, side effects, stats, history changes, export, data compatibility (with 1.0 fixtures), copy
docs/screenshots/ Images used in this README
```

## License

No license has been chosen yet.
