# Lesson 05. Footsteps as events

Lesson scene: `game/scenes/lessons/05_footsteps.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–04 are unchanged; the Lesson 04 scene sends no footsteps.

## 1. Orientation

Lesson 04 sent the player's state as a continuous stream: 30 samples per second, whether or not anything changed. A footstep is a different kind of message. It happens once, at a moment, and the ear judges that moment: four steps per second with one step 15 ms early sounds like a limp. This lesson builds the event path of decision 0003 and answers five questions:

1. The capsule has no legs. Where do footsteps come from? (gait phase)
2. What did the foot land on? The shader knows, the CPU does not. (surface classification)
3. When exactly did the foot land, between two physics ticks? (inverse interpolation)
4. How can SuperCollider play a step at the right moment when packets arrive with a scatter of several milliseconds? (OSC bundles, NTP time tags, latency compensation)
5. What should a step on grass, dirt, and rock sound like, and how does impact speed and slope change it? (synthesis after Farnell and van den Doel)

Goal served (`plan.md`): "diegetic audio using physical simulation and synthesis to create natural sounds, both of the ambience and the player interacting with the environment."

Files:

| File | Role |
|---|---|
| `game/src/audio/osc_bundle.gd` | `OscBundle`: static functions for NTP time tags and the `#bundle` format. |
| `game/src/audio/osc_sender.gd` | Lesson 05 adds `send_bundle()` and the counter `bundles_sent` at the end of the file. The Lesson 04 part is unchanged. |
| `game/src/audio/gait_clock.gd` | `GaitClock`: distance walked → foot strikes, with the strike's position inside the tick. |
| `game/src/audio/surface_classifier.gd` | `SurfaceClassifier`: the paint rules of `terrain_painted.gdshader`, repeated on the CPU. |
| `game/src/audio/footstep_reporter.gd` | `FootstepReporter` (Node): runs the gait clock, classifies the ground, stamps the strike time, sends `/foot/step`. |
| `game/src/lessons/footsteps.gd` | Scene root. Extends `osc_bridge.gd` (Lesson 04); adds the K key and HUD lines. |
| `game/scenes/lessons/05_footsteps.tscn` | The Lesson 04 scene plus a `Footsteps` node. |
| `game/project.godot` | Input action `toggle_step_timing` (K, gamepad B); `run/main_scene`. |
| `audio/supercollider/05_footsteps.scd` | Three footstep SynthDefs; an OSCdef that plays each step at its time tag; a timing report. |
| `tools/footstep_timing.sh`, `tools/sc/footstep_timing_listener.scd`, `tools/godot/walk_steps.gd` | Timing measurement: Godot walks, sclang records arrival times and time tags. |
| `tools/footsteps_nrt.sh`, `tools/sc/footsteps_nrt.scd` | Offline render of the SynthDefs to a WAV file, with a peak, RMS, and NaN check per step. |
| `game/tests/test_05_*.gd` | Bundle bytes, gait clock timing, classifier rules, scene test. |
| `docs/decisions/0006-time-tagged-footsteps.md` | Why a gait clock, a simulated clock, bundles, and weights. |

Reading: OSC 1.0 specification, sections "OSC Bundles" and "Temporal Semantics and OSC Time Tags". RFC 5905 section 6, the 64-bit NTP timestamp (two pages). Andy Farnell, *Designing Sound*, the footsteps chapter. Van den Doel, Kry, Pai, "FoleyAutomatic" (SIGGRAPH 2001), sections 1–3 on modal synthesis. SuperCollider help: `Server` (`makeBundle`), `Klank`, `Dust2`, `Score` (`recordNRT`). Full entries: `docs/references.md`. The geometry here (normals, directional derivatives) is that of Lessons 01–02; there is no new DDG reading.

Before this lesson, run `audio/supercollider/04_player_state.scd` once more and recall Lesson 04 O5: the arrival intervals of a 30 Hz stream scattered between about 26 and 39 ms.

## 2. Predict

Work these on paper before reading the code.

