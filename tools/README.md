# Tools

## Checks

| Script | Purpose |
|---|---|
| `check.sh [frames]` | Headless regression check: runs every lesson scene and every `game/tests/test_*.gd`. Reports script and shader compile errors. |
| `render_check.sh [output_dir] [scenes...]` | Windowed check: renders each scene for 60 frames and saves a screenshot. Needed for visual results and compute shaders. A window appears briefly. |
| `godot/capture.gd` | SceneTree script used by `render_check.sh`. |
| `sc_check.sh [files...]` | SuperCollider syntax check in sclang batch mode: compiles each code block of `audio/supercollider/*.scd` and `tools/sc/*.scd` without running it (`sc/check_syntax.scd`). Boots no server. |
| `osc_roundtrip.sh` | Lesson 04 round trip: sclang listens (`sc/osc_roundtrip_listener.scd`), Godot sends three messages (`godot/osc_send.gd`), sclang checks the values. Boots no server. |
| `footstep_timing.sh [seconds] [immediate\|tagged] [latency ms] [--window]` | Lesson 05 timing measurement: sclang records `/foot/step` arrivals and time tags (`sc/footstep_timing_listener.scd`) while Godot walks the Lesson 05 scene forward (`godot/walk_steps.gd`). Prints interval spread, jitter, margin, late steps. Boots no server. |
| `spatial_nrt.sh [speakers] [output.wav]` | Lesson 06 offline measurement: block 1 of `audio/supercollider/06_spatial_audio.scd` built with each panner (`sc/spatial_nrt.scd`); white-noise probes at nine azimuths, three elevations, eight distances; level per loudspeaker channel; the ambience SynthDefs checked for silence, clipping, NaN. Plays nothing. |
| `footsteps_nrt.sh [output.wav]` | Lesson 05 offline render: block 1 of `audio/supercollider/05_footsteps.scd` rendered by scsynth in non-real-time mode (`sc/footsteps_nrt.scd`), 27 steps; prints peak and RMS per step, fails on silence, clipping, NaN. Plays nothing. |
| `mesher_compare.sh [shape.tres] [cell sizes...]` | Lesson 08: samples an `SdfShape` (default `boulder_pile.tres`) at each cell size (default 0.3 0.15 0.1), runs pass 1 of surface nets on the GPU and on the CPU three times, prints sizes, timings per stage, and the largest GPU–CPU differences (`godot/mesher_compare.gd`). Opens a blank window: a `RenderingDevice` exists only in windowed runs. |
| `raymarch_perf.sh [frames]` | Lesson 10: opens the Lesson 10 scene in a window with vsync off, at two fixed camera views (overview, close), and prints the mean frame time with the formations hidden and with `max_steps` 16, 32, 64, 96, 192 (`godot/raymarch_perf.gd`). About half a minute. |

## Python utilities

Each script states its inputs and outputs at the top and runs with `python3 tools/<script>.py`.

Planned:

| Script | Lesson | Purpose |
|---|---|---|
| `plot_height_field.py` | 01 | Plot h, its contour lines, and its gradient field with matplotlib; compare with the in-game slope view. |
| `plot_convergence.py` | 01 | Log-log plot of normal error against grid spacing (exercise E6). |
| `osc_probe.py` | 04 (exercise E3) | Send and receive test OSC messages without Godot or SuperCollider running. |
| `bake_normal_map.py` | 20 | Write a normal map `.png` from a height function. |

Scripts that read untrusted files (downloads, archives) run with `python3 -I` from outside the folder that holds those files.
