# Tick, in motion

How Clockin's mascot is built, where it can move, and what it costs.

## How it's put together

- **State:** `TickPose`, ten states. `TickDirector` (in `Shared/Model/TickPose+Session.swift`) picks one from the session, the alarm and the clock:
  - The ringing alarm beats everything.
  - A set of four shows done, then the streak.
  - Hello appears on first launch or after a week away.
  - Tick falls asleep at night or after ten idle minutes.
- **Pose and face:** `TickRig` and `TickFace` describe each state as numbers: limb positions, lean, squash, props, eyebrow angle. A change of state springs between them, and the eyes and mouth swap behind a blink.
- **Parts:** each layer is its own view in `Shared/Mascot/Parts`, stacked back to front:
  1. legs
  2. ring track and time-left arc
  3. face, cheeks, eyes, mouth and eyebrow hand
  4. arms
  5. the arc's cap
  6. crown
  7. props and effects

  The colours are the `Tick…` colour sets in the asset catalog.
- **Life:** `TickLoops` gives each state its idle motion and its entrance as a pure function of time. `TickView` draws a frame only while something moves.

## The workout

A focus session is a workout (Settings › Mascot during focus: Workout, Calm or Off). Everything lives in `Shared/Mascot/Workout`, and all of it is worked out from the timer's dates, never counted, so a session opened mid-way or come back to from the background shows exactly where it is.

- **Energy:** `WorkoutEnergy` turns the planned length and time left into a phase and a 0–1 energy. Pauses don't count, as the time left stands still.

  | Phase | When |
  |---|---|
  | warm-up | the first 45 s, or the first 10% if shorter |
  | strong | until tired |
  | tired | from 5 min left, or 40% left if shorter |
  | exhausted | from 60 s left, or 10% left if shorter |
  | final push | the last 10 s |

- **The look:** `WorkoutParams` is the one place the fatigue is tuned: tempo, reach, rests, bounce, breathing, sweat, hunch, the face. Gloves are mustard like the crown, with darker cuffs; Tick faces right, away from the digits and the knob.
- **Moves:** `WorkoutMove` is a set of SwiftUI `KeyframeTimeline`s (jab, cross, hook, uppercut, two kicks, a duck, warm-up and worn-out moves, the flurry), sampled at any time, each starting and ending in guard. Hits squeeze the eyes, squash the body and burst lines at the glove.
- **Combos:** `ComboScheduler` lays out a whole session from its seed: never the same combo twice running, rests from the params, rounds of 3–4 combos with 8–12 s of stillness between while strong, every timing divided by the tempo.
- **Fatigue:** `WorkoutLoops` adds a bounce between combos in a round, breathing that quickens through the tired stretch (its phase added up, so it never jumps), panting in time, puffs of breath, a blink at each face change, and a half-second ease when Tick drops onto its knees and gets back up. `SweatEmitter` drips drops off the head as a function of time (at most six) and flings one with each tired punch.
- **Around the session:** gloves pop on and tap together at the start; a pause drops to guard in 0.3 s and waits with gloves on (still panting and sweating once tired); resume goes straight back; a cancel gets a shrug for 3 s; Finish now and the bell end on the champion, gloves raised; the gloves come off for the break.
- **Calm and still:** Calm stays in guard with the tiring face and no punches. Reduce Motion and Low Power Mode show calm stills that cross-fade at each face change. The bedside clock is always calm, and so is working on past the bell.

## The break

A break is rest, a stretch or breathing (Settings › Break › During breaks, or the chips on the break screen for one break). Everything lives in `Shared/Mascot/Break` and, like the workout, is worked out from the break's own clock: `TickBreak` holds its length, end and the style with when it began, in the break's time, so a pause doesn't count and a relaunch lands on the same moment.