- **P1.** An OSC bundle starts with the string `#bundle`, then an 8-byte time tag, then for each element a 4-byte size followed by the element's bytes. Write every byte of a bundle with the tag "immediately" (seconds 0, fraction 1) that holds the message `/a` with no arguments (Lesson 04 P2). How many bytes is a bundle holding one `/foot/step` message with one int and five floats?
- **P2.** An NTP time tag counts seconds from 1 January 1900; Unix time counts from 1 January 1970. Compute the difference in seconds (count the leap years between 1900 and 1969; 1900 itself is not a leap year). Then write the 8 bytes of the tag for Unix time 1.5 s.
- **P3.** Godot returns the Unix time as a 64-bit float, about 1.8 × 10⁹ s in 2026. A double has 53 significant bits. What is the spacing between neighboring representable times near 1.8 × 10⁹? What would it be in a 32-bit float (24 significant bits)? Which one can describe a footstep's time?
- **P4.** The capsule walks at 3 m/s; one step covers 0.75 m. How many steps per second? With 60 physics ticks per second, by how much does the gait phase (in steps) grow per tick? In one tick the phase goes from 0.95 to 1.0167. At what fraction f of the tick did it pass 1? At what time, if the tick ended at t = 2.000 s?
- **P5.** The ground is a plane rising 30° toward −z. Its unit normal is (0, cos 30°, sin 30°). The player walks toward −z. Using n ∝ (−h_x, 1, −h_z) (Lesson 01) and the directional derivative (Lesson 02), find the rise per meter walked, and the angle. Walking toward +x?
- **P6.** The shader mixes `ground = mix(grass, dirt, d)` and then `mix(ground, rock, r)`. Expand into three weights. For r = 0.5 and d = 0.25, what are the weights of grass, dirt, and rock?
- **P7.** Steps arrive in sclang between 5 and 32 ms after the moment they happened. SuperCollider plays each step at "strike time + L". Which L avoids late steps? What does the player hear and see when L = 50 ms? When L = 200 ms? (Television engineers found that viewers notice sound running ahead of the picture by about 45 ms and behind it by about 125 ms; ITU-R BT.1359.)

## 3. Read

### 3.1 `osc_bundle.gd`

Read the layout diagram in the header comment. `timetag_bytes()` writes two unsigned 32-bit integers, not one 64-bit integer. The Q/A comment gives the reason; check it against P2's number: what is (2208988800 + 1.8 × 10⁹) × 2³², and how does it compare with 2⁶³? The second Q/A comment answers P3.

`encode_bundle()` takes messages that `OscEncoder.encode_message()` (Lesson 04) already built. A bundle may also hold bundles; this encoder does not nest. Why does each element carry its size, when a message already ends with known padding? (Hint: a reader that does not know the type tags of a message still has to skip it.)

### 3.2 `send_bundle()` in `osc_sender.gd`

The new function sits after `send()`. It counts the bundle in `bundles_sent`, its messages in `messages_sent`, and the packet's bytes in `bytes_sent`. The Lesson 04 HUD therefore keeps counting messages and bytes when footsteps travel as bundles.

### 3.3 `gait_clock.gd`

The header diagram shows the idea: the phase counts steps walked, and each whole number is a foot strike. `advance()` contains the two Q/A comments that matter. The first detects that a whole number was crossed by comparing integer parts. The second finds where, inside the tick, the crossing happened: it solves before + f · (after − before) = boundary, which is P4. This is the inverse of `lerp`: given the endpoints and a value between them, find the parameter.

Why does the clock report a fraction rather than a time? (What does the clock know about the length of a tick?)

### 3.4 `surface_classifier.gd`

Lesson 03 R3 asked what CPU code needs to know which surface lies under a point. This class is that answer. Compare `rockiness()` and `dirtiness()` line by line with `fragment()` in `game/shaders/terrain_painted.gdshader`: same smoothstep, same noise shift `noise − 0.5`, same factor 2 · breakup. `read_material()` copies the numbers from the material, so the material file is the single source of the rule parameters.

`surface_weights()` holds P6's expansion. `noise_at()` repeats the shader's triplanar sampling with `PaintMath.triplanar_weights()` (Lesson 03). `sample_bilinear()` repeats what `texture()` does on the GPU at the finest mip level; the Q/A comment explains the half-texel offset. Which part of the GPU's work does the CPU version skip, and when would that matter? (Hint: Lesson 03 §3 on mipmaps.)

