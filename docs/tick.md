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
