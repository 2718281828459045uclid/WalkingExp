# Lesson 06. Spatial audio and ambience

Lesson scene: `game/scenes/lessons/06_spatial_audio.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–05 are unchanged; the Lesson 05 scene sends no emitter positions.

## 1. Orientation

Lessons 04 and 05 sent the player's state and the player's footsteps. Both describe the player; neither describes the place. This lesson puts sound sources into the world and lets the listener move among them: crickets in a hollow, birds on the hillside, and wind that grows as the player climbs. It answers five questions:

1. Where is a source, as the listener hears it? (listener space, spherical coordinates)
2. Which program computes that, and how often? (Godot, 30 times per second; update rates)
3. How does a direction become a gain per loudspeaker? (equal-power panning with `PanAz`; first-order Ambisonics with `PanB` and `DecodeB2`)
4. How does distance change a sound? (inverse distance law, air absorption)
5. How does a stream of control values at 30 Hz become a smooth signal, and what goes wrong at ±180°? (`Lag`, angle unwrapping)

Goal served (`plan.md`): "music and audio that is primarily diegetic", and the artistic goal of "a sense of place and space that a character can traverse".

Files:

| File | Role |
|---|---|
| `game/src/audio/listener_math.gd` | `ListenerMath`: static functions. World point → listener space → azimuth, elevation, distance; angle unwrapping. |
| `game/src/audio/sound_emitter.gd` | `SoundEmitter` (`@tool` Node3D): a point that names a SynthDef (`kind`), with an id, a level, and a marker sphere. |
| `game/src/audio/spatial_audio_reporter.gd` | `SpatialAudioReporter` (Node): reads the listener and the emitters, sends `/emitter/kind`, `/emitter/pos`, `/wind`. |
| `game/src/lessons/spatial_audio.gd` | Scene root. Extends `footsteps.gd` (Lesson 05); adds the L key and HUD lines. |
| `game/scenes/lessons/06_spatial_audio.tscn` | The Lesson 05 scene plus an `Emitters` node with three `SoundEmitter` children and a `SpatialReporter` node. |
| `game/project.godot` | Input action `toggle_listener` (L, left stick click). `run/main_scene` pointed to this scene while it was the newest lesson scene. |
| `audio/supercollider/06_spatial_audio.scd` | A spatializer function, SynthDefs `\crickets`, `\bird`, `\noiseProbe`, `\windBed`; OSCdefs that run one synth per emitter. |
| `tools/spatial_nrt.sh`, `tools/sc/spatial_nrt.scd` | Offline measurement: levels per loudspeaker for directions, elevations, distances; a check of the ambience SynthDefs. |
| `game/tests/test_06_*.gd` | Listener math; the scene's packets. |
| `docs/decisions/0007-listener-relative-spatial-audio.md` | Why Godot computes the coordinates and SuperCollider pans. |

Reading: SuperCollider help for `PanAz`, `PanB`, `DecodeB2`, `Lag`. Andy Farnell, *Designing Sound*, the wind practical. V. Pulkki, "Virtual Sound Source Positioning Using Vector Base Amplitude Panning" (1997), sections 1–2, for pairwise panning. D. G. Malham and A. Myatt, "3-D Sound Spatialization using Ambisonic Techniques" (1995), for B-format. ISO 9613-1 (1993) describes air absorption; read its introduction and look at the shape of its tables, not the formulas. Full entries: `docs/references.md`. There is no DDG reading: the geometry is that of a sphere around one point, with the coordinate charts of first-year calculus.

The Ambisonic Toolkit (ATK) appears in decision 0003. On this machine its UGens (sc3-plugins) are installed, its class library (the `atk-sc3` quark) is not, so this lesson uses only the panners built into SuperCollider. Lesson 06 exercise E4 and decision 0007 return to this.

## 2. Predict

Work these on paper before reading the code.

- **P1.** The listener stands at the origin and faces −z; +x is right, +y up. A source sits at (3, 4, −4). Define the azimuth as the angle in the horizontal plane from "ahead" toward "right", and the elevation as the angle above the horizontal plane. Compute azimuth, elevation, and distance. Which inverse trigonometric function gives the azimuth for all four quadrants?
- **P2.** The listener turns 90° to the left (counterclockwise seen from above) and stays at the origin. The source at (0, 0, −5) was straight ahead. What is its azimuth now? Write the listener's transform as a basis and a position; which part of the transform takes part in "turning" and which in "moving"?
- **P3.** A source is behind the listener. Godot sends azimuth +170°, then, after a small turn, −170°. SuperCollider smooths the azimuth with `Lag`, which glides from the old value to the new one. Through which directions does the glide pass? Find an azimuth equivalent to −170° that makes the glide short.
- **P4.** A point source radiates its power evenly over a sphere. The intensity falls as 1/d², the amplitude as 1/d. How many dB does the level fall per doubling of distance? With full level up to 2 m, what is the level at 32 m relative to 2 m?
- **P5.** `PanAz` places loudspeakers evenly on a ring and gives each source to its two nearest loudspeakers with gains cos θ and sin θ, θ from 0 to 90° between them. Why cos and sin, rather than 1 − t and t? With two loudspeakers (left at −90°, right at +90°), where do sources at 0° and at 180° go, and what is each channel's level in dB?
- **P6.** `Lag.kr(x, 0.15)` reaches 60 dB (a factor 1000) closer to a new value in 0.15 s. Lesson 02 described the same filter as x ← x + (target − x)(1 − e^(−kΔt)). Find k. Godot sends a new azimuth every 1/30 s. What fraction of each step is still missing when the next value arrives?
- **P7.** One send holds three `/emitter/pos` messages (types `ifff`) and one `/wind` message (types `ff`) in a bundle. Count the bytes, using Lesson 04's padding rules and Lesson 05's bundle layout. How many bytes per second at 30 sends per second?
- **P8.** First-order Ambisonics encodes a source in direction (az, el) as four signals, W = s/√2, X = s cos az cos el, Y = s sin az cos el, Z = s sin el (one sign convention of several). A decoder for a ring of four loudspeakers at ±45° and ±135° feeds each loudspeaker a mix of W, X, Y that points a virtual microphone at it. For a source straight ahead, which loudspeakers receive signal? For a source straight overhead?

## 3. Read

### 3.1 `listener_math.gd`

Read the header diagram. The listener's transform maps listener space to world space, so the inverse maps world points into listener space. `to_listener_space()` applies `affine_inverse()`; its Q/A comment says why not `inverse()`.

`spherical()` holds P1. Its first Q/A comment explains the order of the arguments in `atan2(local.x, -local.z)`: the textbook measures from +x toward +y; here the reference direction is −z and the angle grows toward +x. The second Q/A comment concerns the pole: a point straight overhead has no azimuth, as the North Pole has no longitude. The third explains why the elevation uses `atan2` and not `asin`. Check both against a point at (0, 5, 0).

`direction_azimuth()` is for the wind, whose source is "far away in a direction". It uses only the basis of the transform. P2 asked why.

`unwrap_angle()` holds P3. `wrapf(angle − previous, −π, π)` is the shortest signed turn from the previous angle to the new one; adding it to the previous angle gives an angle that may lie outside (−π, π] but never jumps. Why is a jump-free sequence acceptable to `PanAz`? (Section 3.5.)

### 3.2 `sound_emitter.gd`

A `SoundEmitter` holds no sound. It is a name (`kind`, the name of a SynthDef), a number (`emitter_id`), and a level (`amp`). Its marker sphere is an internal child built in `_ready()`, like the terrain mesh of Lesson 01. The script is `@tool`, so the marker also appears in the editor: open the scene, select `Emitters/Crickets`, and move it.

### 3.3 `spatial_audio_reporter.gd`

Read the header: the list of files and what each controls, then the three addresses. Then the code:

1. `_ready()` collects the `SoundEmitter` children of `emitters_root`, and fills the announce timer. Read the Q/A comment about the first tick.
2. `_physics_process()` runs two clocks. The announce timer sends `/emitter/kind` once per second. The `RateClock` of Lesson 04 sends positions 30 times per second.
3. `_send_positions()` computes the spherical coordinates for each emitter, unwraps each azimuth against the one sent before, and builds one bundle with every `/emitter/pos` and the `/wind` message. The tag is "immediately" (`send_bundle(0.0, ...)`): the bundle is used to keep one tick's values in one packet, not to schedule them.

Why does `/emitter/kind` repeat every second when the kinds never change? (Lesson 04 O3: a receiver started after Godot.)

The wind strength is a clamped straight line of the player's height, `wind_strength_at()`. The wind direction is `wind_from`, a world direction; its azimuth is unwrapped as well.

### 3.4 `spatial_audio.gd` and the scene

The root script adds one key. **L** switches the listener between the `Camera3D` and the `CameraPivot`. The pivot sits at the player's head height (1.5 m above the feet) and turns with the camera; the camera sits behind it on the spring arm. Which of the two should be the listener in a third-person game? Section 4 measures the difference.

In the `.tscn`, `SpatialReporter.listener` is a path into the instanced player scene: `../Player/CameraPivot/SpringArm3D/Camera3D`.

### 3.5 `06_spatial_audio.scd`

**Block 1** begins with two settings read from environment variables: `~speakers` (output channels, default 2) and `~panner` (`\panAz` or `\ambisonic`). They are read while the SynthDefs are built; change them, run block 1 again, and the next synths use the new layout.

`spatialize` is an sclang function called inside each SynthDef function, as `footEnvelopes` was in Lesson 05. Read its first Q/A comment; it lists the four steps in order:

1. `Lag.kr` on azimuth, elevation, distance (P6).
2. Gain `refDist / max(dist, refDist)`: the inverse distance law (P4) with a floor at `refDist` = 2 m.
3. `LPF` with cutoff 20000 / (1 + dist / airMeters), `airMeters` = 25. This is a stand-in for air absorption, not a physical model. It has the right direction (more distance, less treble) and an exaggerated size: ISO 9613-1 gives smaller losses at the distances of this 128 m terrain; exercise E6 measures how much smaller.
4. The panner. `PanAz.ar(speakers, sig, az / pi)`: the position is periodic with period 2, so the unwrapped azimuth of Godot needs no wrapping here. With `\ambisonic`, `PanB` encodes to W, X, Y, Z and `DecodeB2` decodes W, X, Y to a ring. Read the Q/A comment on B-format (P8). `PanB` takes the azimuth in units of π and the elevation in units of π/2; the comment says these were measured, and O4 shows how.

Texts on Ambisonics (Malham and Myatt among them) measure the azimuth counterclockwise, with Y pointing left. SuperCollider's `PanB`, `DecodeB2`, and `PanAz`, as measured by `tools/spatial_nrt.sh`, put a positive azimuth on the right, as `ListenerMath` does. Check the sign whenever a formula comes from a paper.

The SynthDefs:

| SynthDef | Model | Controls |
|---|---|---|
| `\crickets` | three sine tones, each switched by a fast pulse train (wing strokes) and a slow one (chirp groups) | position |
| `\bird` | random whistles (`Dust` triggers) with a pitch sweep and a 25 Hz trill | position |
| `\noiseProbe` | pink noise | position |
| `\windBed` | one band-passed noise per channel (diffuse) plus one resonant low-pass noise panned to the wind's direction | `strength`, `az` |

The wind bed does not use `spatialize`: it has no distance. Read its two Q/A comments: decorrelated noise in each channel, and the squared strength.

**Block 2** holds the responders. `~emitters` maps an id to an Event with keys `kind`, `amp`, `node`, `seen`; the comment says why the key is `node` and not `synth`. Read the two Q/A comments in `\emitterPos`: a position that arrives before its kind, and why the synth starts on the first position rather than on the kind.

**Block 3** prints each emitter. **Block 4** releases the synths and removes the responders.

### 3.6 `tools/spatial_nrt.sh`

The tool runs block 1 twice, once per panner, and after each run builds probe SynthDefs from `~spatialize` (block 1 stores its function there). It renders white noise at nine azimuths, three elevations, and eight distances, then the four ambience sounds, all in non-real-time mode. Its first argument is the number of loudspeakers. Why white noise for the probes and not pink? (Hint: the probe level is measured over 0.8 s; how much does a pink noise's level change over 0.8 s, given how much of its power lies below 100 Hz?)

## 4. Run and observe

Start SuperCollider, boot the server (`s.boot`), run block 1, then block 2 of `06_spatial_audio.scd`. Run blocks 1 and 2 of `05_footsteps.scd` as well if you want footsteps. Start the lesson scene (F6). Use headphones for O1–O3. The blue spheres are the emitters.

- **O1.** At the spawn, read the HUD lines of the three emitters. Turn the camera slowly a full circle with the mouse. Watch the azimuths and listen. Where is each bird when its azimuth reads 0? At ±90°? At 180°? Can you tell a source in front from one behind?
- **O2.** At the spawn, press **L** and read the HUD again. Write down the azimuth and distance of each emitter for both listeners. Which emitter changes most, and why that one?
- **O3.** Walk straight up the hill from the spawn for about 12 s. Every 2 s, write down the crickets' azimuth and elevation and the wind strength. Listen to where the crickets go, and to the wind.
- **O4.** In a terminal, run `tools/spatial_nrt.sh 2`. Read the `DIR Az` lines: compare az 0 with az 180, and az −45 with az −135. Then the `DIR B` lines, and the total level column of both. Then run `tools/spatial_nrt.sh 4` and compare the same lines, and the `ELEV` lines of both runs.
- **O5.** In the `DIST` lines of either run, compute the level change per doubling of distance for the full band and for the band above 4 kHz. Compare with P4.
- **O6.** Read the HUD's OSC line (Lesson 04): messages and bytes per second. Compare with the Lesson 05 scene. Then compare the difference with P7.
- **O7.** With SuperCollider running, flick the mouse fast so the camera turns half a circle in a fraction of a second. Listen to a source as it passes behind you. Then do T3 and repeat.

## 5. Tweak

Restore each change after the observation.

- **T1.** In block 1, set `~speakers = 2; ~panner = \ambisonic;` above the block, run block 1, then block 4 and block 2 (the running synths keep the old SynthDef until they are replaced). Walk the circle of O1. What changed in the width of the image? Compare with the `DIR B` lines of O4.
- **T2.** In the argument list of `\crickets`, set the `lagTime` default to 0 and run block 1, 4, 2. Turn the camera at a medium speed. What do you hear? At what update rate would the steps stop being audible? Try **O** (Lesson 04) to change only the state rate; why does that key not change the emitter rate? Change `send_rate_hz` on the `SpatialReporter` node instead.
- **T3.** In `spatial_audio_reporter.gd`, comment out the line `s.x = ListenerMath.unwrap_angle(previous.x, s.x)`. Repeat O7. What does the source do as it crosses 180°? Why is the error audible with `Lag` and inaudible without it?
- **T4.** In `\crickets`, change `refDist = 2` to `refDist = 10`. Walk away from the crickets. Over which range of distances does the level now stay constant? What does a large `refDist` model?
- **T5.** In `spatialize`, change `airMeters` defaults from 25 to 1000 in all three SynthDefs. Walk toward and away from a bird. Which cue for distance remains?
- **T6.** On the `SpatialReporter` node, set **Wind From** to (0, 0, 1). Where is the wind's whistle at the spawn? Set **Wind Per Meter** to 0. What does the climb sound like now?

## 6. Exercises

- **E1 ★ Doppler.** A moving source changes pitch by the rate at which its distance changes. In SuperCollider, a delay line of length dist / 343 s (`DelayC`) produces the Doppler shift by itself. Add it to `spatialize`, choose a maximum delay, and make the bird of E5 fly past at 15 m/s. Measure the pitch ratio before and after it passes and compare with c / (c ∓ v).
- **E2 ★ Send less.** Most of the 30 sends per second repeat the previous values when the player stands still. Send `/emitter/pos` for an emitter only when its azimuth changed by more than a threshold, or its distance by more than a fraction. Choose the thresholds from what you can hear, and measure the bytes per second standing, walking, and turning. What must the receiver assume about an emitter that sends nothing?
- **E3 ★★ Occlusion.** When the hill stands between listener and source, the source should sound duller and quieter. Cast a ray from the listener to each emitter (`PhysicsDirectSpaceState3D.intersect_ray()`), append an occlusion value at the end of `/emitter/pos`, and apply a low-pass and a gain in `spatialize`. Glide the value so a source passing behind a ridge does not switch.
- **E4 ★★ Headphones.** Neither `PanAz` with two channels nor the two-channel `DecodeB2` separates front from back (O4). Build a simple binaural model for headphones: an interaural time difference after Woodworth, (a / c)(θ + sin θ) for head radius a ≈ 0.0875 m, and a head-shadow low-pass on the far ear. Compare front and back in a listening test. Then read the ATK documentation on its binaural decoders and decide whether the quark is worth installing (decision 0007).
- **E5 ★★ A moving source.** Give a bird a flight path (`Path3D` and `PathFollow3D`) of your design. At 10, 30, and 60 Hz send rates, measure the largest azimuth step between sends when the bird passes close to the listener. Which rate does a close pass need, and which one a distant source? Make the rate a property of each emitter.
- **E6 ★★★ Air you can hear.** Replace the stand-in air absorption with a model fitted to ISO 9613-1: choose a temperature and humidity, take the absorption coefficients at the octave-band centers, and build a filter whose loss at each band follows α(f) · d. Measure it with a version of `tools/spatial_nrt.sh`. At which distance on this terrain does the difference from no absorption become audible to you? Decide whether to keep the physical model, the stand-in, or both behind a switch.

## 7. Reflect

- **R1.** The listener sits on the camera, 4.5 m behind and above the player's head. Footsteps (Lesson 05) are not spatialized at all. Where should each kind of sound be heard from: the camera, the head, or a point between? What do films do with a camera that moves away from the person on screen?
- **R2.** Godot sends coordinates relative to the listener. An alternative sends world positions of emitters and listener, and lets SuperCollider compute the rest. Which version needs fewer messages when the listener turns but nothing else moves? Which one keeps the geometry in one program? Decision 0007 records a choice; would you choose differently for a game with 200 sources?
- **R3.** Lesson 27 drives plants and audio from one wind field. Today the wind is a direction and a strength from the player's height. What would a wind field need to provide to the audio (a value at the listener, values at several points, a gradient)? How would the wind bed change?
- **R4.** Lesson 29 adds reverb zones and a mix. Distance already lowers the level and the treble. Which other distance cue does a real space provide that this lesson leaves out? (Consider the ratio of direct to reverberant sound.)
- **R5.** The rock formations of Phase 3 will reflect sound. Signed distance fields answer "how far is the nearest surface" cheaply. How could that number shape the sound at the listener, without ray tracing sound?

## 8. Answers

<details><summary>P1</summary>

Azimuth atan2(x, −z) = atan2(3, 4) = 36.87° (right of ahead). Horizontal distance √(3² + 4²) = 5. Elevation atan2(4, 5) = 38.66°. Distance √(9 + 16 + 16) = √41 = 6.40 m. `atan2` returns the angle in all four quadrants; `atan(x / −z)` loses the sign of −z and cannot tell ahead from behind. `test_06_listener_math.gd` checks the same construction at (1, 1, −1): 45°, 35.26°, √3.
</details>

<details><summary>P2</summary>

After a left turn the listener faces −x, and its right is −z. The source at (0, 0, −5) lies to the right: azimuth +90°. The transform is a basis (three columns: the listener's right, up, and back directions in world space) and an origin. The basis takes part in turning, the origin in moving. A direction (the wind) uses only the basis; a point (an emitter) uses both. The test checks both cases with a listener that is turned and moved.
</details>

<details><summary>P3</summary>

From +170° to −170° the numeric glide passes through 0°: the source sweeps around the front of the listener in about the lag time and returns behind. −170° + 360° = +190° is 20° from +170°, and the glide stays behind. `unwrap_angle(170°, −170°)` returns 190°; `PanAz` with position 190/180 = 1.056 places it where −170° lies, since its period is 2. The test checks the case 179°, −179° → 181°.
</details>

<details><summary>P4</summary>

20 log₁₀(1/2) = −6.02 dB per doubling. From 2 m to 32 m is four doublings: −24.1 dB. Measured (`tools/spatial_nrt.sh 2`, total level, white noise): 2 m −16.4 dB, 32 m −43.6 dB, a drop of 27.2 dB. The extra 3.1 dB is the air-absorption filter, which removes part of the white noise's treble. 1 m and 2 m measured −16.3 and −16.4 dB: the floor at `refDist`.
</details>

<details><summary>P5</summary>

With gains cos θ and sin θ, cos² θ + sin² θ = 1: the total power stays constant as the source moves between two loudspeakers. With 1 − t and t, the power at the midpoint is 0.5² + 0.5² = 0.5, a 3 dB dip. With two loudspeakers at ±90°, a source at 0° and one at 180° both lie halfway: each channel gets cos 45° = 0.707, −3 dB. Front and back are the same signal. Measured: az 0 and az 180 both −19.4 dB per channel; az 90 −16.4 dB in one channel, nothing in the other; the total stays −16.4 dB at every azimuth.
</details>

<details><summary>P6</summary>

e^(−k · 0.15) = 1/1000, so k = ln 1000 / 0.15 = 46.1 s⁻¹. After 1/30 s, the missing fraction is e^(−46.1/30) = 1000^(−0.222) = 0.215: about a fifth of each step remains when the next value arrives, so the glide never stops while the listener turns at constant speed. The lag delays the image by about 1/k = 22 ms.
</details>

<details><summary>P7</summary>

`/emitter/pos`: address 12 characters + 1 zero → 16 bytes; tags `,ifff` 5 + 1 → 8; four arguments 16. Total 40 bytes. `/wind`: address 8, tags `,ff` → 4, arguments 8: 20 bytes. Bundle: 8 (`#bundle`) + 8 (tag) + 3 · (4 + 40) + (4 + 20) = 172 bytes. At 30 sends: 5160 B/s; with the `/emitter/kind` bundle (152 bytes once per second): 5312 B/s. `test_06_spatial_scene.gd` checks 172 and 152. O6 measured the difference between the Lesson 06 and Lesson 05 scenes: 6632 − 1320 = 5312 B/s.
</details>