`read_material()` may find no image yet. Read the Q/A comment, then find where `test_05_surface.gd` waits for the image.

### 3.5 `footstep_reporter.gd`

Read the header: the list of files and what each controls, the message layout, and the two timing modes. Then `_physics_process()`:

1. `_advance_clock()` returns the time at the end of this tick. Read its three Q/A comments before going on. The clock is `anchor + n · Δt`, not the wall clock. The anchor moves when the simulated clock runs ahead of the wall clock, and resets when it falls far behind.
2. A landing (air → floor) is a strike of both feet with the falling speed of the previous tick as impact.
3. On the floor, the distance moved this tick advances the gait clock. On a strike, the strike time is `tick_end − (1 − f) · Δt`.

`_emit()` gathers the rest. The feet are `foot_offset` (0.9 m, half the capsule height) below the center. The normal is `get_floor_normal()`: the collision triangle under the capsule. `signed_slope_degrees()` holds P5; its Q/A comment derives it from the graph normal. With timing TIMETAGGED the message goes into a bundle tagged `strike time + latency_seconds`; with IMMEDIATE it goes out as in Lesson 04.

Why does the node run after `Player` in the same physics tick? (Godot calls `_physics_process()` in tree order; find the order in the `.tscn`.)

### 3.6 `05_footsteps.scd`

**Block 1** defines the SynthDefs. `footEnvelopes` is an ordinary sclang function called inside each SynthDef function while the SynthDef is built; it returns two envelope UGens. Read its Q/A comment: Farnell's footstep has a heel phase and a ball phase, and the roll between them shortens as the walk speeds up. The slope shifts weight between heel and ball. Then the three surfaces:

| SynthDef | Model | Varies with impact | Varies with slope |
|---|---|---|---|
| `\stepGrass` | dense band-passed clicks (`Dust2` → `BPF`) and high-passed noise | click density, level | heel/ball balance |
| `\stepDirt` | low-passed noise thump and sparse grit | cutoff, grit density, level | heel/ball balance |
| `\stepRock` | noise exciting five resonant modes (`Klank`) | mode pitch (±10 %), level | heel/ball balance |

`\stepRock` is modal synthesis in the sense of van den Doel, Kry, and Pai: a struck object rings at a set of frequencies, each with its own amplitude and decay. Five inharmonic modes stand in for an irregular stone.

**Block 2** is the responder. Read the two Q/A comments. The OSCdef's `time` argument is the bundle's time tag, already converted by sclang to its own clock. `time − thisThread.seconds` is the margin: how far in the future the step should sound. `s.makeBundle(margin, { ... })` sends the `Synth` messages to scsynth as a bundle tagged "now + margin", and scsynth starts the synths on that sample. Each surface with weight above 0.02 gets its own synth, scaled by its weight. Note the line that treats a margin above 1 s as "now", and the reason in the comment above it.

**Block 3** prints how many steps arrived late. **Block 4** removes the responder.

### 3.7 The tools

`tools/footstep_timing.sh` runs the same arrangement as Lesson 04's round trip: a background sclang (`footstep_timing_listener.scd`) and a Godot script (`walk_steps.gd`) that runs the lesson scene and holds "move forward". The listener records, for each `/foot/step` that is not a landing, the arrival time and the tag. It prints the intervals between arrivals, the intervals between tags, their difference (the jitter), and the margin.

`tools/footsteps_nrt.sh` takes block 1 of `05_footsteps.scd` by the block convention of `tools/sc/check_syntax.scd`, runs it, and renders 27 steps with scsynth in non-real-time mode: nothing reaches the speakers. It reads the file back and reports peak and RMS per step.

## 4. Run and observe

Start SuperCollider, boot the server (`s.boot`), run block 1, then block 2 of `05_footsteps.scd`. Start the lesson scene (F6). The spawn point lies on low ground at the foot of the central hill; the camera faces the hill. **K** (gamepad B) toggles the timing between time-tagged and immediate.

