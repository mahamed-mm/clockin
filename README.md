<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Focus, completion and History screens" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a focus session, then take a break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **One session at a time:** focus, pause and resume, or cancel without recording (and undo the cancel for a few seconds). The break starts manually and never counts as focus time.
- **Your rhythm:** Classic 25/5, Deep 50/10 or Short 15/3, and a 15-minute long break after every fourth full session of the day. "+5 min" in the last five minutes, and "Finish now" to stop early and keep the minutes. Pick the length from chips under the dial or in Settings, or drag the dial's knob like a kitchen timer to any length from 5 to 60 minutes, one detent per five minutes (its break is a fifth of it, 3 to 15 minutes). It applies from the next session.
- **Calm while it runs:** eight seconds after your last touch, everything round a running dial fades back to the countdown and Pause; a tap brings it back. It stays put while paused, in the last five minutes and with VoiceOver or Switch Control. A paused dial goes still and sepia, and the header says when you paused.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts. A session that finished while the app was closed opens quietly, saying when it finished.
- **Keeps up with the clock:** "today" moves on at midnight, and on time zone and clock changes, everywhere at once. Setting the clock back can't add time to a session.
- **History:** today's focused minutes, then a week at a time as session columns and sessions by day, paging back to the first one. Tap a session for its card: when it ran, focused and planned minutes, how it ended and whether it counts toward the set, with Rename and Delete. Swipe to delete too; both offer Undo. Under the week, one line sums it up ("Mostly mornings this week; Tuesday was your longest day."). On iPhones with Apple Intelligence the on-device model writes it, from session times and lengths only, never names; everywhere else it's a fixed sentence.
- **Appearance:** System, Light or Dark in Settings, following the phone by default.
- **Your data:** export History as CSV, back it up as JSON and restore it, or erase it, all from Settings. Nothing leaves the phone unless you export it; week summaries use Apple's on-device model, and can be turned off.
- **Rings on time:** turn on "Ring when time's up" and the end of a session or break is an AlarmKit alarm: it sounds through Silent mode and a Focus, repeating Clockin's chime until you stop it, and after focus it offers Start break right on the alarm. Pause, +5 min and Finish now move or take it away. Without it, a notification plays the same chime. If alarms are turned off for Clockin, Settings and the Focus screen say so and link to the switch.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a bedside clock inside the app: open it from Settings during a session (it turns the screen even with orientation lock on) or turn the phone on its side. It uses a night palette, and the screen stays on only while the clock runs.
- **Home Screen widget:** today's progress in small and medium sizes, including tinted and clear Home Screens; tapping it opens the Focus screen. Away from Focus, a running session also sits above the tab bar.
- **Feel:** subtle haptics on every transition, a custom Core Haptics pattern and a sunburst when a session completes, and calm fallbacks when Reduce Motion is on.
- **Easy on the battery:** screens redraw only when something on them changes, so a paused or idle timer draws nothing. Low Power Mode and a hot phone stop the decoration.

## Accessibility

- **Contrast:** every colour that carries words reaches WCAG AA (4.5:1) on both paper tones, in light and dark, and AAA (7:1) with Increase Contrast. A test reads the colours from the asset catalog and checks every pair.
- **VoiceOver:** the dial says "24 minutes left", updating about once a minute, with Pause/Resume as an action and on the magic tap. While waiting, swipe up or down on it to change the length by five minutes. Durations are read in words, the week strip names each date and says "today", and every widget and Lock Screen surface has its own labels.
- **Voice Control:** every control answers to what's on screen, e.g. "Tap What are you focusing on" or "Tap Add 5 minutes".
- **Large text:** the Focus screen scrolls rather than pushing controls off-screen, even at the largest sizes on an iPhone SE. Rows and the completion summary stack, and icon-only buttons offer the Large Content Viewer.
- **Reduce Motion and Differentiate Without Color:** every animation has a calm fallback, and the session in progress is a dashed pill, not just a different colour.

## Screenshots

| Focus | Running | Complete |
|:---:|:---:|:---:|
| <img src="docs/screenshots/focus-idle.png" width="250" alt="Focus screen with the dial set to 35 minutes and the length chips"> | <img src="docs/screenshots/focus-running.png" width="250" alt="A focus session running"> | <img src="docs/screenshots/focus-complete.png" width="250" alt="Session complete with the sunburst"> |

| History | Session card | Settings |
|:---:|:---:|:---:|
| <img src="docs/screenshots/history.png" width="250" alt="History with the week's session columns and a line about the week"> | <img src="docs/screenshots/session-card.png" width="250" alt="A session's card, with Rename and Delete"> | <img src="docs/screenshots/settings.png" width="250" alt="Settings with lengths, appearance and the bedside clock"> |

| Lock Screen | Home Screen widget |
|:---:|:---:|
| <img src="docs/screenshots/lock-screen.png" width="250" alt="Live Activity on the Lock Screen"> | <img src="docs/screenshots/widget.png" width="250" alt="Medium widget on the Home Screen"> |

| Bedside clock | Dynamic Island |
|:---:|:---:|
| <img src="docs/screenshots/bedside.png" width="420" alt="The bedside clock in landscape"> | <img src="docs/screenshots/dynamic-island.png" width="380" alt="Expanded Dynamic Island"> |

## Design

- **Warm 70s palette:** paper, ink, rust, burnt orange, mustard and avocado, with full light and dark modes.
- **One progress language:** every ring and bar shows time left and drains as it runs. The app's dial is a 60-minute kitchen-timer face, so a session unwinds from where you set the knob; the widget, Lock Screen, StandBy and Dynamic Island rings start full. A finished phase is a full mustard ring everywhere. Pills show focus sessions (four per set, filling rust → orange → mustard → avocado), the same everywhere.
- **Typography:** [Fraunces](https://github.com/undercasetype/Fraunces), a soft 70s serif, for titles, session names and every countdown, including the widget and Live Activity; SF Pro Rounded for everything you read in passing. `scripts/make-fonts.sh` builds three static cuts from the variable font and gives them tabular digits, which Fraunces doesn't ship, so the countdown never shifts sideways. Small tracked labels carry the appliance feel.
- **One system:** a spacing scale with one screen edge, a type scale that follows Dynamic Type and Bold Text, motion tokens with Reduce Motion fallbacks, and one recipe for small modals (a close button, a centred header, grouped rows, then the actions). Destructive actions read in rust.
- **Liquid Glass:** a prominent glass primary button, a session field that morphs into the session chip, glass chips, and card sheets that float at the height of their content.

## Credits

Fraunces by Undercase Type, under the SIL Open Font License 1.1 (`Shared/Fonts/OFL.txt`). Clockin bundles modified cuts named Fraunces Clockin.

The chime (`Clockin/Sounds/clockin-ding.caf`) is synthesised from scratch by `scripts/make-chime.sh`: a two-note bell, 24 seconds, so it fits the 30-second limit for notification sounds.

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

A free Personal Team is enough, alarms included: AlarmKit needs only the usage description in `project.yml`. The notification alert is marked time-sensitive, but the entitlement that lets a notification break through Focus needs a paid Apple Developer Program team; with "Ring when time's up" on, the alarm does that anyway. If you have a paid team, uncomment `com.apple.developer.usernotifications.time-sensitive` in `project.yml`.

The simulator can't fully test alarms: on iOS 27 it denies AlarmKit without asking, and on iOS 26.5 SpringBoard crashes when an alarm starts to ring. Try them on a device.

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

README screenshots come from a simulator launched with `-DemoData`, captured with `xcrun simctl io <device> screenshot --mask=alpha` and framed by `scripts/frame-screenshot.sh`.

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