<details><summary>P8</summary>

A virtual cardioid pointing at a loudspeaker at angle φ receives ½(√2 W + X cos φ + Y sin φ) ∝ ½(1 + cos(az − φ)) for a horizontal source. For a source straight ahead: the front pair (φ = ±45°) gets ½(1 + 0.707) = 0.854, the rear pair ½(1 − 0.707) = 0.146. All four loudspeakers receive signal, the rear pair 15.3 dB below the front. Overhead (el = 90°), X and Y are 0, and all four get ½. Measured with `tools/spatial_nrt.sh 4` (`DIR B az 0`, `ELEV B el 90`): front −17.9, rear −33.2 dB; overhead −22.4 dB in all four.
</details>

<details><summary>O1</summary>

At azimuth 0 the source is straight ahead of the camera, in the middle of the image; at +90° to the right; at 180° behind. With two channels and `PanAz`, a source ahead and a source behind give the same signal (P5): the image folds onto a line from left to right, and only the movement of the head (turning and listening for which way the sound moves) separates front from back. E4 addresses this.
</details>

<details><summary>O2</summary>

Measured at the spawn (headless run):

| Emitter | camera: az, el, dist | head: az, el, dist |
|---|---|---|
| 0 crickets | −35°, +10.1°, 17.5 m | −46°, +12.5°, 14.2 m |
| 1 bird (east) | +32°, +22.1°, 28.5 m | +38°, +25.3°, 25.1 m |
| 2 bird (north) | −15°, +15.5°, 81.8 m | −16°, +16.4°, 77.7 m |

