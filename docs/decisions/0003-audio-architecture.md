# 0003. Audio architecture: Godot sends state and events to SuperCollider over OSC

Status: accepted, 2026-11-22.

## Context

`plan.md` calls for diegetic audio produced by physical simulation and synthesis, sample playback where useful, and music that is in part generative and influenced by player movement and environment. The developer works in SuperCollider and Ableton Live.

## Decision

SuperCollider runs as a separate process. Godot sends OSC messages over UDP to sclang on port 57120. sclang interprets the messages and starts and controls synths on scsynth. SuperCollider sends messages back to Godot on UDP port 9000 for events that originate in the music (beat clock, section changes).

```
 Godot (game/src/audio/, Lesson 04)          SuperCollider (audio/supercollider/)
 ┌──────────────────────────────┐   OSC    ┌──────────────────────────────┐
 │ player state, contact events │ ───────▶ │ sclang :57120                │
 │ listener-relative positions  │   UDP    │   OSCdefs → Synths on scsynth│
 │                              │ ◀─────── │   music clock, sections      │
 │ listens on :9000             │          │                              │
 └──────────────────────────────┘          └──────────────────────────────┘
```

Message classes (addresses are provisional; Lesson 04 fixed `/player/state x y z speed ground` and `/player/ground name`, decision 0005):

| Class | Rate | Example address and arguments |
|---|---|---|
| Continuous state | 30–60 Hz | `/player/state x y z speed balance stance` |
| Discrete events | on occurrence | `/contact/foot side surface impact_speed slope nx ny nz` |
| Environment | on change, 1–10 Hz | `/env/zone name`, `/env/wind speed direction` |
| Return channel (SC → Godot) | on occurrence | `/music/beat bar beat`, `/music/section name` |

Spatialization: Godot computes listener-relative coordinates (azimuth, elevation, distance) for each source and sends them. SuperCollider pans (`PanAz`, or the Ambisonic Toolkit with binaural decoding). Godot's own `AudioStreamPlayer3D` remains available for sounds that need no synthesis.

## Timing

UDP on localhost adds well under a millisecond of transport delay. The larger error comes from Godot's loop: events leave at physics-tick boundaries, quantized to 16.7 ms at 60 Hz. In a fast footstep sequence that jitter is audible.

Mitigation: OSC bundles with timetags. Godot stamps each event with its simulation time plus a fixed latency (for example 50 ms), and SuperCollider schedules the sound at that time. Lesson 05 measures the jitter before and after the change.

## Consequences

- Sound design happens in SuperCollider with live coding. Changes require no game restart.
- During development the game depends on a running SuperCollider instance. The OSC sender must tolerate its absence without errors.
- Distribution: bundling scsynth with a game brings GPL obligations. Outside the scope of a learning project; recorded here for later reference.
- Ableton Live produces samples, impulse responses, and stems. Exported files go to `game/assets/audio/` (decision 0004).
