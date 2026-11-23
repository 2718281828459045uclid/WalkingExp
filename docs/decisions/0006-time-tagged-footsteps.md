# 0006. Footsteps as time-tagged OSC bundles on a simulated clock

Status: accepted, 2026-11-22 (Lesson 05).

## Context

Decision 0003 separates continuous state (sampled, rate-limited) from events (sent once, on occurrence). Footsteps are the first events whose timing the ear judges: at 4 steps per second, an unevenness of 10 ms is audible as a limp. Lesson 04 O5 measured that messages sent from physics ticks arrive in sclang with intervals scattered by several milliseconds, because Godot runs physics ticks at the start of render frames, not at evenly spaced times.

The capsule has no legs, so there are no foot contacts to detect.

## Decision

1. **Footsteps come from a gait clock.** `GaitClock` (`game/src/audio/gait_clock.gd`) advances a phase by distance walked on the floor divided by `step_length` (0.75 m). A strike happens when the phase passes a whole number; the strike's position inside the tick is found by inverse linear interpolation. A landing after air is a strike of both feet. Lesson 12 replaces the invented contacts with foot contacts from the leg solver; the message stays.
2. **Strike times use a simulated clock.** `FootstepReporter` stamps each strike with `anchor + n·Δt − (1 − f)·Δt`: Unix time at the first tick plus the simulated time. The anchor moves back when the simulated clock runs ahead of the wall clock, and is reset when the simulation falls more than 0.25 s behind.
3. **Events travel as OSC bundles** whose NTP time tag is the strike time plus `latency_seconds` (default 0.05 s). `OscBundle` (`game/src/audio/osc_bundle.gd`) builds them; `OscSender.send_bundle()` sends them. sclang passes the tag to the OSCdef as `time`; the responder forwards it to scsynth with `s.makeBundle(time − now, ...)`.
4. **The surface is classified on the CPU** by `SurfaceClassifier` (`game/src/audio/surface_classifier.gd`), which reads the rule parameters and the noise texture from `painted_terrain_material.tres`. The message carries three weights (grass, dirt, rock), not a name.
5. **Address:**

| Address | Types | Arguments | When |
|---|---|---|---|
| `/foot/step` | `ifffff` | foot (0 left, 1 right, 2 both), impact (m/s), slope along travel (degrees, + uphill), grass, dirt, rock (sum 1) | at each strike, in a bundle (or as a plain message with timing IMMEDIATE) |

## Consequences

- Godot and sclang must read the same system clock. Both run on one machine here; a second machine would need clock synchronization (Lesson 05 exercise E6).
- Every step sounds `latency_seconds` after the strike. Measured (Lesson 05 O3): strike-to-arrival delay between 5 and 32 ms; with 50 ms no step arrived late, with 25 ms 6 of 30, with 10 ms 28 of 30.
- An OSC tag of "immediately" (0, 1) reaches the sclang 3.13.0 OSCdef as a meaningless large time (about 2.9 × 10⁸ s); the responder treats a delta above 1 s as "now".
- Rule changes in the material change both the paint and the footsteps. A second copy of the rules lives in the classifier; `tests/test_05_surface.gd` checks it against the shader's formulas, not against rendered pixels.
- `get_floor_normal()` is the normal of the collision triangle, while the shader uses interpolated vertex normals. On the sandbox hill they differed by up to 5.7° on one walk; near a rule threshold the sound and the paint can disagree.
