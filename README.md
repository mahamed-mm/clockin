<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Tick, the kitchen-timer mascot, at work, done and on a break" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a focus session, then take a break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **Tick:** Clockin's mascot, a little kitchen timer whose ring is its own timer and whose crown is the start button. It leans on the dial and shows how things stand: ready (asleep at night), arms crossed and a foot tapping when paused, a jump when a session's done (proud for the fourth of a set), a kind shrug after a cancel, and feet up with a mug on a break. A focus session is a workout: Tick pulls on boxing gloves and trains in short bursts (jabs, crosses, hooks, kicks), then tires as the time runs out: slower, breathing hard, sweating, hands on knees, with one last flurry before the bell and gloves raised as the champion. Its energy is worked out from the timer, so it's right whenever you look. Settings can make it calm (in guard, no punches) or turn it off; Reduce Motion and Low Power Mode keep it calm and still. Every change springs from one pose to the next, with the face changing behind a blink, and each state has a short entrance (headphones sliding on, a jump with sparkles as the ring sweeps gold, the mug popping into its hand) and a quiet idle life: blinks, a breath now and then, a foot tapping, steam rising. Its crown really is the start button: tap it to start or pause, tap its body and it giggles, and while the alarm rings a tap on Tick stops it. It never sulks, dies or nags, and there's nothing to earn. Tick is on the Lock Screen, in the Dynamic Island and in StandBy with a live ring around its face, on the widget and on the ringing alarm too, and it's the app icon: at work, or on a break if you pick that in Settings.
- **One session at a time:** focus, pause and resume, or cancel without recording (and undo the cancel for a few seconds). The break starts manually and never counts as focus time.
- **Your rhythm:** Classic 25/5, Deep 50/10 or Short 15/3, and a 15-minute long break after every fourth full session of the day. "+5 min" in the last five minutes, and "Finish now" to stop early and keep the minutes. Pick the length from chips under the dial or in Settings, or drag the dial's knob like a kitchen timer to any length from 5 to 60 minutes, one detent per five minutes (its break is a fifth of it, 3 to 15 minutes). It applies from the next session.
- **Keeps going after the bell:** if you carry on past time's up, the dial keeps time in a thin rust lap round its rim, "+3 min" under the seal, once a minute for up to an hour. "Keep +3 min" adds the whole minutes to the session; starting the break or Done leaves it as it rang.
- **Calm while it runs:** eight seconds after your last touch, everything round a running dial fades back to the countdown and Pause; a tap brings it back. It stays put while paused, in the last five minutes and with VoiceOver or Switch Control. A paused dial goes still and sepia, and the header says when you paused.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts. A session that finished while the app was closed opens quietly, saying when it finished.
- **Keeps up with the clock:** "today" moves on at midnight, and on time zone and clock changes, everywhere at once. Setting the clock back can't add time to a session.
- **History:** today's focused minutes, then a week at a time as session columns and sessions by day, paging back to the first one. Tap a session for its card: when it ran, focused and planned minutes, how it ended, any extra minutes beyond the plan and whether it counts toward the set, with Rename and Delete. Swipe to delete too; both offer Undo. Under the week, one line sums it up ("Mostly mornings this week; Tuesday was your longest day."). On iPhones with Apple Intelligence the on-device model writes it, from session times and lengths only, never names; everywhere else it's a fixed sentence.
- **Appearance:** System, Light or Dark in Settings, following the phone by default.
- **Your data:** export History as CSV, back it up as JSON and restore it, or erase it, all from Settings. Nothing leaves the phone unless you export it; week summaries use Apple's on-device model, and can be turned off.
- **Mindful Minutes:** turn on "Save to Apple Health" and each finished session is written to Health as Mindful Minutes, in step with History: kept overtime updates it, deleting a session removes it and Undo puts it back. Clockin only writes, never reads, and a session that ends while the phone is locked is written the next time the app runs.
- **Siri, Shortcuts and Control Center:** "Start a focus in Clockin", "Pause Clockin", "Stop Clockin", with a spoken reply, and Start, Pause, Resume and Stop actions in Shortcuts (Start takes a length and a name, for that session only). On iOS 27 Siri's own timer words work too: "Set a 25-minute timer in Clockin". Stop never throws work away: past the first minute it ends the session and keeps its minutes. A Control Center, Lock Screen and Action button control does what the app's big button would: start, pause, resume or start the break.
- **Teaches itself:** no tutorial screens. On a first launch a faint thumb sweeps the dial's knob over "Drag the knob to set the time", until the length is first set or a session starts. After the very first session the summary says "That's the whole app." just once.
- **Rings on time:** turn on "Ring when time's up" and the end of a session or break is an AlarmKit alarm: it sounds through Silent mode and a Focus, repeating Clockin's chime until you stop it, and after focus it offers Start break right on the alarm. Pause, +5 min and Finish now move or take it away. Without it, a notification plays the same chime. If alarms are turned off for Clockin, Settings and the Focus screen say so and link to the switch.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a bedside clock inside the app: open it from Settings during a session (it turns the screen even with orientation lock on) or turn the phone on its side. It uses a night palette, and the screen stays on only while the clock runs.
- **Home Screen widget:** today's progress in small and medium sizes, including tinted and clear Home Screens; tapping it opens the Focus screen. In History, a running session floats above the tab bar; a tap goes back to Focus.
- **Feel:** subtle haptics on every transition, a custom Core Haptics pattern and a sunburst when a session completes, and calm fallbacks when Reduce Motion is on.
- **Easy on the battery:** screens redraw only when something on them changes, so a paused or idle timer draws nothing. Low Power Mode and a hot phone stop the decoration.

