# SuperCollider

Patches that receive game state from Godot over OSC and produce the game's diegetic sound and music. Architecture and message classes: `docs/decisions/0003-audio-architecture.md`.

Godot sends to sclang on port 57120. SuperCollider replies to Godot on port 9000.

| File | Lesson | Purpose |
|---|---|---|
| `00_osc_monitor.scd` | 00, 04 | Print incoming OSC messages |
| `04_player_state.scd` | 04 | OSCdefs for `/player/state` and `/player/ground`; prints the state twice per second. No server. |
| `05_footsteps.scd` | 05 | SynthDefs `\stepGrass`, `\stepDirt`, `\stepRock`; OSCdef `\footStep` plays `/foot/step` at the bundle's time tag; timing report. Blocks 2–4 need the server, booted by you. Block 1 is rendered offline by `tools/footsteps_nrt.sh`. |
| `06_spatial_audio.scd` | 06 | Spatializer (`Lag`, 1/d gain, air low-pass, `PanAz` or `PanB` + `DecodeB2`; `~speakers`, `~panner`); SynthDefs `\crickets`, `\bird`, `\noiseProbe`, `\windBed`; OSCdefs `\emitterKind`, `\emitterPos`, `\wind` run one synth per emitter and the wind bed. Blocks 2–4 need the server, booted by you. Block 1 is measured offline by `tools/spatial_nrt.sh`. |
| `13_balance.scd` | 13 | OSCdefs `\bodyBalance`, `\bodyBalanceState` for `/body/balance` and `/body/balance/state` (no server); SynthDef `\balanceTone`: pitch rises as the margin shrinks, a 3 Hz beating voice when outside. Blocks 2–3 need the server, booted by you. |

Code blocks open with a line holding only `(` and close with a line holding only `)`; `tools/sc_check.sh` compiles each block on its own and relies on this convention.

Planned layout, filled in from Lesson 04 onward:

```
supercollider/
├── main.scd          Boots the server, loads the files below, starts listening
├── synthdefs/        One file per sound family (footsteps, wind, water, music voices)
├── responders/       OSCdefs that map game messages to synths and parameters
└── score/            Generative music: Pdefs, state machines (Phase 8)
```

Recordings rendered from SuperCollider go to `recordings/` (ignored by Git). A take to keep moves to `art-source/` and its export to `game/assets/audio/`.