- **Stretch:** `StretchMove` is a set of slow `KeyframeTimeline`s on the standing Tick (neck roll, shoulder shrug, reach up, side stretch, wrist circles, eye rest), each about 20 seconds with holds, starting and ending on the stance; hands going up high swing their elbows out round the ring. `StretchRoutine` fits them to what's left of the break: as many as fit in 60% of it, chosen eyes first, done in an order that flows, 2 s apart. `BreakLoops` eases Tick up off the ground as the mug goes, plays the routine, then eases it back down to the mug. Each stretch has a still pose for Reduce Motion and Low Power Mode.
- **Breathe:** `BreathCycle` is 4 s in, 6 s out from when Breathe began. The halo and Tick's breath are one number that the render server animates from turn to turn (`BreathFollower`), so the app itself wakes only at the turns, for the words on the dial and a soft tap. Still, they hold at half.
- **The dial's words:** `BreakGuide` gives the label ("Breathe in", "Neck roll"), the dots and the VoiceOver value, and the moments they change, so the dial redraws only then.
- **Break's over:** after a break runs out, `TickDirector` keeps Tick ready (even at night) for the ten minutes "Break's over" shows, and its entrance is a quick reach up and a yawn (`StretchMove.backToWork`), seen only if the change happened on screen.
- **Live Activity, island, widget, bedside:** unchanged. They can't follow breaths or stretches without push updates (the same limit as the workout), and the bedside clock always rests.

## Waiting, watching and catching