## Accessibility

- **Contrast:** every colour that carries words reaches WCAG AA (4.5:1) on both paper tones, in light and dark, and AAA (7:1) with Increase Contrast. A test reads the colours from the asset catalog and checks every pair.
- **VoiceOver:** the dial says "24 minutes left", updating about once a minute, with Pause/Resume as an action and on the magic tap. While waiting, swipe up or down on it to change the length by five minutes. Durations are read in words, the week strip names each date and says "today", and every widget and Lock Screen surface has its own labels.
- **Voice Control:** every control answers to what's on screen, e.g. "Tap What are you focusing on" or "Tap Add 5 minutes".
- **Large text:** the Focus screen scrolls rather than pushing controls off-screen, even at the largest sizes on an iPhone SE. Rows and the completion summary stack, and icon-only buttons offer the Large Content Viewer.
- **Reduce Motion and Differentiate Without Color:** every animation has a calm fallback, and the session in progress is a dashed pill, not just a different colour.

## Screenshots

| Focus | Running | Kept going |
|:---:|:---:|:---:|
| <img src="docs/screenshots/focus-idle.png" width="250" alt="Focus screen, ready, with Tick leaning on the dial"> | <img src="docs/screenshots/focus-running.png" width="250" alt="A focus session running"> | <img src="docs/screenshots/focus-complete.png" width="250" alt="Session complete, four minutes past the bell, with the overtime lap and Keep +4 min"> |

| History | Session card | Settings |
|:---:|:---:|:---:|
| <img src="docs/screenshots/history.png" width="250" alt="History with the week's session columns and a line about the week"> | <img src="docs/screenshots/session-card.png" width="250" alt="A session's card, with Rename and Delete"> | <img src="docs/screenshots/settings.png" width="250" alt="Settings with lengths, appearance and the bedside clock"> |

| Lock Screen | Home Screen widget |
|:---:|:---:|
| <img src="docs/screenshots/lock-screen.png" width="250" alt="Live Activity on the Lock Screen, with Tick on the dial"> | <img src="docs/screenshots/widget.png" width="250" alt="Medium widget on the Home Screen"> |

| Bedside clock | Dynamic Island |
|:---:|:---:|
| <img src="docs/screenshots/bedside.png" width="420" alt="The bedside clock in landscape"> | <img src="docs/screenshots/dynamic-island.png" width="380" alt="Expanded Dynamic Island"> |

## Design

<p align="center"><img src="docs/screenshots/app-icons.png" width="260" alt="The two app icons: Tick at work with headphones, and Tick on a break with a mug"></p>

