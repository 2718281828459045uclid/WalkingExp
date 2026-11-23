# WalkingExp

A traversal sandbox for learning game development: procedural terrain and rock built from geometry, a body that walks, crawls, climbs, and balances under analog control, and diegetic audio synthesized in SuperCollider. Goals and constraints: `plan.md`. Sequence of work: `ROADMAP.md`.

## Directory map

```
WalkingExp/
├── plan.md                 Goals and teaching mode (source of intent)
├── ROADMAP.md              Phases, lessons, milestones
├── CLAUDE.md               Instructions for AI assistants working in this repository
├── discreteDifferentialGeometry.pdf   Crane, DDG notes; chapters cited by lessons
│
├── game/                   The Godot project. Godot sees nothing outside this folder.
│   ├── project.godot       Engine settings, input map, main scene
│   ├── src/                GDScript code
│   ├── shaders/            .gdshader files
│   ├── scenes/             .tscn scene files (node trees); scenes/lessons/ holds one per lesson
│   ├── data/               .tres Resources: parameters and asset references read by code
│   ├── tests/              Headless test scripts run by tools/check.sh
│   └── assets/             Exported art and audio (written by tools in art-source/)
│
├── audio/supercollider/    .scd files. Runs as a separate process; talks to game/ over OSC.
├── art-source/             Working files: Procreate, Ableton Live, Blender. Exports go to game/assets/.
├── curriculum/             Lessons, one folder each
├── docs/
│   ├── architecture.md     Module map: what each part provides and which lesson introduced it
│   ├── decisions/          Architecture decision records (engine, character, audio, assets)
│   └── references.md       Books, papers, articles, mapped to lessons
└── tools/                  check.sh, render_check.sh, Python utilities
```

How the parts control each other:

- `game/scenes/sandbox.tscn` (Lessons 00–01) contains a `Terrain` node and an instance of `scenes/player.tscn`. Each later lesson has its own scene in `game/scenes/lessons/`, built from the same parts; the newest one is the main scene (`run/main_scene` in `project.godot`).
- `Terrain` (`src/terrain/terrain.gd`) samples a `HeightField` (`src/terrain/height_field.gd`) whose values are stored in a `.tres` file that the scene assigns: `data/terrain/sandbox_height_field.tres` in `sandbox.tscn`, `data/terrain/steep_height_field.tres` in the Lesson 02 scene. It colors the result with `data/terrain/terrain_material.tres`, which wraps `shaders/terrain.gdshader`.
- `Player` (`src/player/player.gd`) walks on the terrain's collision shape and reads the input actions defined in `project.godot`.
- Lesson 02: the scene's root script `src/lessons/walking_on_a_surface.gd` extends `src/sandbox.gd`; `Player` shapes the stick with a `StickResponse` Resource (`src/input/stick_response.gd`, values in `data/input/walk_stick_response.tres`) when the scene assigns one; test geometry built from boxes derives from `BoxCourse` (`src/world/`). Module map per lesson: `docs/architecture.md`.
- Lesson 03: the scene's root script `src/lessons/painting_the_ground.gd` extends `src/sandbox.gd`. `Terrain` and a `RampTower` use `data/terrain/painted_terrain_material.tres`, which wraps `shaders/terrain_painted.gdshader` and samples the noise texture `data/terrain/ground_noise.tres`. The root script writes the material's `paint_view` and `show_contours` uniforms and the scene's `Environment` (tonemapper, fog).
- From Lesson 04 onward, `game/src/audio/` sends OSC to the patches in `audio/supercollider/` (decision 0003).
- From Lesson 07 onward, `game/src/sdf/` holds signed distance functions as trees of Resources; boulders are `.tres` files in `game/data/rocks/`, drawn as plane cuts by `SdfSlice` nodes (decision 0008). Lesson 08 meshes them (`SdfMesher`, decision 0009); Lesson 09 adds field normals and curvature per vertex (`CurvatureMesher`, decision 0010). Lesson 10 draws them without a mesh by sphere tracing in a fragment shader whose `sdf_map()` is generated from the same `.tres` tree (`RaymarchVolume`, `SdfGlsl`, decision 0011).
- From Lesson 11 onward, `game/src/body/` holds the procedural body: a `Skeleton3D` built in code from `BodyProportions` (`game/data/body/`), drawn with capsules on `BoneAttachment3D` nodes, posed by a placeholder `WalkCycle` and following the Lesson 00 capsule (`BodyPlayer`, decision 0002 stage 2).
- Lesson 12: `FootRig` (a `BodyRig` subclass in `scenes/grounded_player.tscn`) places the feet with one ray per swinging foot and bends the legs with a hand-written two-bone IK solver (`TwoBoneIk`), or with Godot's `TwoBoneIK3D` for comparison; the pelvis height follows from the feet. Each plant emits `foot_planted`, and `PlantFootstepReporter` (a `FootstepReporter` subclass) sends `/foot/step` from it (decision 0002 stage 3, decision 0012).

## Running

Requires Godot 4.6.2 (`/Applications/Godot.app`).

1. Open Godot, choose **Import**, select `game/project.godot`.
2. Press **F5** to run the main scene (the newest lesson's scene), or open a lesson's scene and press **F6**. Lessons 00–01 use `scenes/sandbox.tscn`; later lessons use `scenes/lessons/NN_slug.tscn`.

Regression check (every lesson scene and test, headless), from the repository root:

```bash
tools/check.sh
```

Windowed check with screenshots, for visual changes:

```bash
tools/render_check.sh
```

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | W A S D | Left stick (analog) |
| Look | Mouse, arrow keys | Right stick |
| Cycle terrain view (lit / normals / slope) | Tab | Select / Back |
| Cycle normal method | N | Y (north button) |
| Release mouse | Esc (click to recapture) | — |
| Cycle physics tick rate 30 / 60 / 144 Hz (Lesson 02 scene) | T | D-pad up |
| Switch blend rule exponential / linear (Lesson 02 scene) | B | D-pad down |
| Cycle paint view (Lesson 03 scene and scenes built on it) | V | D-pad left |
| Toggle contour lines (Lesson 03 scene and scenes built on it) | C | D-pad right |
| Cycle tonemapper (Lesson 03 scene and scenes built on it) | M | Left shoulder |
| Toggle fog (Lesson 03 scene and scenes built on it) | F | Right shoulder |

## Where to start

`curriculum/00-environment/README.md`.