- **O1.** Walk straight up the hill from the spawn and listen. In what order do the surfaces change? Read the HUD's `grass dirt rock` line at each change. Is the change sudden or a blend?
- **O2.** Walk slowly with a half-deflected stick, then fast. What changes in the sound? Walk up the steepest line of the hill, then down it. What changes?
- **O3.** In a terminal, run `tools/footstep_timing.sh 8 tagged 50`. Read the `ARRIVAL`, `TAG`, and `JITTER` lines. Which spread is larger, and by how much? Read `MARGIN`: compare its mean with the 50 ms latency. What is the delay from strike to arrival? Repeat with `25` and `10` instead of `50` and read `LATE`. Then add `--window` to one run.
- **O4.** In the game, walk on flat ground at full speed and toggle K a few times. Can you hear the difference between immediate and time-tagged steps? Try with a rock surface (the steep flanks), where the attack is sharpest.
- **O5.** Run block 3 after a walk. Compare the margins sclang reports with the latency on the HUD. Then quit Godot, change `latency_seconds` on the `Footsteps` node to 0.01, run again, walk, and run block 3.
- **O6.** Read the HUD's `clock lag` while walking, and right after the scene loads. What is the largest value you see? Then drag the Godot window or open a menu (on macOS, holding a window's title bar pauses frames). Does `resets` increase?
- **O7.** Run `tools/footsteps_nrt.sh ~/Desktop/steps.wav` and open the file in an editor that shows a waveform (Audacity, or `SoundFile` and `plot` in SuperCollider). The 27 steps follow in the order grass, dirt, rock; within each, impact 0.5, 1.5, 3.0 m/s; within each, slope −25°, 0°, +25°. Compare the heel and ball peaks at −25° and +25°.
- **O8.** Walk across the hilltop (the flat summit) and watch the `rock` weight. The ground looks flat. Why does the HUD report rock there? Press Tab twice (slope view) and look again.

## 5. Tweak

Restore each change after the observation.

- **T1.** In the `Footsteps` node, set **Step Length** to 1.5. Predict the number of steps per second at full speed. Is the sound plausible for a human? What would a stride length depend on in a real walker?
- **T2.** In `gait_clock.gd`, replace the computed `strike_fraction` with `1.0` (stamp every strike at the end of its tick). At 60 Hz and 3 m/s on flat ground, how large is the timing error? At 30 Hz (`T` key)? Find the tick rates and speeds where the error is zero.
- **T3.** In `footstep_reporter.gd`, comment out the branch `if clock_lag < 0.0:` (keep the `elif` as `if`). Run `tools/footstep_timing.sh 8 tagged 50` and read `MARGIN`. Where did the extra delay come from?
- **T4.** In the Inspector of `data/terrain/painted_terrain_material.tres`, set **Rock Angle Start** to 12 and **Rock Angle End** to 18. Run the scene. Do the paint and the footsteps still agree? Which file holds the numbers the classifier uses?
- **T5.** In block 2 of `05_footsteps.scd`, change `s.makeBundle(delta.max(0), {` to `s.makeBundle(nil, {` and run the block again. Every step now plays on arrival, even in time-tagged mode. Listen as in O4.
- **T6.** In `\stepRock`, multiply the decay times in the `Klank` specification by 5. What material does the step sound like now? Then divide the frequencies by 3.

## 6. Exercises