- **Tick:** a round Bakelite timer in the palette (cream face, terracotta ring, mustard crown) with a clock hand for an eyebrow. One silhouette per pose, so each reads even as a solid shape. Each part (limbs, ring, face, eyes, mouth, brow, crown, props) is its own SwiftUI view, posed by a small set of numbers (`TickRig`, `TickFace`) that spring from state to state; its colours live in the asset catalog. The same code draws it in the app, the widgets, the icon (`scripts/render-tick.sh`) and this README's banner, and the detail follows the size, down to a head-only glyph. Motion is calm and cheap: frames are drawn only while something moves (a blink, a tap, a hop, a combo), never in the background or off screen, and Reduce Motion and Low Power Mode keep it still. The workout's moves are SwiftUI keyframe timelines, sampled from the session's own clock with a seeded combo schedule, so Tick lands on the right move however the app was opened. A debug-build gallery (`-MascotGallery`) shows every state in light and dark at each size. More in [docs/tick.md](docs/tick.md): how it's built, where it can move, and what it costs.

- **Warm 70s palette:** paper, ink, rust, burnt orange, mustard and avocado, with full light and dark modes.
- **One progress language:** every ring and bar shows time left and drains as it runs. The app's dial is a 60-minute kitchen-timer face, so a session unwinds from where you set the knob; the widget, Lock Screen, StandBy and Dynamic Island rings start full. A finished phase is a full mustard ring everywhere. Pills show focus sessions (four per set, filling rust → orange → mustard → avocado), the same everywhere.
- **Typography:** [Fraunces](https://github.com/undercasetype/Fraunces), a soft 70s serif, for titles, session names and every countdown, including the widget and Live Activity; SF Pro Rounded for everything you read in passing. `scripts/make-fonts.sh` builds three static cuts from the variable font and gives them tabular digits, which Fraunces doesn't ship, so the countdown never shifts sideways. Small tracked labels carry the appliance feel.
- **One system:** a spacing scale with one screen edge, a type scale that follows Dynamic Type and Bold Text, motion tokens with Reduce Motion fallbacks, and one recipe for small modals (a close button, a centred header, grouped rows, then the actions). Destructive actions read in rust.
- **Liquid Glass:** a prominent glass primary button, a session field that morphs into the session chip, glass chips, and card sheets that float at the height of their content.

## Credits

Fraunces by Undercase Type, under the SIL Open Font License 1.1 (`Shared/Fonts/OFL.txt`). Clockin bundles modified cuts named Fraunces Clockin.

The chime (`Clockin/Sounds/clockin-ding.caf`) is synthesised from scratch by `scripts/make-chime.sh`: a two-note bell, 24 seconds, so it fits the 30-second limit for notification sounds.

Tick, the app icons and the banner are drawn in code in this repository (`Shared/Mascot`, `scripts/render-tick.sh`); no generated or licensed art.

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
| `-DemoOvertime` | A 25-minute session that ended four minutes before launch, for the overtime screen |
| `-ResetOnboarding` | Shows the first-launch hints again (also in the debug menu) |

Run the tests:

```bash
xcodebuild test -project Clockin.xcodeproj -scheme Clockin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI (`.github/workflows/ci.yml`) generates the project, runs the tests on an iPhone simulator and builds Release for devices on every push to `main` and every pull request.

Copy lives in `Shared/Design/Copy.swift` (one phrase per moment) and `Shared/Localizable.xcstrings`, which holds the plural forms. Xcode adds new strings to the catalog when it builds; after a command-line build, run `scripts/sync-strings.sh`.

README screenshots come from a simulator launched with `-DemoData`, captured with `xcrun simctl io <device> screenshot --mask=alpha` and framed by `scripts/frame-screenshot.sh`.

`scripts/render-tick.sh` draws Tick on the Mac from the app's own code: `sheet` and `shapes` for contact sheets of every pose, `workout`, `moves`, `breath` and `ending` for the workout's stances, moves and last minute, `icon` for the app icons' layers (`Clockin/AppIcon.icon`, `Clockin/AppIconBreak.icon`) and `hero` for the banner.

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