The nearest emitter, the crickets, changes most: the camera sits 4.3 m behind and 1.2 m above the head (4.5 m in all), which is a quarter of the distance to the crickets and an eighteenth of the distance to the far bird.
</details>

<details><summary>O3</summary>

Measured on a headless walk from the spawn straight toward −z, camera listener:

| time | player height | crickets az, el | wind |
|---|---|---|---|
| 0 s | 1.5 m | −35°, +10.1° | 0.38 |
| 2 s | 2.8 m | −47°, +1.9° | 0.44 |
| 4 s | 4.4 m | −66°, −13.2° | 0.52 |
| 6 s | 6.3 m | −92°, −29.7° | 0.61 |
| 8 s | 8.1 m | −117°, −38.5° | 0.71 |
| 10 s | 9.9 m | −135°, −40.5° | 0.79 |
| 12 s | 11.2 m | −146°, −39.4° | 0.86 |

The crickets move from front-left to behind-left and below. With `PanAz` the elevation is not heard; with two channels, neither is the move behind. The wind's direction stays at +64° (the player walks without turning), and its strength follows the height: 0.3 + 0.05 · y.
</details>

<details><summary>O4</summary>

Two channels, `PanAz`: az 0 and az 180 both −19.4 dB per channel. az −45 and az −135 both −17.1 / −24.8 dB. Total −16.4 dB at every azimuth. Ambisonic decode to two channels: az 0 −22.5 dB per channel (total −19.5 dB, 3 dB below the sides), az ±45 −17.8 / −33.1 dB: the far channel is 15.3 dB below the near one, where `PanAz` gave 7.7 dB. Off-center sources sit nearer the loudspeakers, and the center is 3 dB quieter than the sides.

