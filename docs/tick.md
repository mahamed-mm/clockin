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

## Where Tick can move

| Surface | Tick | Not possible |
|---|---|---|
| App | Everything: springs, entrances, idle loops, touch, the live ring | – |
| Lock Screen, expanded island, StandBy | A still face in a live system ring (`ProgressView(timerInterval:)`); a new pose fades in when the activity updates | Loops, keyframes, touch on Tick |
| Compact and minimal island | The still face in the live ring | Animation, touch other than opening the app |
| Home Screen widget | A still pose for each timeline entry, with the ring as of that entry | Animation |
| Alarm (AlarmKit) | The still ringing Tick, plus the system's Stop and Start-break buttons | Shake, flashing lines |

## What it costs

- Frames run at 30 a second only during a blink, a breath, a tap, a hop or an entrance, and at 15 a second for the slow steam and z's. Between them nothing is drawn.
- Breathing comes in short spells, two breaths about every 16 s, because breathing all the time kept the screen drawing for whole sessions.
- Drawing, breathing and shaking: the figure is drawn once into a layer, and breathing and the alarm's shake move that layer without redrawing the parts.
- Paused: in the background, off screen, in Low Power Mode and with Reduce Motion (which also turns state changes into cross-fades).

**Simulator (iPhone 17, iOS 27), app CPU averaged over 30 s with `top`:**

| Screen | Still Tick | Living Tick |
|---|---|---|
| Focus, idle | 0% | about 6% |
| Focus, running | about 27% | about 26% |
| App in the background | 0% | 0% |

The running screen's cost is its countdown; Tick adds nothing measurable there. The simulator draws in software, so a phone uses far less.

## Checking on a phone

1. **Instruments, SwiftUI template:** during a focus session, body updates should come only from the dial's once-a-second step, plus Tick's blinks.
2. **Animation Hitches:** step through every state in the gallery (debug builds, ladybug menu › Tick gallery). Hitches should stay under 1%.
3. **Time Profiler:** no main-thread work over 1 ms per frame while Tick moves.
4. **Power Profiler:** compare a 50-minute focus session with the app open against the M8 build. Aim for under 5% more energy.