- **E1 ★ Stopping.** When the player stops, the gait clock keeps its phase, and the next walk starts mid-step. Real walkers bring the trailing foot next to the leading one when they stop. Detect the stop (speed below a threshold for some ticks) and emit one quiet "settle" step if the phase is more than a chosen fraction past the last strike; reset the phase. Test it in your own SceneTree script.
- **E2 ★ Stride from speed.** Human step length grows with speed. Make `step_length` a function of horizontal speed (a `Curve` Resource assigned in the scene, following decision 0004). Choose the curve so the cadence at 3 m/s and at 1 m/s matches a value you measure by walking with a metronome.
- **E3 ★★ Hearing jitter.** Write a SuperCollider patch that plays a 4 Hz click train twice: once on a perfect grid, once with each click displaced by a Gaussian error of standard deviation σ. Find the smallest σ at which you can tell the two apart in an ABX test of 20 trials. Compare with the jitter measured in O3.
- **E4 ★★ Paint and sound agree?** Measure how often the classifier and the rendered image disagree. In a windowed run, render the terrain from above in `paint_view` 0 with lighting removed, read the pixel color at many points, unmix it into grass, dirt, and rock weights, and compare with `weights_at()`. Report the disagreement as a function of slope. Which of the limits in decision 0006 dominates?
- **E5 ★★ Gravel.** Dirt in Joshua Tree is decomposed granite: grit, not soil. Write `\stepGravel` as a particle model after Cook's PhISEM (each grain a short decaying resonance, the number of grains per heel and ball following impact). Add a fourth weight to the classifier for a band of heights or noise values of your choice, and extend `/foot/step` at the end of its arguments.
- **E6 ★★★ Two machines.** Time tags assume both programs read the same clock. Run SuperCollider on a second computer. Build Lesson 04 E5's return channel if you have not, then estimate the clock offset between the machines with an NTP-style exchange of four timestamps (RFC 5905 §8) and correct the tags. Report the offset, its scatter, and the margin before and after the correction.

## 7. Reflect

- **R1.** Lesson 04 R1 asked whether a lost packet or a late packet costs more for a footstep. Now that steps carry time tags, what does a packet that arrives 100 ms late do in block 2? What does a lost one do? Which of the two would you prevent first, and how?
- **R2.** The latency L delays every step. Lessons 12–13 move the feet with IK; the foot will visibly touch the ground at a known time. Where else could that delay go so that sound and picture meet? (Consider audio output buffers, the render pipeline's frame delay, and P7's thresholds.)
- **R3.** The gait clock invents strikes from distance. Lesson 12 will detect real foot contacts from the leg solver. Which parts of `FootstepReporter` survive that change, and which are replaced? What should the message look like so SuperCollider needs no change?
- **R4.** The classifier is a second copy of the shader's rules. Name two other ways to give CPU code the same answer (consider reading back a rendered image, or generating both the shader code and the GDScript from one description). What does each cost?
- **R5.** `/foot/step` sends three weights. Lesson 07 adds boulders made of signed distance fields, and Lesson 21 adds water. How should the message grow: more weights, a material id, or a separate address per material family? Consider the receiver that joins late (Lesson 04 O3) and the SynthDefs that must exist for each.

## 8. Answers

<details><summary>P1</summary>

```
23 62 75 6e 64 6c 65 00   "#bundle" + 0
00 00 00 00 00 00 00 01   time tag "immediately"
00 00 00 08               element size: 8
2f 61 00 00 2c 00 00 00   "/a", ","
```

28 bytes; `test_05_osc_bundle.gd` checks them. `/foot/step` takes 12 bytes, `,ifffff` 8, six arguments 24: a 44-byte message. The bundle is 8 + 8 + 4 + 44 = 64 bytes (the loopback test checks 64).
</details>

<details><summary>P2</summary>

From 1900 to 1969 there are 70 years. Leap years: 1904, 1908, …, 1968, that is 17. (70 · 365 + 17) · 86400 = 25567 · 86400 = 2 208 988 800 s (`OscBundle.NTP_UNIX_OFFSET`). Unix 1.5 s: seconds 2 208 988 801 = `83 aa 7e 81`, fraction 0.5 · 2³² = 2³¹ = `80 00 00 00`.
</details>

<details><summary>P3</summary>

1.8 × 10⁹ lies between 2³⁰ and 2³¹, so the spacing of doubles there is 2³⁰ · 2⁻⁵² = 2⁻²² s ≈ 0.24 µs. A 32-bit float has 2³⁰ · 2⁻²³ = 128 s spacing: it cannot tell two minutes apart. Godot's `float` is 64-bit, `Vector3` components are 32-bit (CLAUDE.md); a time stored in a `Vector3` would be useless. The test round-trips a 2026 time through the tag within 1 µs.
</details>

<details><summary>P4</summary>

