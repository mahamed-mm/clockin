<p align="center">
  <img src="docs/screenshots/hero.jpg" alt="Clockin: Tick, the kitchen-timer mascot, at work, done and on a break" width="100%">
</p>

# Clockin

A retro, one-thing-at-a-time focus timer for iPhone. Name what you're working on, start a focus session, then take a break. Built with SwiftUI and Liquid Glass on iOS 26; everything stays on the device.

## Features

- **Tick:** Clockin's mascot, a little kitchen timer whose ring is its own timer and whose crown is the start button. It leans on the dial and shows how things stand: ready (asleep at night), arms crossed and a foot tapping when paused, a jump when a session's done (proud for the fourth of a set), a kind shrug after a cancel, and feet up with a mug on a break. A focus session is a workout: Tick pulls on boxing gloves and trains in short bursts (jabs, crosses, hooks, kicks), then tires as the time runs out: slower, breathing hard, sweating, hands on knees, with one last flurry before the bell and gloves raised as the champion. Its energy is worked out from the timer, so it's right whenever you look. Settings can make it calm (in guard, no punches) or turn it off; Reduce Motion and Low Power Mode keep it calm and still. Every change springs from one pose to the next, with the face changing behind a blink, and each state has a short entrance (headphones sliding on, a jump with sparkles as the ring sweeps gold, the mug popping into its hand) and a quiet idle life: blinks, a breath now and then, a foot tapping, steam rising. Waiting, it fidgets on its own uneven beat (taps or polishes its crown, checks the dial, stretches, looks round, yawns after 20:00), its eyes follow the knob as you drag it (a raised brow at 5 or 60), and it nods when a name finds its symbol. It catches the thoughts you park and tucks them away. In Calm and Off it wears its headphones only while a focus sound plays. Its crown really is the start button: tap it to start or pause, tap its body and it giggles, and while the alarm rings a tap on Tick stops it. It never sulks, dies or nags, and there's nothing to earn. Tick is on the Lock Screen, in the Dynamic Island and in StandBy with a live ring around its face, on the widget and on the ringing alarm too, and it's the app icon: at work, or on a break if you pick that in Settings.
- **Focus sounds:** a kitchen timer's tick-tock, brown noise, rain or a fireplace through a focus session, made from scratch by `scripts/make-focus-sounds.py` (rain and fire are two loops of lengths that share no factor, so they don't line up again for half an hour). Pick one from the speaker on the running session, with its own volume, or set the default in Settings › Sounds. It fades in after the wind-up, out on Pause and back on Resume, and out before the bell so the chime or alarm always rings into silence; breaks are silent. It keeps playing on the Lock Screen, pauses for calls, and stops (but the timer doesn't) when headphones come out. A focus sound plays in Silent mode (it's a choice you made) and pauses music and podcasts unless "Mix with other audio" is on. Started from Siri, a widget or the Lock Screen it starts too, where iOS allows; otherwise the menu says it starts when you open Clockin.
- **Park a thought:** a stray thought mid-session goes in a one-line field from the notepad on the session (or Siri: "Park a thought in Clockin", a Control Center control, or the notepad on the Lock Screen card, which opens the app to the field). Tick catches it; the session says "2 parked", never a score. Parking one keeps the dial and Tick where they are: the keyboard covers the controls, the title steps aside rather than slide under the status bar, and the slip flies straight to Tick. When the session's done they fold into one quiet row ("2 parked") that opens into a short list to tick off, copy or share; through the break they're waiting too. They stay with the session and show on its card in History. Every thought not yet ticked off is gathered at the top of History ("3 open thoughts"), by subject with the day it was parked, and a cancelled session's under their own heading rather than lost. Ticking one off there draws a pen line through it, then it folds away, with Undo; Clear ticked, Copy all and Share sit underneath. Thoughts never show on the Lock Screen, in a widget or the Live Activity, and never go to the on-device model.
- **Breaks with something to do, if you like:** Settings › Break › During breaks picks how each break starts, and three quiet chips under the session (Rest · Stretch · Breathe) change it for that break. Rest is Tick with its mug. Stretch has Tick lead a short routine fitted to the break: a neck roll, a shoulder shrug, reaching up, a side stretch, wrist circles and resting the eyes on something far away, about 20 seconds each, as many as fit in 60% of the break (four in a 3-minute break, all six from 5 minutes), named on the dial with a dot for each, then the mug again. Breathe swells a soft avocado halo round the dial four seconds in and shrinks it six seconds out, with "Breathe in" / "Breathe out" on the dial, Tick breathing along, and a soft tap at each turn for eyes-closed breathing. It's all worked out from the timer, so it's right after a relaunch, and none of it is counted. Reduce Motion and Low Power Mode keep the halo and Tick still and only change the words.
- **Plan the set, if you like:** "Plan the set", first among the recent names, opens a small card to line up to four names for today: from recent names or typed, the same one more than once if you like ("Thesis, Thesis, Chemistry"), put in order by dragging (or VoiceOver's Move up and Move down), and removed. A full set says so. Then a strip of them replaces the recent names, with the plan's button always first, ticked as each one's session finishes (at the bell or with Finish now; something else in between leaves the plan alone); a repeated name ticks its first slot still to do. While you type a name, the recent names come back in the strip's place. An empty name field picks up the next planned name (on launch, coming back to the app or after a session), never over a name you typed; clear it and Start makes an unnamed session. When one's done, the next planned name moves from the strip into the name field. It's only for today and goes quietly at midnight, with nothing missed and nothing to keep up: an unfinished plan just isn't there tomorrow. It isn't in backups, and Erase all history clears it.
- **Break's over:** when a break runs out, the app says so for ten minutes (or until you start, pick a length, or midnight): "Break's over", the next session ("Next: Thesis outline · session 3 of 4", with its symbol) with its name filled in and its pill outlined, the colour turning back to orange, and Tick stretching and yawning before it's ready. With a plan, the next session is the next planned one, here, in the break's alert, on the Lock Screen's Start focus and as the first quick action. Skipping a break goes straight back to waiting.
- **One session at a time:** focus, pause and resume, or cancel without recording (and undo the cancel for a few seconds). The break starts manually and never counts as focus time.
- **Your rhythm:** Classic 25/5, Deep 50/10 or Short 15/3, and a 15-minute long break after every fourth full session of the day. "+5 min" in the last five minutes, and "Finish now" to stop early and keep the minutes. Pick the length from chips under the dial or in Settings, or drag the dial's knob like a kitchen timer to any length from 5 to 60 minutes, one detent per five minutes (its break is a fifth of it, 3 to 15 minutes). It applies from the next session.
- **Keeps going after the bell:** if you carry on past time's up, the dial keeps time in a thin rust lap round its rim, "+3 min" under the seal, once a minute for up to an hour. "Keep +3 min" adds the whole minutes to the session; starting the break or Done leaves it as it rang.
- **Calm while it runs:** eight seconds after your last touch, everything round a running dial fades back to the countdown and Pause; a tap brings it back. It stays put while paused, in the last five minutes and with VoiceOver or Switch Control. A paused dial goes still and sepia, and the header says when you paused.
- **Survives relaunch:** the timer is date-based, so a running session is restored exactly after the app is closed or the phone restarts. A session that finished while the app was closed opens quietly, saying when it finished.
- **Keeps up with the clock:** "today" moves on at midnight, and on time zone and clock changes, everywhere at once. Setting the clock back can't add time to a session.
- **A symbol for each name:** every session name gets a small symbol, guessed from the name ("Chemistry" a flask, "Spanish vocab" a globe, "Les" a stack of books, in English and Norwegian) and changed from 24 in a grid: tap the symbol at the start of the name field, or Change symbol on a session's card. It belongs to the name, so it shows on every session with it, past and future, in the field, the running session, the summary, History, the recent names, the Live Activity and the widgets. Unnamed sessions keep the book.
- **History:** today's focused minutes, then a week at a time as session columns and sessions by day, paging back to the first one. Tap a day to see it as a ribbon of its sessions, from start to end, in the order they filled the set; tap a block to open it. Week or Month: the month is a calendar of small dials, each filled to that day's sessions out of four, and a day opens its week. "By subject" shows where the week's time went, by name; tap one for its page, which zooms out of the row: all its minutes and sessions since the first, when in the day it usually happens and how long it usually runs, its recent sessions, its open thoughts, then the last three months as small ink dials for that subject alone, this month first and the two before it folded to a line each ("September 2026 · 12 sessions") that opens with a tap. Facts only: no best, no streak, no other week to compare with. From the page: Start again, Change symbol, Show in week (the old filter, also in the row's long-press) and Rename everywhere, which renames every session with the name, the one running now, today's plan and the name field, merging into another subject after asking if the name is taken, with Undo. "Share this week" makes a postcard of the week: light paper, the dates, Tick with its mug for a finished week, the total, the week's pills and its three biggest subjects by symbol (names only if you switch them on), settling from a slight tilt before you share it as a 1080 × 1350 image that describes itself. Nothing leaves the phone unless you share it. Tap a session for its card, which zooms out of the row: when it ran, focused and planned minutes, how it ended, any extra minutes beyond the plan and whether it counts toward the set, with Rename, Change symbol, Delete and a way to its subject's page. Long-press a session for the same, plus Open (its subject) and Start again, which sets Focus up with its name and length. Swipe to delete too; both offer Undo. Under the week, one line sums it up ("Mostly mornings this week; Tuesday was your longest day."). On iPhones with Apple Intelligence the on-device model writes it, from session times and lengths only, never names or symbols; everywhere else it's a fixed sentence.
- **Appearance:** System, Light or Dark in Settings, following the phone by default. The paper has a faint, still grain (none with Increase Contrast), and the dial's track a hint of Bakelite shine.
- **Kitchen-timer sounds:** a ratchet click for each five-minute detent of the knob, a wind-up and click on Start, a soft clunk on Pause and a lighter click on Resume. They're system sounds, so Silent mode mutes them and they never stop or duck your music, and they only play for what you do in the app (not Siri, Shortcuts or the Lock Screen). Settings › Sounds turns them off.
- **English and Norwegian:** every screen, the widget, alerts, Siri phrases and permission prompts. On a Norwegian phone the week line is written in Norwegian when the on-device model can, and is the fixed Norwegian sentence when it can't.
- **Your data:** export History as CSV, back it up as JSON and restore it, or erase it, all from Settings. Nothing leaves the phone unless you export it; week summaries use Apple's on-device model, and can be turned off.
- **Mindful Minutes:** turn on "Save to Apple Health" and each finished session is written to Health as Mindful Minutes, in step with History: kept overtime updates it, deleting a session removes it and Undo puts it back. Clockin only writes, never reads, and a session that ends while the phone is locked is written the next time the app runs.
- **Siri, Shortcuts and Control Center:** "Start a focus in Clockin", "Pause Clockin", "Stop Clockin", "Park a thought in Clockin", with a spoken reply (Siri never reads a thought back), and Start, Pause, Resume and Stop actions in Shortcuts (Start takes a length and a name, for that session only). On iOS 27 Siri's own timer words work too: "Set a 25-minute timer in Clockin". Stop never throws work away: past the first minute it ends the session and keeps its minutes. A Control Center, Lock Screen and Action button control does what the app's big button would: start, pause, resume or start the break.
- **Teaches itself:** no tutorial screens. On a first launch a faint thumb sweeps the dial's knob over "Drag the knob to set the time", until the length is first set or a session starts. After the very first session the summary says "That's the whole app." just once. After that, a few quiet tips (TipKit, on paper) point out what doesn't show itself: Tick's crown, a History row's menu, tapping days and subjects, the name's symbol, the break chips and parking a thought. Each waits until you've had a fair chance to find it yourself, shows once, one at a time, and never during focus.
- **Rings on time:** turn on "Ring when time's up" and the end of a session or break is an AlarmKit alarm: it sounds through Silent mode and a Focus, repeating Clockin's chime until you stop it, and after focus it offers Start break right on the alarm. Pause, +5 min and Finish now move or take it away. Without it, a notification plays the same chime. If alarms are turned off for Clockin, Settings and the Focus screen say so and link to the switch.
- **Live Activity:** a Lock Screen card and Dynamic Island with a live countdown and a pause/resume button that works without opening the app. When focus ends the card, the expanded island and StandBy offer Start break, and when a break ends, Start focus with the same name, even if the app never ran. "+5 min" shows in the last five minutes while Clockin is running to update it: always with a focus sound, otherwise only if it happens to be (a Live Activity can't change itself on a schedule). On an Apple Watch it shows in the Smart Stack as a small card: Tick in its live ring, the phase and the time left, and one button (pause or resume, Start break or Start focus); CarPlay shows the same small card. A session renamed while it runs keeps its old name on the card until it ends, as a Live Activity's name is fixed.
- **Quick actions:** touch and hold the icon to start the next planned session or one of your last ones again, or open History; during focus, to pause, park a thought or open History.
- **StandBy and bedside mode:** a full-screen bedside clock when the phone is charging on its side, and a bedside clock inside the app: open it from Settings during a session (it turns the screen even with orientation lock on) or turn the phone on its side. It uses a night palette, and the screen stays on only while the clock runs.
- **Widgets:** today's progress on the Home Screen in small, medium and large, including tinted and clear Home Screens, each with a button that does what the app's big button would (start, pause, resume or start the break) without opening it. The large one adds the week's pills, today's sessions with their symbols and, with a plan, one "Next:" line. On the Lock Screen: Tick in a ring of the time left (or today's sessions out of four), today's minutes and pills or the running session's countdown, and a line above the clock ("1 h 9 min today", "Chemistry · 12:30 left"); session names hide while the phone is locked if you ask the Lock Screen to. Tapping a widget opens the Focus screen. In History, a running session floats above the tab bar; a tap goes back to Focus.
- **Feel:** subtle haptics on every transition, a custom Core Haptics pattern and a sunburst when a session completes, the finished session's pill filling like liquid, and calm fallbacks when Reduce Motion is on.
- **Easy on the battery:** screens redraw only when something on them changes, so a paused or idle timer draws nothing. Low Power Mode and a hot phone stop the decoration.

## Accessibility

- **Contrast:** every colour that carries words reaches WCAG AA (4.5:1) on both paper tones, in light and dark, and AAA (7:1) with Increase Contrast. A test reads the colours from the asset catalog and checks every pair.
- **VoiceOver:** the dial says "24 minutes left", updating about once a minute, with Pause/Resume as an action and on the magic tap. While waiting, swipe up or down on it to change the length by five minutes. Durations are read in words, the week strip names each date and says "today", and every widget and Lock Screen surface has its own labels.
- **Voice Control:** every control answers to what's on screen, e.g. "Tap What are you focusing on" or "Tap Add 5 minutes".
- **Large text:** the Focus screen scrolls rather than pushing controls off-screen, even at the largest sizes on an iPhone SE. Rows and the completion summary stack, and icon-only buttons offer the Large Content Viewer.
- **History:** each block on a day's ribbon is a button that reads its name and times ("Chemistry, 19:00 to 19:25"), each day of the month reads its date and sessions, and a session's long-press actions are VoiceOver actions too. At the largest text sizes the month is a list of its days. A subject's page reads its facts as sentences, then its recent sessions, and each day's dial its date and sessions, with each older month a row that reads as collapsed or expanded; the plan's button comes first in its strip ("Edit plan", which Voice Control also takes as "Plan the set"), and the plan's names read "Chemistry, 1 of 4, done", with Move up, Move down and Remove as actions.
- **Breaks:** while stretching or breathing, the dial says which stretch it is ("Stretch, 2 of 4, shoulder shrug") or the pace ("Breathe, in for 4 seconds, out for 6") without announcing every move or breath.
- **Reduce Motion and Differentiate Without Color:** every animation has a calm fallback, and the session in progress is a dashed pill, not just a different colour.

## Screenshots

| Focus | Running | Kept going |
|:---:|:---:|:---:|
| <img src="docs/screenshots/focus-idle.png" width="250" alt="Focus screen, ready, with Tick leaning on the dial, Thesis outline in the name field and today's plan under it, its button first"> | <img src="docs/screenshots/focus-running.png" width="250" alt="A focus session running"> | <img src="docs/screenshots/focus-complete.png" width="250" alt="Session complete, four minutes past the bell, with the overtime lap and Keep +4 min"> |

| Stretch | Breathe | Break's over |
|:---:|:---:|:---:|
| <img src="docs/screenshots/break-stretch.png" width="250" alt="A break with Tick leading a neck roll, the stretch named on the dial"> | <img src="docs/screenshots/break-breathe.png" width="250" alt="A break spent breathing, with a soft halo round the dial and Breathe out on it"> | <img src="docs/screenshots/break-over.png" width="250" alt="Break's over, naming the next session, with Tick ready"> |

| History | Month | Long-press |
|:---:|:---:|:---:|
| <img src="docs/screenshots/history.png" width="250" alt="History with the week's session columns, today's ribbon of sessions and the week by subject"> | <img src="docs/screenshots/history-month.png" width="250" alt="The month as a calendar of small dials filled in the set's colours"> | <img src="docs/screenshots/history-menu.png" width="250" alt="A session's long-press menu: Rename, Change symbol, Start again and Delete"> |

| Session card | Settings | Lock Screen |
|:---:|:---:|:---:|
| <img src="docs/screenshots/session-card.png" width="250" alt="A session's card with its symbol, and Rename, Change symbol and Delete"> | <img src="docs/screenshots/settings.png" width="250" alt="Settings with the mascot during focus, during breaks and timer sounds"> | <img src="docs/screenshots/lock-screen.png" width="250" alt="Live Activity on the Lock Screen, with Tick on the dial"> |

| Lock Screen widgets | Home Screen widgets |
|:---:|:---:|
| <img src="docs/screenshots/lock-screen-widgets.png" width="250" alt="Clockin's Lock Screen widgets: today's minutes above the clock, minutes and pills, and Tick in a ring"> | <img src="docs/screenshots/widget.png" width="250" alt="The large and medium widgets on the Home Screen, each with a Start button"> |

| Focus sound | Park a thought | Parked thoughts |
|:---:|:---:|:---:|
| <img src="docs/screenshots/sound-menu.png" width="250" alt="The focus sound menu over a running session: Off, Tick-tock, Brown noise, Rain (ticked) and Fireplace, with a volume slider"> | <img src="docs/screenshots/park-thought.png" width="250" alt="A one-line field above the keyboard during focus, with a thought being typed, the dial and Tick still full size and the title out of the way"> | <img src="docs/screenshots/parked-list.png" width="250" alt="Focus complete with Keep +4 min and two parked thoughts folded into one row, Done for now above the tab bar"> |

| A tip |
|:---:|
| <img src="docs/screenshots/tip.png" width="250" alt="A quiet tip on paper at the end of a session: Park a stray thought"> |

| Plan the set | Break's over, planned | Open thoughts |
|:---:|:---:|:---:|
| <img src="docs/screenshots/plan.png" width="250" alt="Plan the set on paper: Chemistry done, then Thesis outline, Linear algebra and Thesis outline again, each with its symbol, to drag into order or remove, and a line saying the set is full"> | <img src="docs/screenshots/break-over-plan.png" width="250" alt="Break's over, with the next planned session, Thesis outline, in the name field and the Next line"> | <img src="docs/screenshots/open-thoughts.png" width="250" alt="Open thoughts in History, by subject with the day each was parked, and the cancelled sessions' under their own heading"> |

| A subject's page | The week's postcard |
|:---:|:---:|
| <img src="docs/screenshots/subject-page.png" width="250" alt="Reading: Dune's page: 20 h 47 min over 50 sessions since 14 July, usually in the morning, with its actions and its recent sessions"> | <img src="docs/screenshots/postcard.png" width="250" alt="The week's postcard before sharing: light paper, the week's dates, Tick ready, 8 h 52 min, the week's pills and the three biggest subjects by symbol, with Show names off"> |

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
- **Liquid Glass:** a prominent glass primary button, a session field that morphs into the session chip, glass chips, and card sheets that float at the height of their content, on paper so nothing behind them shows through.

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
| `-DemoData` | Fills an empty store with fourteen weeks of sample sessions, a few symbol picks, today's plan (one done) and open thoughts across several subjects, and hides the debug menu and the alert hints |
| `-DemoPostcard 1` | Opens History's postcard for the week that many weeks back (0 for this one); the debug menu's "Postcard for a week" does the same |
| `-DemoNow 09:41` | Shows today at 09:41 in the app and the widgets: Tick's hour, the `-DemoData` sessions and a running session's times ("Ends 9:43") move, while timers keep the real clock. Pair it with `xcrun simctl status_bar booted override --time 09:41` |
| `-DemoSound rain` | Plays that focus sound (`tickTock`, `brownNoise`, `rain`, `fireplace` or `off`) through sessions started this run, as if picked in Settings |
| `-DemoMascot calm` | Tick during focus (`workout`, `calm` or `off`), as if picked in Settings |
| `-DemoFinishing` | Starts a 25-minute session that ends 3 seconds after launch |
| `-DemoOvertime` | A 25-minute session that ended four minutes before launch, for the overtime screen |
| `-DemoThoughts` | With `-DemoFinishing` or `-DemoOvertime`: two thoughts parked in that session |
| `-DemoBreak` | A break halfway through (seconds long with `-ShortTimers`); add `-DemoBreakStyle stretch` or `breathe` to spend it that way from launch |
| `-DemoBreakOver` | A break that ran out 30 seconds before launch, for the "Break's over" screen |
| `-DemoTip ParkTip` | Shows that tip whatever its rules (`CrownTip`, `SymbolTip`, `HistoryTapTip`, `HistoryMenuTip`, `BreakChipsTip`, `ParkTip`), for screenshots |
| `-ResetOnboarding` | Shows the first-launch hints and every tip again (also in the debug menu, from the next launch) |

Run the tests:

```bash
xcodebuild test -project Clockin.xcodeproj -scheme Clockin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The paper grain is a Metal shader, so building needs the Metal Toolchain (Xcode › Settings › Components, or `xcodebuild -downloadComponent MetalToolchain`).

CI (`.github/workflows/ci.yml`) installs the Metal Toolchain, generates the project, runs the tests on an iPhone simulator and builds Release for devices on every push to `main` and every pull request.

Copy lives in `Shared/Design/Copy.swift` (one phrase per moment) and `Shared/Localizable.xcstrings`, which holds the plural forms. Xcode adds new strings to the catalog when it builds; after a command-line build, run `scripts/sync-strings.sh` (pass `-derivedDataPath`'s folder if you used one). Every string has a Norwegian translation (`nb`), checked by `ClockinTests/LocalizationTests.swift`, as do `Clockin/InfoPlist.xcstrings` (permission prompts) and `Clockin/Intents/AppShortcuts.xcstrings` (Siri phrases). Developer-only strings are marked not to translate.

The sounds are made from scratch: `scripts/make-chime.sh` for the end chime and `scripts/make-sounds.sh` for the timer's ratchet, wind-up and clicks.

README screenshots come from a freshly erased simulator launched with `-DemoData -DemoNow 09:41`, its status bar set with `xcrun simctl status_bar booted override --time 09:41`, captured with `xcrun simctl io <device> screenshot --mask=alpha` and framed by `scripts/frame-screenshot.sh`.

`scripts/render-tick.sh` draws Tick on the Mac from the app's own code: `sheet` and `shapes` for contact sheets of every pose, `workout`, `moves`, `breath` and `ending` for the workout's stances, moves and last minute, `break` for the break's stretches, `icon` for the app icons' layers (`Clockin/AppIcon.icon`, `Clockin/AppIconBreak.icon`) and `hero` for the banner.

Logs go to the unified log under the subsystem `com.moha.clockin` (categories `store`, `live-activity`, `notifications`, `audio`). Filter for it in Console.app. Errors are logged in full, and session names are never logged.

### Data compatibility

- History is a SwiftData store with a versioned schema (`Shared/Model/ClockinSchema.swift`). Never edit a shipped version. Add a new one and a migration stage instead. V2 added planned length, time zone and outcome, all optional, with a lightweight migration from 1.0.
- Settings are saved as JSON in the App Group's defaults and always load: a missing or unknown value falls back to its default (during breaks falls back to Rest, timer sounds to on, focus sound to off).
- The running session is saved as JSON in the App Group's defaults. Fields added after 1.0 must be optional. Format 4 added a break's style and when it began (an unknown style reads as Rest) and the "Break's over" moment; format 5 a focus session's sound (an unknown one reads as off), its parked thoughts and the focus session a break follows. Older state loads with none.
- Parked thoughts kept after their session are a JSON file in the app's own Application Support folder (`Clockin/Services/ThoughtStore.swift`), outside the App Group so the widget extension can't read them, keyed by session id, with the unfiled ones from cancelled sessions. History's schema is unchanged. Deleting a session forgets its thoughts once Undo has gone; Erase all history clears them.
- The Live Activity's content state only gains optional fields (`canExtend`), so a card started by an older build still decodes.
- The widget doesn't open the store. The app writes today's sessions (with their names and symbols) and the week's totals to the App Group (`Shared/Store/WidgetSnapshot.swift`) after every change; fields added later are optional, so an older snapshot still reads. Until the app has written one, the widget reads today from the store read-only, so it can never run a migration.
- `ClockinTests/StoreCompatibilityTests.swift` checks both against real data written by 1.0, including `ClockinTests/Fixtures/ClockinV1.store`, which it migrates to V2.
- Each session name's symbol is saved as JSON in the App Group's defaults (`Shared/Store/SymbolBook.swift`), keyed by the name ignoring case and extra spaces. Only picked symbols are saved; a missing or unknown one shows the book. Picks for names no session has any more are dropped, and Erase all history clears them.
- Today's plan is JSON in the App Group's defaults (`plan.v1`, `Shared/Store/SetPlanStore.swift`), so a widget can read it. It belongs to one day, is dropped when the day moves on, isn't in backups, and Erase all history clears it. An unreadable one is no plan.
- The Live Activity's content state gained an optional next planned session (`next`), and the widget snapshot the same (`next`); older ones read as no plan.
- Rename everywhere changes the saved names in place. Restoring a backup made before a rename brings the old names back on those sessions (a restore matches by id), as with any edit since the backup.
- Backups (`Clockin/Settings/HistoryExport.swift`) carry a format number. A restore matches sessions by id, so restoring the same backup twice changes nothing. Format 2 added each name's symbol and format 3 parked thoughts (merged by id): older backups still restore, a restore never replaces a symbol picked on this phone, and a backup from a newer format says so instead of failing.

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