Four channels, `PanAz`: az 0 → channels 0 and 1 (front left and front right) at −19.4 dB each; az 45 → channel 1 alone at −16.4 dB; az −135 → channel 3 alone. The loudspeakers sit at −45°, +45°, +135°, −135°, numbered clockwise from front left. Ambisonic decode to four channels: every direction reaches three or four loudspeakers, total −14.7 dB.

Elevation: with two channels the ambisonic levels at el 0, 45, 90 were −22.4, −22.5, −22.4 dB: a source ahead has Y = 0 already, and the two-channel decoder uses W and Y, so lifting the source changes nothing. With four channels: el 0 front −17.8 / rear −33.1; el 45 −18.9 / −28.5; el 90 −22.4 in all four. These levels also fixed the units of `PanB`: elevation 1 (in its units) is straight up.
</details>

<details><summary>O5</summary>

Full band, per doubling from 2 m: −6.4, −6.5, −6.9, −7.4, −7.8, −8.4 dB (2→4 … 64→128 m). Above 4 kHz: −6.5, −6.8, −7.5, −8.4, −10.3, −12.9 dB. The inverse distance law accounts for 6.02 dB of each step; the rest is the air-absorption filter, which takes more as the cutoff falls toward the band above 4 kHz.
</details>

<details><summary>O6</summary>

