# 0007. Listener-relative coordinates from Godot, panning in SuperCollider

Status: accepted, 2026-11-22 (Lesson 06).

## Context

Decision 0003 assigns spatialization to SuperCollider and the computation of listener-relative coordinates to Godot. Lesson 06 is the first lesson with positioned sources. Open questions: what exactly travels over OSC, at what rate, how SuperCollider avoids audible steps and wrap-around errors, which panner to use, and how a receiver started late learns the sources.

The Ambisonic Toolkit named in decision 0003 is installed only in part on the development machine: its UGens (sc3-plugins) are present, its class library (the `atk-sc3` quark) is not. Installing software is outside the lesson's scope.

## Decision

1. **Godot sends azimuth, elevation, distance per emitter**, computed by `ListenerMath` (`game/src/audio/listener_math.gd`) from the listener's transform. Azimuth 0 is ahead, positive to the right; elevation positive upward; both in radians. The listener is a `Node3D` assigned in the scene (the camera by default; the L key switches to the head).
2. **The azimuth is unwrapped in Godot**: each value is the one equal to it modulo 2π that lies closest to the value sent before. SuperCollider's smoothing (`Lag`) then never glides the long way round, and `PanAz`, periodic in its position, needs no wrapping.
3. **Rate and grouping.** `SpatialAudioReporter` sends every emitter's `/emitter/pos` and one `/wind` message in one bundle tagged "immediately", 30 times per second (`RateClock`, Lesson 04). The bundle keeps one tick's values in one packet; it schedules nothing.
4. **Announcement.** `/emitter/kind` (id, SynthDef name, level) for all emitters goes out once per second, so a receiver started after Godot learns the emitters within a second. SuperCollider starts an emitter's synth on its first position after the kind is known, so `Lag` starts from the true position.
5. **Panning in SuperCollider** with `PanAz` (equal-power pairwise panning on a ring, horizontal only) by default; first-order Ambisonics (`PanB` encoding, `DecodeB2` decoding to a ring) as an alternative selected when block 1 is built. Both are built into SuperCollider 3.13.
6. **Distance** is a gain refDist / max(d, refDist) (1/d law, refDist 2 m) and a low-pass whose cutoff falls with distance, a stand-in for air absorption.
7. **Addresses:**

| Address | Types | Arguments | When |
|---|---|---|---|
| `/emitter/kind` | `isf` | id, SynthDef name, level 0..1 | every `announce_interval` (1 s), all emitters in one bundle |
| `/emitter/pos` | `ifff` | id, azimuth (rad, unwrapped), elevation (rad), distance (m) | `send_rate_hz` (30) times per second, in one bundle with `/wind` |
| `/wind` | `ff` | strength 0..1, azimuth of the wind's origin (rad, unwrapped) | with every `/emitter/pos` bundle |

## Consequences

- Turning the listener changes every emitter's coordinates, so every emitter is sent every time, whether or not anything moved. Three emitters cost 5312 bytes per second (measured, Lesson 06 O6). Many emitters would call for sending world positions instead, or sending only changes (Lesson 06 exercise E2).
- The geometry stays in Godot: occlusion (exercise E3), listener choice, and later the wind field (Lesson 27) are computed where the scene is.
- With two output channels neither panner separates front from back (Lesson 06 O4). Headphone listening needs a binaural model (exercise E4) or the ATK class library.
- The air-absorption filter is not fitted to ISO 9613-1 (exercise E6).
- `PanB` takes the azimuth in units of π and the elevation in units of π/2; `DecodeB2` numbers loudspeakers clockwise from front left. Both were measured with `tools/spatial_nrt.sh`.
- Decision 0003 lists the wind as environment state at 1–10 Hz under `/env/wind`. Because the wind's direction is sent relative to the listener, it changes whenever the listener turns; it travels as `/wind` in the position bundle at 30 Hz.