- **Fidgets.** Ready and idle, Tick fidgets on its own beat (`FidgetSchedule` in `Shared/Mascot/TickFidget.swift`): it taps or polishes its crown, checks the dial, stretches, looks round, and from 20:00 yawns. Each Tick's seed sets the order and the 8–20 s gaps between them, never the same kind twice in a row, so it doesn't read as a loop. Frames are drawn only during a fidget, the same as a blink. Never during focus, asleep or hello; dozing after ten minutes still comes from `TickDirector`.
- **Watching.** While the knob is dragged Tick's eyes follow it round the dial (`TickAttention`, with the face's new `gazeY`), and the brow goes up at 5 and 60. While a name is typed it glances at the field and nods when the name finds its symbol. The face springs there and back, so this only draws while it moves; Reduce Motion and Low Power Mode keep Tick still. (With the keyboard up, today's iPhones shrink the dial below the size where Tick shows, so the glance and nod are mostly unseen there.)
- **Catching.** A parked thought flies to Tick as a slip of paper (`ParkedSlip`, an Animatable curve), and Tick reaches up, catches it and tucks it away (`TickCatch`, 0.9 s of frames). Mid-combo it just nods so the round isn't broken. With Reduce Motion or Low Power Mode the slip fades where it is and Tick stays still.
- **Headphones.** In Calm and Off, Tick wears its headphones only while a focus sound plays; the workout always has them.

## Where Tick can move

| Surface | Tick | Not possible |
|---|---|---|
| App | Everything: springs, entrances, idle loops, the workout, touch, the live ring | – |
| Lock Screen, expanded island, StandBy | A still face in a live system ring (`ProgressView(timerInterval:)`); a new pose fades in when the activity updates | Loops, keyframes, touch on Tick, the workout's tiring face (see below) |
| Compact and minimal island | The still face in the live ring | Animation, touch other than opening the app |
| Home Screen widget | A still pose for each timeline entry, with the ring as of that entry | Animation |
| Alarm (AlarmKit) | The still ringing Tick, plus the system's Stop and Start-break buttons | Shake, flashing lines |

**Why the Lock Screen and island can't tire:** a Live Activity redraws only when the app updates it, or once at its stale date. That stale date is already the end of the session: it's what turns the card to done at 0:00. Moving it 5 minutes earlier would give the tired face but leave it there at the end, the app has no way to wake itself at a given minute, and updating only when the app happens to be open would be inconsistent. So the glyph stays as it is, with its live ring.

## What it costs

- Frames run at 30 a second only during a blink, a breath, a tap, a hop or an entrance, and at 15 a second for the slow steam and z's. Between them nothing is drawn.
- Breathing comes in short spells, two breaths about every 16 s, because breathing all the time kept the screen drawing for whole sessions.
- Drawing, breathing and shaking: the figure is drawn once into a layer, and breathing and the alarm's shake move that layer without redrawing the parts.
- Paused: in the background, off screen, in Low Power Mode and with Reduce Motion (which also turns state changes into cross-fades).
- The workout draws at 30 frames a second during combos, the bounces between them and blinks, at 15 when only breathing, and not at all while standing still between rounds. Breathing never stops once tired, so the last 5 minutes draw throughout, at 15 a second. The combo plan and the sweat are worked out once per session, not per frame.

**Simulator (iPhone 17, iOS 27), app CPU averaged over 30 s with `top`:**

| Screen | Still Tick | Living Tick |
|---|---|---|
| Focus, idle | 0% | about 6% |
| Focus, running | about 27% | about 26% |
| App in the background | 0% | 0% |

The running screen's cost is its countdown; Tick adds nothing measurable there. The simulator draws in software, so a phone uses far less.

**The workout (same simulator, Focus running, 20 s averages):**

| Mascot during focus | App CPU |
|---|---|
| Off (the plain working pose) | about 28% |
| Workout, warm-up and strong | 30–32% |
| Workout, tired (breathing throughout) | 31–33% |

So the workout adds 2–5 points in the simulator.

**Breaks (same simulator, a 5-minute break, 30 s averages after settling):**

| During breaks | App CPU |
|---|---|
| Rest (the mug's steam, 15 frames a second throughout) | about 29% |
| Stretch (frames only while a stretch moves; holds, gaps and eye rest draw nothing) | about 28% |
| Breathe (the app wakes at each turn; the render server moves the halo and Tick) | about 25% |

So stretching and breathing cost no more than resting.

**Focus sounds (same simulator, Rain, 25-minute session):** the loops are decoded into memory once and summed by one `AVAudioSourceNode` with a 0.1 s buffer; the fade is worked out per buffer, so there are no timers. With the app in the background and the sound playing, the app sat at about 0.5% CPU, and sampling it showed only the audio thread at work: no Core Animation commits, no SwiftUI. That took one fix: background audio keeps the app running, and its countdown `TimelineView`s kept drawing (about 30% CPU) until `LiveTimeline` paused them while the scene is in the background. Battery on a real phone over a 50-minute session with the screen off is still to be measured (see below).

**Idle with fidgets:** about 5% averaged over 30 s in the simulator, close to the old fixed crown tap's 6%; between fidgets nothing is drawn.

**Sounds and paper:** the timer's sounds are system sounds (`SystemTimerSounds`): loaded once, no audio session, nothing running between them. The paper grain is a Metal `colorEffect` (`Clockin/Design/PaperGrain.metal`) with no time input, so it's drawn with the page and never on its own; the dial's Bakelite shine is one static stroke on its track. The widget and Live Activity keep plain paper: they're drawn by the system from an archived view, often tinted or clear, where a grain would be flattened or lost.

## Checking on a phone

1. **Instruments, SwiftUI template:** during a focus session, body updates should come only from the dial's once-a-second step, plus Tick's blinks.
2. **Animation Hitches:** step through every state in the gallery (debug builds, ladybug menu › Tick gallery). Hitches should stay under 1%.
3. **Time Profiler:** no main-thread work over 1 ms per frame while Tick moves.
4. **Power Profiler:** compare a 50-minute focus session with the app open against the M8 build. Aim for under 5% more energy.

**For the workout** (Mascot during focus on Workout, then Off, to compare):

1. **SwiftUI:** `TickView` body updates stay at or under its frame rate during combos, and `FocusView` and `DialFace` don't update for Tick.
2. **Animation Hitches:** under 1% through a session; the gallery's workout simulator at 10× runs through every phase quickly.
3. **Time Profiler:** under 2 ms of main-thread work per frame during combos.
4. **Power Profiler:** a 50-minute session with the screen on, Workout against Off. Aim for under 10% more energy; if it's over, longer rests between rounds come first.

**For breaks** (a 5-minute break in each style, Rest to compare):

1. **SwiftUI:** while breathing, `DialFace` and `TickView` update only at the turns and blinks; while stretching, `TickView` updates at 30 a second or less during a stretch and not at all in holds; `FocusView` doesn't update for either.
2. **Animation Hitches:** under 1% across each style, including switching chips mid-break.
3. **Time Profiler:** under 2 ms of main-thread work per frame while stretching, and almost none between breaths.
4. **Power Profiler:** each style against Rest, screen on. Aim for under 10% more energy than Rest; if the breathing halo keeps the display at a high refresh rate, move it to a 15-frame timeline.

**For the paper:** the SwiftUI template shows no `PaperBackground` updates during a running countdown, Time Profiler shows no shader work once a screen has appeared, and History scrolls with under 1% hitches.

**For focus sounds** (Rain, a 50-minute session, screen off):

1. **Energy Log or Power Profiler:** the same session with and without a sound. The difference should be the audio hardware alone.
2. **`top -l N -pid` while locked:** near 0% CPU apart from the audio thread.
3. **Core Animation:** no commits while the phone is locked.
4. **By ear:** with the Silent switch on and off, with Music playing (with and without "Mix with other audio"), through a call and Siri, unplugging headphones, and up to the notification chime and the alarm, which should always ring into silence.

**For the catch and fidgets:** Animation Hitches under 1% through a catch, a knob drag and each fidget.