Measured headless, player standing, averaged over 10 s: the Lesson 05 scene sends 30 messages and 1320 bytes per second (`/player/state`); the Lesson 06 scene 153 messages and 6632 bytes per second. The difference: 123 messages (30 · 4 in the position bundles, 3 in the kind bundle) and 5312 bytes, as P7 predicts. Footsteps add to both while walking. The Lesson 04 counters count each message inside a bundle (Lesson 05 §3.2).
</details>

<details><summary>O7</summary>

With unwrapping, a source passing behind stays behind: the azimuth sent grows past 180° and `PanAz` places it correctly. `test_06_spatial_scene.gd` turns the camera 0.3 rad per physics tick for 2 s; every azimuth step between sends stayed below π, and the azimuth grew by more than 30 rad without a jump. A fast flick can still make the image lag: the listener's turn is smoothed with a 22 ms time constant (P6).
</details>

<details><summary>T1</summary>

Both panners feed both channels for a source at ±45°. With the ambisonic decode the far channel is 15.3 dB below the near one, where `PanAz` gave 7.7 dB (O4): off-center sources sit nearer the loudspeakers, and the center is 3 dB quieter than the sides. Sources at ±90° stay in one channel with either panner. First-order Ambisonics on two loudspeakers trades sharpness of the image for smoothness of movement.
</details>