3 / 0.75 = 4 steps per second, 250 ms apart. Per tick at 60 Hz: 3 · (1/60) / 0.75 = 1/15 ≈ 0.0667 steps. f = (1 − 0.95) / (1.0167 − 0.95) = 0.05 / 0.0667 = 0.75. Strike time = 2.000 − (1 − 0.75) / 60 = 1.99583 s. `test_05_gait_clock.gd` rebuilds 40 strike times this way at 30, 60, and 144 Hz and finds each within 10⁻⁹ s of a multiple of 0.25 s.
</details>

<details><summary>P5</summary>

From n ∝ (−h_x, 1, −h_z): h_x = −n.x / n.y = 0 and h_z = −n.z / n.y = −tan 30°. Walking toward −z, d = (0, −1) in (x, z): D_d h = h_z · (−1) = tan 30° ≈ 0.577 m per meter, an angle of +30°. Toward +x: D_d h = h_x = 0, so 0°. The test checks +30, −30 (toward +z), and 0.
</details>

<details><summary>P6</summary>

final = (1 − r)(1 − d) grass + (1 − r) d dirt + r rock. For r = 0.5, d = 0.25: grass 0.375, dirt 0.125, rock 0.5. The weights sum to 1 for any r and d in [0, 1].
</details>

<details><summary>P7</summary>

L must exceed the largest delay: here more than 32 ms. With L = 50 ms the step sounds 50 ms after the strike (plus the audio device's output buffer), sound behind picture, below the 125 ms threshold for sound running late. With L = 200 ms no step is late, but the sound trails the picture visibly, and Lesson 12's feet will touch the ground a fifth of a second before they are heard. O3 measures the delays; decision 0006 records the choice of 50 ms.
</details>

<details><summary>O1</summary>

Measured on a headless walk of 16 s straight from the spawn (63 steps): the landing and the first steps report dirt (feet at 0.6–1.0 m, below `dirt_height` 1 m + blend). Between 1.9 and 3 m of height the dirt weight falls and grass rises. On the flank (slopes 15–23°) the rock weight moves between 0 and 0.82 from step to step, as the noise shifts the threshold. Above about 9 m the steps are grass, with one more rock patch at the summit. The changes are blends: the weights pass through mixtures such as grass 0.31, dirt 0.17, rock 0.53.
</details>

<details><summary>O2</summary>

Impact is the horizontal speed: a slower walk gives quieter steps, fewer grass snaps, a darker dirt thump, and a slightly lower rock pitch; the roll between heel and ball lengthens from 55 ms (3 m/s) to 92 ms (0.5 m/s). Uphill the ball of the foot is louder; downhill the heel. On the measured walk the slope along the path reached +23°.
</details>

<details><summary>O3</summary>

Measured, 8 s walk up the hill, 30 steps (landing excluded):

| Run | Arrival interval sd | Tag interval sd | Jitter (arrival − tag interval) | Margin mean (min) | Late |
|---|---|---|---|---|---|
| headless, L = 50 ms | 7.5 ms | 3.5 ms | sd 7.1 ms, −16 to +11 ms | 32.4 ms (22.1) | 0 |
| windowed, L = 50 ms | 8.1 ms | 3.4 ms | sd 7.9 ms, −19 to +11 ms | 33.3 ms (22.0) | 0 |
| headless, L = 25 ms | 9.1 ms | 3.4 ms | sd 8.7 ms | 5.1 ms (−5.5) | 6 |
| headless, L = 10 ms | 8.0 ms | 3.5 ms | sd 8.0 ms | −9.3 ms (−21.5) | 28 |

The tag intervals vary only with the walk itself (the speed-up from rest and the slope: the gait clock counts distance along the ground, so at 17° a step takes 250 / cos 17° ≈ 261 ms; the mean interval was 262 ms). The arrival intervals add about 7–8 ms standard deviation and single errors up to 19 ms. The delay from strike to arrival is L − margin: 17–20 ms on average per run, between 5 and 32 ms over all four runs. In immediate mode the listener's `time` equals the arrival time within 2.3 ms, so its `LATE` count means nothing there.
</details>

<details><summary>O4</summary>

The measured jitter is a standard deviation of 7–8 ms with single errors up to 19 ms (O3). Whether that is audible depends on the listener and on the attack: the rock step has the sharpest onset and the grass step the softest. This lesson does not measure a listening threshold; exercise E3 measures yours.
</details>

<details><summary>O5</summary>

With L = 50 ms the margins lie between about 22 and 45 ms. With L = 10 ms nearly every margin is negative: in the measured run 28 of 30 steps (headless) and 30 of 30 (windowed) arrived after their time. Block 2 plays a late step at once, so it falls back to immediate behavior.
</details>

<details><summary>O6</summary>

Headless, the lag stayed between 0 and 17.6 ms over a 16 s walk; the windowed render check showed 26 ms shortly after load. The lag combines the frame loop (ticks run at the start of a frame) and catch-up ticks. A pause longer than `max_clock_drift` (0.25 s) resets the anchor and increases `resets` by one.
</details>

<details><summary>O7</summary>

One render (48 kHz, float WAV): all 27 steps audible, no NaN or infinite samples, peaks between −21 and −4 dBFS. Grass at 0.5 m/s: −20 to −13 dBFS; at 3 m/s: −9 to −4. The noise sources are random, so peaks change by a few dB between renders. Peaks of the heel phase (before the roll time) against the ball phase, linear: grass at 1.5 m/s 0.30 / 0.09 at −25°, 0.13 / 0.22 at 0°, 0.08 / 0.35 at +25°; rock at 3 m/s 0.23 / 0.05 at −25° and 0.05 / 0.33 at +25°. Downhill the heel dominates, uphill the ball, on all three surfaces. `tools/footsteps_nrt.sh` fails if a step is silent (below −60 dBFS), clips, or contains NaN.
</details>

<details><summary>O8</summary>

The summit is flat along the walk (slope +0.4° along the path) but the sandbox ripples run across it: the full slope of the floor normal was 22.1° at that step, and a noise value of 0.84 adds 5.4°. Rockiness uses the full slope, not the slope along the path. The slope view (Tab) shows the ripples. On the same walk the floor normal and the analytic normal of the height field differed by up to 5.7° (17.6° against 23.3°): `get_floor_normal()` returns the flat collision triangle. In 8 of the 63 steps the dominant surface differed from the one the clean rules (no noise) would give.
</details>

<details><summary>T1</summary>

2 steps per second at 3 m/s, 500 ms apart. Step length in a real walker depends on leg length, speed, and slope; exercise E2 makes it follow speed, with a cadence you measure yourself.
</details>

<details><summary>T2</summary>

With f = 1 the error is (1 − f) · Δt, at most one tick: up to 16.7 ms at 60 Hz, 33 ms at 30 Hz. At 3 m/s on flat ground the step period of 250 ms is exactly 15 ticks at 60 Hz and 36 ticks at 144 Hz, so the strikes fall on tick ends and the error happens to be zero; at 30 Hz the period is 7.5 ticks and every second step is 16.7 ms early in its stamp. Any other speed or slope breaks the alignment.
</details>

<details><summary>T3</summary>

Measured before that branch existed: margin mean 184 ms (sd 5.9 ms) with L = 50 ms. The anchor is taken at the first physics tick, which runs after the scene has loaded; the catch-up ticks that follow advance the simulated clock past the wall clock, and every later tag lies about 134 ms further in the future than intended. The steps then trail the walk by about 184 ms.
</details>

<details><summary>T4</summary>

They agree: the classifier copies `rock_angle_start` and `rock_angle_end` from the same material file in `read_material()`. It copies them once, in `_ready()`; a change made to the loaded material while the game runs reaches the paint at once and the footsteps not at all.
</details>

<details><summary>T5</summary>

Every step plays on arrival with the jitter of O3 (sd 7–8 ms, single errors near 19 ms), and 17–20 ms on average earlier than with tags at L = 50 ms.
</details>

<details><summary>T6</summary>

Five times longer decays make the rock ring like a ceramic tile or a hollow slab. Dividing the frequencies by 3 lowers the modes to 207–1743 Hz: a larger, heavier block. In modal synthesis the frequencies carry size and shape, the decays carry material damping (van den Doel, Kry, Pai §3).
</details>