<details><summary>T2</summary>

Without the lag, the gain of each channel changes in a step 30 times per second: a faint buzz at 30 Hz on a steady tone (zipper noise), strongest on the crickets' pure tones. The steps become inaudible when they are smoothed, or small and frequent enough; raise `send_rate_hz` with the lag at 0 to find the rate for your ears. **O** changes only `PlayerStateReporter.send_rate_hz`; the `SpatialReporter` has its own `RateClock` and its own `send_rate_hz`.
</details>

<details><summary>T3</summary>

The source sweeps around the front each time its azimuth crosses ±180°: the lag glides through 0 as in P3. Without `Lag`, `PanAz` would jump from +179° to −179°, which are neighbors on its period-2 position, and nothing would be heard. The error lies in the combination of a periodic quantity and a linear filter.
</details>

<details><summary>T4</summary>

The level is constant out to 10 m and falls from there. A large `refDist` models a large source: a field of crickets, a stream, the sea. Such a source does not shrink to a point as the listener approaches, so its level stops growing. The same 1/d law holds beyond `refDist`.
</details>

<details><summary>T5</summary>

Level remains: the 1/d gain still lowers distant sources. What is lost is the change of timbre that separates a quiet near source from a loud far one. Lesson 29 adds the third cue, the ratio of direct sound to reverberation.
</details>

<details><summary>T6</summary>

`wind_from` (0, 0, 1) points behind the player at the spawn (the camera faces −z): the whistle comes from 180°, which with two channels sounds the same as straight ahead. With **Wind Per Meter** 0 the strength stays at 0.3 everywhere, and the hill loses its exposure: nothing in the sound tells that the player has climbed.
</details>
