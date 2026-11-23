# Architecture

How the code is organized and how the parts control each other. Each lesson that adds or changes a module updates this file. Rules for how lessons change code: `CLAUDE.md`, section "Lessons written ahead of the student".

## Process layout

```
┌────────────────────────── Godot (game/) ──────────────────────────┐
│ scenes/  node trees      src/  scripts      shaders/  GPU programs │
│ data/    .tres Resources (parameters, asset references)            │
│ assets/  exported files from art-source/                           │
└────────────────────────────────────────────────────────────────────┘
          │ OSC over UDP (from Lesson 04; decisions 0003, 0005)
          ▼
┌──────────────── SuperCollider (audio/supercollider/) ──────────────┐
│ sclang :57120 → synths on scsynth                                   │
└─────────────────────────────────────────────────────────────────────┘
```

Lesson 04 path of one state message:

```
Player ──read──▶ StateReporter ──send()──▶ /root/Osc (OscSender autoload)
 (physics tick)   RateClock.tick()          OscEncoder.encode_message()
                                            PacketPeerUDP → 127.0.0.1:57120
                                                         ▼
                                   sclang OSCdef(\playerState) → ~player
```

Lesson 05 path of one footstep event (decision 0006):

```
Player ──read──▶ FootstepReporter ─────────────────────────────▶ /root/Osc
 (physics tick)   simulated clock: anchor + n·Δt                  send_bundle(tag, [/foot/step ...])
                  GaitClock.advance(distance) → strike, fraction f  OscBundle.encode_bundle()
                  strike time = tick end − (1 − f)·Δt                    ▼
                  SurfaceClassifier.weights_at(feet, floor normal)  sclang OSCdef(\footStep)
                  tag = strike time + latency_seconds                 s.makeBundle(tag − now) → scsynth
                                                                      \stepGrass, \stepDirt, \stepRock
```

Lesson 06 path of emitter positions (decision 0007):

```
listener (Camera3D or CameraPivot) ─┐
SoundEmitter children of Emitters ──┼─read─▶ SpatialReporter ───────────────▶ /root/Osc
Player (height, for the wind) ──────┘         RateClock.tick() at 30 Hz         send_bundle(0, [...])
                                              ListenerMath.spherical_from()           ▼
                                              ListenerMath.unwrap_angle()   sclang OSCdef(\emitterKind)
                                              every 1 s: /emitter/kind       OSCdef(\emitterPos) → one synth per emitter
                                              each send: /emitter/pos, /wind OSCdef(\wind) → \windBed
                                                                             spatialize: Lag → 1/d gain → LPF → PanAz or PanB/DecodeB2
```

There is no return channel yet: nothing in Godot listens on port 9000 (Lesson 04 exercise E5).

## Scene tree: Lessons 00–01 (`scenes/sandbox.tscn`)

```
Sandbox (Node3D, src/sandbox.gd)          spawns the player on the ground; debug keys; HUD text
├── WorldEnvironment                      sky, fog, AgX tonemapping
├── Sun (DirectionalLight3D)
├── Terrain (Node3D, src/terrain/terrain.gd)
│     field    ← data/terrain/sandbox_height_field.tres  (HeightField)
│     material ← data/terrain/terrain_material.tres      (ShaderMaterial → shaders/terrain.gdshader)
│     internal children, rebuilt at load and never saved:
│       MeshInstance3D, StaticBody3D/CollisionShape3D (runtime only)
├── Player (scenes/player.tscn, src/player/player.gd)
│     CollisionShape3D, BodyMesh, CameraPivot/SpringArm3D/Camera3D
└── HUD (CanvasLayer) / Label
```

## Scene tree: Lesson 02 (`scenes/lessons/02_walking_on_a_surface.tscn`)

```
WalkingOnASurface (Node3D, src/lessons/walking_on_a_surface.gd)
│     extends src/sandbox.gd: same spawn, Tab / N keys, HUD; adds T (tick rate),
│     B (blend rule), course placement at ground height, HUD lines
├── WorldEnvironment, Sun                 same values as sandbox.tscn
├── Terrain (Node3D, src/terrain/terrain.gd)
│     field    ← data/terrain/steep_height_field.tres  (hill: A 18 m, σ 10 m; flat plain)
│     material ← data/terrain/terrain_material.tres
├── RampTower (Node3D, src/world/ramp_tower.gd) at (-10, ground, 40)
│     material ← data/terrain/terrain_material.tres
│     internal children: platform and four ramp boxes (44°, 30°, 46°, 55° on +z, +x, -z, -x),
│       Label3D per ramp, StaticBody3D per box (runtime only)
├── StepRow (Node3D, src/world/step_row.gd) at (12, ground, 50), steps along -z
│     material ← data/terrain/terrain_material.tres
│     internal children: boxes of 5, 9, 12, 25 cm, labels, StaticBody3D (runtime only)
├── Player (scenes/player.tscn) at (0, ground + 1, 54)
│     stick_response ← data/input/walk_stick_response.tres
│     steep_slide = true, look_ahead_distance = 4
└── HUD (CanvasLayer) / Label    anchored bottom-left (sandbox.tscn: top-left)
```

## Scene tree: Lesson 03 (`scenes/lessons/03_painting_the_ground.tscn`)

```
PaintingTheGround (Node3D, src/lessons/painting_the_ground.gd)
│     extends src/sandbox.gd: same spawn, Tab / N keys, HUD; adds V (paint_view),
│     C (show_contours), M (tonemapper), F (fog), ColorStrip and RampTower placement,
│     HUD lines; export ramp_tower = RampTower (empty: no placement)
├── WorldEnvironment                      as sandbox.tscn, plus tonemap_white = 6
├── Sun (DirectionalLight3D)              same values as sandbox.tscn
├── Terrain (Node3D, src/terrain/terrain.gd)
│     field    ← data/terrain/sandbox_height_field.tres
│     material ← data/terrain/painted_terrain_material.tres (ShaderMaterial → shaders/terrain_painted.gdshader)
│                  ground_noise ← data/terrain/ground_noise.tres (NoiseTexture2D)
├── RampTower (Node3D, src/world/ramp_tower.gd) at (16, ground, 38)
│     material ← data/terrain/painted_terrain_material.tres (same resource as Terrain)
│     platform 4 m high, 6 m wide; ramps 60°, 45°, 75°, 85° on +z, +x, -z, -x
├── ColorStrip (MeshInstance3D, QuadMesh 4 × 1.5 m) at (-3, ground + 1.5, 33)
│     material ← data/debug/color_ramp_material.tres (ShaderMaterial → shaders/color_ramp.gdshader)
├── Player (scenes/player.tscn) at (0, ground + 1, 40), Lesson 00 defaults
└── HUD (CanvasLayer) / Label    anchored bottom-left, as in the Lesson 02 scene
```

## Scene tree: Lesson 04 (`scenes/lessons/04_osc_bridge.tscn`)

```
OscBridge (Node3D, src/lessons/osc_bridge.gd)
│     extends src/lessons/painting_the_ground.gd: all Lesson 01–03 keys;
│     adds O (state rate: off, 10, 30, 60 Hz) and OSC HUD lines
├── (same nodes as the Lesson 03 scene: WorldEnvironment, Sun, Terrain, ColorStrip, Player;
│     no RampTower, so ramp_tower stays empty)
├── StateReporter (Node, src/audio/player_state_reporter.gd)
│     player = ../Player, send_rate_hz = 30; sends through /root/Osc
└── HUD (CanvasLayer) / Label    anchored top-left
/root/Osc (autoload, src/audio/osc_sender.gd)   exists in every scene; sends only when called
```

## Scene tree: Lesson 05 (`scenes/lessons/05_footsteps.tscn`)

```
Footsteps (Node3D, src/lessons/footsteps.gd)
│     extends src/lessons/osc_bridge.gd: all Lesson 01–04 keys;
│     adds K (step timing: time-tagged / immediate) and footstep HUD lines
├── (same nodes as the Lesson 04 scene: WorldEnvironment, Sun, Terrain, ColorStrip, Player, StateReporter)
├── Footsteps (Node, src/audio/footstep_reporter.gd)
│     player = ../Player
│     surface_material ← data/terrain/painted_terrain_material.tres (same resource as Terrain)
│     timing = TIMETAGGED, latency_seconds = 0.05, step_length = 0.75; sends through /root/Osc
└── HUD (CanvasLayer) / Label    anchored top-left
```

## Scene tree: Lesson 06 (`scenes/lessons/06_spatial_audio.tscn`)

```
SpatialAudio (Node3D, src/lessons/spatial_audio.gd)
│     extends src/lessons/footsteps.gd: all Lesson 01–05 keys;
│     adds L (listener: camera / head) and emitter HUD lines
├── (same nodes as the Lesson 05 scene: WorldEnvironment, Sun, Terrain, ColorStrip, Player, StateReporter, Footsteps)
├── Emitters (Node3D)
│   ├── Crickets  (SoundEmitter, id 0, kind crickets, amp 0.3)    at (−10, 3.5, 30)
│   ├── BirdEast  (SoundEmitter, id 1, kind bird, amp 0.25)       at (14, 8.75, 20)
│   └── BirdNorth (SoundEmitter, id 2, kind bird, amp 0.25)       at (−20, 5.6, −35)
│         each builds an internal marker sphere (never saved)
├── SpatialReporter (Node, src/audio/spatial_audio_reporter.gd)
│     listener = ../Player/CameraPivot/SpringArm3D/Camera3D, player = ../Player, emitters_root = ../Emitters
│     send_rate_hz 30, announce_interval 1, wind_from (1, 0, −0.5), wind 0.3 + 0.05 per meter of height
└── HUD (CanvasLayer) / Label
```

## Scene tree: Lesson 07 (`scenes/lessons/07_sdf_primitives.tscn`)

```
SdfPrimitives (Node3D, src/lessons/sdf_primitives.gd)
│     extends src/lessons/spatial_audio.gd: all Lesson 01–06 keys;
│     places Rocks at ground height; adds G (slice view), H (horizontal cut height),
│     HUD lines (f at the player's feet, Lipschitz bound, slice statistics)
├── (same nodes as the Lesson 06 scene: WorldEnvironment, Sun, Terrain, ColorStrip, Player,
│     StateReporter, Footsteps, Emitters, SpatialReporter)
├── Rocks (Node3D) at (4, ground, 30)          its local space is the shape space of the slices
│   ├── SliceHorizontal (SdfSlice, src/sdf/sdf_slice.gd)  axis Y, origin (1.5, 1.25, 0.3), 10 × 7 m
│   └── SliceVertical   (SdfSlice)                        axis Z, origin (1.5, 2, 0.3), 10 × 5 m
│         shape          ← data/rocks/boulder_pile.tres  (SdfUnion → SdfTransform → SdfDisplace → ...)
│         slice_material ← data/debug/sdf_slice_material.tres (ShaderMaterial → shaders/sdf_slice.gdshader)
│         internal child, rebuilt at load and never saved: MeshInstance3D (QuadMesh, own material copy
│           with an RGF ImageTexture: f, |∇f|)
└── HUD (CanvasLayer) / Label
```

Lesson 07 data flow (decision 0008):

```
data/rocks/boulder_pile.tres ── SdfShape tree ──▶ SdfSlice.rebuild()
  SdfUnion                                          3 evaluate() per texel (plane, ±1 spacing)
   └ SdfTransform (inverse transform on p, × scale)  finite differences → |∇f|
      └ SdfDisplace (+ amplitude · FastNoiseLite)    Image RGF ─▶ ImageTexture ─▶ sdf_slice.gdshader
         └ SdfSmoothUnion (smin) / SdfSubtraction                                (view 0 / 1 / 2)
            └ SdfEllipsoid, SdfBox
```

## Scene tree: Lesson 08 (`scenes/lessons/08_field_to_mesh.tscn`)

```
FieldToMesh (Node3D, src/lessons/field_to_mesh.gd)
│     extends src/lessons/sdf_primitives.gd: all Lesson 01–07 keys;
│     adds R (rock view: mesh / mesh + slices / slices), J (pass 1 on GPU or CPU),
│     writes mesh size and timings into HUD/RockLabel
├── (same nodes as the Lesson 07 scene)
├── Rocks (Node3D) at (4, ground, 30)
│   ├── SliceHorizontal, SliceVertical (SdfSlice)   hidden in rock view 0
│   └── Boulders (SdfMesher, src/sdf/sdf_mesher.gd)
│         shape          ← data/rocks/boulder_pile.tres
│         material       ← data/rocks/rock_material.tres
│         compute_shader ← shaders/compute/surface_nets.glsl (RDShaderFile)
│         internal children, rebuilt at load and never saved:
│           MeshInstance3D (ArrayMesh), StaticBody3D / CollisionShape3D (ConcavePolygonShape3D)
└── HUD (CanvasLayer) / Label, RockLabel
```

Lesson 08 data flow (decision 0009):

```
SdfShape.evaluate() ─▶ SdfGrid.sample()          f at every grid point (PackedFloat32Array), GDScript
                         │
             ┌───────────┴─────────────┐
   use_gpu and device?               otherwise (headless, no shader)
   SurfaceNetsGpu.run()              SurfaceNets.cell_table()
   storage buffers → surface_nets.glsl (one invocation per cell) → read back
             └───────────┬─────────────┘
                 cell table: [x, y, z, has_vertex, nx, ny, nz, 0] per cell
                         ▼
   SurfaceNets.build(): _read_table() → _connect_faces() (one quad per sign-changing edge)
                         ▼
   ArrayMesh ─▶ MeshInstance3D          Mesh.create_trimesh_shape() ─▶ CollisionShape3D
```

## Scene tree: Lesson 09 (`scenes/lessons/09_implicit_curvature.tscn`)

```
ImplicitCurvature (Node3D, src/lessons/implicit_curvature.gd)
│     extends src/lessons/field_to_mesh.gd: all Lesson 01–08 keys;
│     adds U (rock shader view: weathered / H / K / normals),
│     I (mesh normals: trilinear / gradient), two lines in HUD/RockLabel
├── (same nodes as the Lesson 08 scene)
├── Rocks (Node3D)
│   ├── SliceHorizontal, SliceVertical (SdfSlice)
│   └── Boulders (CurvatureMesher, src/sdf/curvature_mesher.gd, extends SdfMesher)
│         material ← data/rocks/weathered_rock_material.tres (shaders/rock_weathering.gdshader)
│         other exports as in Lesson 08
└── HUD / Label, RockLabel (160 px tall)
```

Lesson 09 data flow (decision 0010):

```
SdfMesher.rebuild() (Lesson 08, unchanged) ─▶ nets.positions
   for each vertex: ImplicitCurvature.sample(shape, p, curvature_step)
        26 evaluate() calls ─▶ gradient, Hessian ─▶ n, H, K, k1, k2
   _assemble_mesh(): NORMAL ← gradient or trilinear normals, CUSTOM0 ← (H, K, k1, k2) as RGBA float
        ▼
   rock_weathering.gdshader: vertex() copies CUSTOM0 to a varying; fragment() colors by H
```

## Scene tree: Lesson 10 (`scenes/lessons/10_raymarching.tscn`)

```
Raymarching (Node3D, src/lessons/raymarching.gd)
│     extends src/lessons/implicit_curvature.gd: all Lesson 01–09 keys;
│     adds P (march view: lit / steps / normals / mean H), X (max_steps
│     16, 32, 64, 96, 192), Z (show / hide Formations), one line pair in
│     HUD/RockLabel (frame time); places each formation at
│     terrain height + its scene y
├── (same nodes as the Lesson 09 scene)
├── Formations (Node3D)
│   ├── PileNear (RaymarchVolume, src/sdf/raymarch_volume.gd) boulder_pile.tres at (-9, ground - 0.5, 31)
│   ├── PileFar  (RaymarchVolume) boulder_pile.tres, scale 4, turned 30°, at (-30, ground - 1, -8)
│   └── TorField (RaymarchVolume) distant_tors.tres (SdfRepeat, 3 × 3 tors), scale 2.5, at (26, ground - 0.8, -14)
│         each: template ← shaders/sdf/raymarch.gdshader;
│         internal MeshInstance3D "Proxy" (ArrayMesh box = shape.bounds() grown 0.05 m, no shadow)
└── HUD / Label, RockLabel (200 px tall)
```

Lesson 10 data flow (decision 0011):

```
shape (.tres tree) ─▶ SdfGlsl.translate() ─▶ "uniform sampler3D sdf_noise_k ...; float sdf_map(vec3 p0) {...}"
                   └▶ SdfGlsl.bake_noise_textures(noise_cell) ─▶ ImageTexture3D per FastNoiseLite (RF, 0.1 m)
template raymarch.gdshader (#include sdf_library.gdshaderinc) ─▶ SdfGlsl.splice() ─▶ new Shader
RaymarchVolume: ShaderMaterial(step_scale = 1 / L, proxy_min/max, max_steps, epsilon_pixels, noise uniforms)
   fragment(): ray in the node frame ─▶ slab test against the proxy ─▶ sphere tracing
        hit: tetrahedral normal (h 0.05) and tr(Hf) (h 0.1) ─▶ NORMAL, DEPTH, LIGHT_VERTEX, ALBEDO
        miss: discard
```

## Scene tree: Lesson 11 (`scenes/lessons/11_skeleton_from_code.tscn`)

```
SkeletonFromCode (Node3D, src/lessons/skeleton_from_code.gd)
│     extends src/lessons/raymarching.gd: all Lesson 01–10 keys; adds E
│     (body view: rig / rig + capsule / capsule) and one line in HUD/Label
├── (same nodes as the Lesson 10 scene, except:)
├── Player (scenes/body_player.tscn, src/body/body_player.gd: BodyPlayer extends Player)
│   ├── CollisionShape3D, CameraPivot/...   unchanged from scenes/player.tscn
│   └── BodyMesh                            turned toward travel by Player
│       ├── Capsule, Nose                   hidden (shown by E)
│       └── Rig (BodyRig, src/body/body_rig.gd)
│             proportions ← data/body/default_proportions.tres (BodyProportions)
│             walk_cycle  ← data/body/placeholder_walk.tres    (WalkCycle)
│             material    ← data/body/body_material.tres
│             internal children, rebuilt at load and never saved:
│               Skeleton3D (15 bones) / BoneAttachment3D (one per bone) / MeshInstance3D (17 CapsuleMesh)
└── HUD / Label (one more line), RockLabel
```

Lesson 11 control flow, once per physics tick:

```
Player._physics_process()  (stick → velocity → move_and_slide → facing of BodyMesh)
BodyPlayer: distance = |Δposition| in the ground plane, speed fraction = distance / Δt / walk_speed
BodyRig.advance(): phase += distance / stride_length (mod 1); amount → speed fraction (exponential blend)
WalkCycle.sample(phase, amount) → Pose {bone → Quaternion, hips_offset}
BodyRig.apply_pose(): ForwardKinematics.local_transform(rest, q, offset) → Skeleton3D pose
Skeleton3D: global poses (FK) → BoneAttachment3D → capsule meshes
```

## Scene tree: Lesson 12 (`scenes/lessons/12_feet_on_the_ground.tscn`)

```
FeetOnTheGround (Node3D, src/lessons/feet_on_the_ground.gd)
│     extends src/lessons/skeleton_from_code.gd: all Lesson 01–11 keys; adds Q
│     (leg solver: own IK / TwoBoneIK3D / walk cycle) and Y (foot debug
│     lines); places StepRow; two lines in HUD/RockLabel
├── (same nodes as the Lesson 11 scene, except:)
├── Player (scenes/grounded_player.tscn: a copy of body_player.tscn with
│   │       the Rig script swapped; BodyPlayer unchanged)
│   └── BodyMesh / Rig (FootRig extends BodyRig, src/body/foot_rig.gd)
│         internal children: Skeleton3D / EngineIK (TwoBoneIK3D, active only
│         for solver ENGINE), EngineTargetL/R and EnginePoleL/R (top-level
│         Node3D), FootDebug (top-level MeshInstance3D, ImmediateMesh lines)
├── Footsteps (PlantFootstepReporter extends FootstepReporter,
│             src/audio/plant_footstep_reporter.gd): /foot/step per plant
├── StepRow (Lesson 02 StepRow, steps 0.06 / 0.12 / 0.18 m at (−6, 40),
│            spacing 2 m: a staircase on a hillside that ends in a drop)
└── HUD / Label, RockLabel (two more lines; offset_bottom 252)
```

Lesson 12 control flow, once per physics tick:

```
Player._physics_process() → BodyPlayer: distance, speed fraction
FootRig.advance():
  phase, amount (as BodyRig); WalkCycle.sample() → base pose
  in the air → feet released, base pose; first floor tick → both feet planted under the hips
  per foot: swing_progress(side, phase)
    swing  → landing ray ahead of the hip (lead = stride / 4); ankle = lerp(lift, target, ease) + arc
    strike (phase crosses 0.25 / 0.75) → ray moved back by the rest of the tick → plant → foot_planted(side, point, normal, fraction)
    stance → ankle fixed in world space; replanted when 0.9 m from home
  pelvis: lowest of target.y + sqrt(R² − h²) per foot, R = 0.98 (thigh + shin), clamp −0.35 m
  OWN: TwoBoneIk.solve() → leg_bases() → local quaternions; foot_basis(normal, heading)
  ENGINE: targets and poles to EngineTarget / EnginePole; TwoBoneIK3D turns thigh and shin during the skeleton update
  BodyRig.apply_pose()
PlantFootstepReporter._physics_process() (later in the tree): queued plants → /foot/step at tick_end − (1 − fraction) Δt + latency
```

## Scene tree: Lesson 13 (`scenes/lessons/13_balance.tscn`)

```
Balance (Node3D, src/lessons/balance.gd)
│     extends src/lessons/feet_on_the_ground.gd: all Lesson 01–12 keys; adds
│     1 (balance lines), 2 / Shift+2 (push right / left), 3 / Shift+3 (push
│     forward / back); two lines in HUD/RockLabel
├── (same nodes as the Lesson 12 scene)
├── BalanceMonitor (BalanceMonitor, src/body/balance_monitor.gd)
│     rig = Player/BodyMesh/Rig, masses = data/body/winter_segment_masses.tres
│     process_physics_priority −1 (ticks before Player)
│     internal child: BalanceDebug (top-level MeshInstance3D, ImmediateMesh)
└── HUD / Label, RockLabel (offset_bottom 304)
```

Lesson 13 control flow, once per physics tick:

```
BalanceMonitor._physics_process() (priority −1, before Player):
  measure(): bone poses of the last tick → segment centers → c (CenterOfMass)
             feet in contact (planted, or sole within 0.02 m of a ray hit) → 4 sole corners each
             → ground coordinates (x, −z) → SupportPolygon.convex_hull() → signed_distance(c) = margin
             → next_state() (none / stable / marginal / outside, hysteresis)
  OSC: /body/balance/state on change; /body/balance at 30 Hz (RateClock)
  SwayPendulum.step() → Rig.position = rest + (s.x, 0, −s.y) inside BodyMesh
  debug lines
Player._physics_process() → FootRig.advance() (Lesson 12) solves the legs with the rig moved
```

## Scene tree: Lesson 14 (`scenes/lessons/14_analog_stances.tscn`)

```
AnalogStances (Node3D, src/lessons/analog_stances.gd)
│     extends src/lessons/balance.gd: all Lesson 01–13 keys; adds 4 (stance),
│     5 / 6 (weight left / right, held), 7 (smoothing), 8 (radial / axial
│     stick deadzone), 9 (60 / 120 ticks per second); five lines in
│     HUD/RockLabel. Export axial_stick_response = data/input/walk_stick_axial.tres
├── (same nodes as the Lesson 13 scene)
│     Player: stick_response = data/input/walk_stick_response.tres (Lesson 02)
├── BalanceMonitor (Lesson 13, priority −1)
├── Stance (StanceController, src/body/stance_controller.gd)
│     monitor = BalanceMonitor, player = Player,
│     trigger_response = data/input/trigger_response.tres
│     process_physics_priority −1, after BalanceMonitor in the tree
└── HUD / Label, RockLabel (offset_bottom 408)
```

Lesson 14 control flow, once per physics tick:

```
BalanceMonitor._physics_process() (priority −1): measure, OSC, Rig.position = rest + sway
StanceController._physics_process() (priority −1, later in the tree):
  read_input(): Input.get_action_raw_strength(shift_weight_left / _right) (deadzone 0)
                → TriggerResponse.apply() each → shift target x = (R − L) · side_range
                Player.stick_shaped (last tick) → shift target y = |stick| · forward_lean
  update(): NONE / OnePoleFilter / CriticalSpring.step() / step_euler() on shift and crouch
  apply_to_rig(): Rig.position += (shift.x, −crouch, −shift.y)
Player._physics_process() → StickResponse (radial or axial) → FootRig.advance() solves the legs
```

## Scene tree: Lesson 15 (`scenes/lessons/15_climbing.tscn`)

```
Climbing (Node3D, src/lessons/climbing.gd)
│     extends src/lessons/analog_stances.gd: all Lesson 01–14 keys; adds
│     0 / Start (climb, let go), F1 (holds and climbing lines), F2 (arm
│     solver); five lines in HUD/RockLabel; places ClimbFace on the
│     terrain and turns the camera toward it in _ready()
├── (same nodes as the Lesson 14 scene, with these differences)
│     Player: scenes/climbing_player.tscn (ClimbingPlayer, FootRig rig)
├── ClimbFace (ClimbableRock, src/climb/climbable_rock.gd)
│     shape = data/rocks/climbing_face.tres, weathered material, cell 0.08
│     ground = Terrain (holds less than 0.05 m above it are left out)
│     at (5.5, terrain, 47.5), turned 180° about y (face toward the spawn)
│     internal children: mesh, collision (Lesson 08), HoldMarks (lines)
├── BalanceMonitor (ClimbBalanceMonitor, src/climb/climb_balance_monitor.gd)
│     rig, masses as in Lesson 13; climb = Climb
├── Stance (Lesson 14)
├── Climb (ClimbController, src/climb/climb_controller.gd)
│     player = Player, rock = ClimbFace, stance = Stance
│     priority 0, after Player in the tree
│     internal child: ClimbDebug (top-level MeshInstance3D, ImmediateMesh)
└── HUD / Label, RockLabel (offset_bottom 520)
```

Lesson 15 control flow:

```
ClimbFace.rebuild() (load, or a change of shape or cell):
  SdfMesher + CurvatureMesher (Lessons 08–09): mesh, collision, per-vertex n, H
  find_holds() (also after a change of a hold threshold):
    HoldFinder.candidates(): 3 ≤ H ≤ 40, n·up ≥ 0.3, n·face ≥ 0.2 → sorted by H (n·up)
    HoldFinder.suppress(): one per 0.2 m
    HoldFinder.refine(): two Newton steps onto f = 0, ImplicitCurvature.sample(),
                         tests again with ‖∇f‖ ≥ 0.5; knob or edge
    _below_top(): SphereTracer ray down from behind the hold → top_out
    holds in shape space (local_holds) → world space (holds), less those
      less than ground_clearance 0.05 m above Terrain.height_at()
      (again whenever the node moves)

Key 0 → ClimbController.begin_climb(): approach tests → hands on holds in reach,
        feet on the ground; ClimbingPlayer.climbing = true

Once per physics tick while climbing:
  BalanceMonitor (ClimbBalanceMonitor, priority −1): Lesson 13 measure, then the
        polygon of all held contacts and hand_pull = d / h; OSC as Lesson 13
  StanceController (priority −1): shift and crouch as Lesson 14
  Player (ClimbingPlayer): camera and stick only
  Climb (priority 0, after Player):
    one limb in REACH or MOVE, or: a trigger starts a REACH, both hands on
    top-outs start the mantle, or _plan_feet() starts a foot MOVE
    REACH: stick → aim velocity → CriticalSpring → hand point; candidate =
           nearest hold in reach within 0.3 m; trigger released → MOVE
    _solve_pelvis(): ReachSolver.solve(preferred pelvis, balls of HOLD and
           MOVE limbs, half-space) → OnePoleFilter → ReachSolver.solve() again
    _place_body(): capsule under the pelvis, BodyMesh faces the rock
    _pose(): TwoBoneIk legs; TwoBoneIk or Fabrik arms → BodyRig.apply_pose()
  MANTLING: eased up-and-over ramps (1.2 s) → walking
```

## Scene tree: Lesson 16 (`scenes/lessons/16_crawling_and_scrambling.tscn`)

```
CrawlingAndScrambling (Node3D, src/lessons/crawling_and_scrambling.gd)
│     extends src/lessons/climbing.gd: all Lesson 01–15 keys; adds F3 / Guide
│     (crawl, rise from a crawl), F4 (collision shape and crawl lines); key 0
│     refused ("not upright") while crawling or scrambling; four lines in
│     HUD/RockLabel; places CrawlGap and Slab on the terrain, turns the camera
│     toward the gap's entrance in _ready()
├── (same nodes as the Lesson 15 scene, with these differences)
│     Player: scenes/crawling_player.tscn (CrawlingPlayer, FootRig rig)
├── CrawlGap (CrawlGap, src/world/crawl_gap.gd, @tool BoxCourse)
│     roof 0.9 m, width 1.1 m, roof 2.4 m long, aprons 1.2 m, ramps 15°
│     at (−7, highest terrain under the floor, 52), course along x
│     internal children: boxes, collision at runtime, label "0.90 m"
├── Slab (RampTower, Lesson 02)
│     platform 2 m high, 3 m wide; ramps 48° (+x, toward the gap), 60°, 35°
│     (−x, the way down), 85°; at (−15.5, terrain at the 48° ramp's foot, 52)
├── BalanceMonitor (CrawlBalanceMonitor, src/crawl/crawl_balance_monitor.gd)
│     rig, masses, climb as in Lesson 15; crawl = Crawl
├── Stance (PostureController, src/crawl/posture_controller.gd)
│     monitor, player, trigger_response as in Lesson 14; climb = Climb
├── Climb (Lesson 15)
├── Crawl (CrawlController, src/crawl/crawl_controller.gd)
│     player = Player, posture = Stance, monitor = BalanceMonitor
│     priority 0, after Player (and Climb) in the tree
│     internal child: CrawlDebug (top-level MeshInstance3D, ImmediateMesh)
└── HUD / Label, RockLabel (offset_bottom 616)
```

Lesson 16 control flow, once per physics tick:

```
BalanceMonitor (CrawlBalanceMonitor, priority −1): Lesson 13 measure; while
      crawling or scrambling, the polygon of Crawl.contact_points()
Stance (PostureController, priority −1): Lesson 14 shift and crouch; while
      climbing nothing more (key 4 toggles only the Lesson 14 stance); else
      an upright posture follows the stance (after a climb), then the
      automatic scramble: CrawlingPlayer.ground_ahead() 0.6 m along the stick
      → slope in (45°, 55°] and a rise or drop over 0.05 m → request(SCRAMBLE);
      walkable under and ahead (< 40°) → back to the posture before it
      request(): CrawlingPlayer.fits(shape) (intersect_shape 0.02 m up)
                 → set_body_shape(), mode, /body/posture; or refusal
Player (CrawlingPlayer): UPRIGHT → Lesson 00–15 walking (ClimbingPlayer);
      CRAWL / SCRAMBLE → _low_move(): turn (crawl: only if the turned shape
      fits; scramble: up the slope), speed × speed_scale, move_and_slide()
Climb (Lesson 15)
Crawl (CrawlController, while the mode is low):
  contact normal → phase += (distance + turn arc) / stride
  _test_lift(): SupportPolygon margin of the other three contacts ≥ 0,
      else wait (speed_scale 0) up to 1 s
  limbs: swing on an eased arc to a ray hit ahead of the home point, or stand
  shift (CriticalSpring ±0.08 m), lean up the slope, pelvis and shoulders
  _pose(): TwoBoneIk arms (and scrambling legs), kneeling legs → apply_pose()
  every tick: pose blend after a posture change (0.4 s), debug lines
```

## Scene tree: Lesson 17 (`scenes/lessons/17_writing_light.tscn`)

```
WritingLight (Node3D, src/lessons/writing_light.gd)
│     extends src/lessons/crawling_and_scrambling.gd: all Lesson 01–16 keys;
│     adds F5 (shading mode), F6 (term), F7 (HUD labels); export
│     start_pitch_degrees −15; turns the camera toward Gallery; hides
│     HUD/Label and HUD/RockLabel at the start
├── (same nodes as the Lesson 16 scene, with these differences)
│     Player at (14.2, 0, 42)
├── Gallery (ShadingGallery, src/render/shading_gallery.gd, @tool)
│     at (12, row height 2.57, 37.5), rotated 26° about y (the sun comes
│     from the viewer's left); light_include custom_light.gdshaderinc,
│     rock_shape gallery_rock.tres, rock_material weathered_rock_material,
│     tile_field gallery_tile_field.tres, tile_material
│     painted_terrain_material, ground = Terrain
│     internal children, per column (built-in, Lambert, wrap, Oren–Nayar,
│     GGX, 2.7 m apart): Terrain tile 2.4 m, plinth box, rock (column 0:
│     CurvatureMesher; 1–4: MeshInstance3D sharing its mesh), Label3D,
│     runtime collision
├── BalanceMonitor, Stance, Climb, Crawl (Lesson 16)
├── Shading (ShadingSwitch, src/render/shading_switch.gd)
│     light_include custom_light.gdshaderinc; targets Terrain,
│     Rocks/Boulders, ClimbFace
└── HUD / Label, RockLabel (hidden at start), LightLabel (bottom left)
```

Lesson 17 path of one pixel of the switched terrain:

```
Shading.set_mode(m) ─▶ Terrain.material = lit copy (LitShader.material():
                       terrain_painted.gdshader code + #include custom_light)
                       light_model = m − 1, light_term = F6
GPU, per pixel:  fragment()  (Lesson 03, unchanged) → ALBEDO, ROUGHNESS, NORMAL
                 light()     once per light (custom_light.gdshaderinc →
                             brdf.gdshaderinc) → DIFFUSE_LIGHT, SPECULAR_LIGHT
                 Godot:      diffuse × ALBEDO × (1 − METALLIC) + specular
                             + ambient + sky reflections → fog → tonemap
Mode BUILT_IN:   the original material, no light(): Godot's Lambert + GGX
```

## Modules

| Module | Files | Provides | Used by | Lesson |
|---|---|---|---|---|
| Height field | `src/terrain/height_field.gd` | `HeightField` Resource: `height(p)`, `gradient(p)`, `normal(p)`; emits `changed` | `Terrain`, `sandbox.gd` | 01 |
| Terrain | `src/terrain/terrain.gd` | `Terrain` node: mesh and collision from a `HeightField`; `height_at(x, z)`; `NormalMethod` enum; `rebuild()` | `sandbox.gd` | 01 |
| Terrain shader | `shaders/terrain.gdshader` | Slope and height coloring; `debug_view` uniform (0 lit, 1 normals, 2 slope) | `data/terrain/terrain_material.tres` | 01 |
| Player | `src/player/player.gd`, `scenes/player.tscn` | `Player` (CharacterBody3D): analog walking relative to camera, orbit camera, mouse capture | `sandbox.gd` | 00 |
| Player, Lesson 02 options | `src/player/player.gd` | Exports `stick_response`, `blend_rule`, `steep_slide`, `look_ahead_distance` / `_gain` / `_responsiveness` (defaults keep Lesson 00 behavior); enums `BlendRule`, `GroundState`; `static blend_factor(rate, delta, rule)`; `get_ground_state()`; public vars `stick_raw`, `stick_shaped` (written each tick by `_read_stick()`) | `walking_on_a_surface.gd`, tests | 02 |
| Sandbox | `src/sandbox.gd` | Spawn placement, view and normal-method cycling, HUD text | `scenes/sandbox.tscn`; extended by `walking_on_a_surface.gd`, `painting_the_ground.gd` | 01 |
| Stick response | `src/input/stick_response.gd` | `StickResponse` Resource: `apply(raw: Vector2) -> Vector2`, `shape(magnitude) -> float`; inner and outer deadzone, exponent, optional `Curve` | `Player.stick_response` | 02 |
| Box courses | `src/world/box_course.gd`, `ramp_tower.gd`, `step_row.gd` | `BoxCourse` base (`_build()`, `_add_box()`, `_add_label()`, `rebuild()`); `RampTower` (`platform_height`, `platform_size`, `ramp_angles_degrees` for +z, +x, -z, -x); `StepRow` (`step_heights`, `spacing`, `step_size`) | Lesson 02 scene, `test_02_ground.gd`; `RampTower` also in the Lesson 03 scene | 02 |
| Lesson 02 root | `src/lessons/walking_on_a_surface.gd` | Course placement, tick-rate and blend-rule keys, HUD lines | `scenes/lessons/02_walking_on_a_surface.tscn` | 02 |
| Painted terrain shader | `shaders/terrain_painted.gdshader` | Triplanar noise, noise-shifted slope and height rules, contour lines (`fract` + `fwidth`); uniforms `debug_view` (0–2, as `terrain.gdshader`), `paint_view` (0 painted, 1 triplanar weights, 2 noise triplanar, 3 noise top-down), `show_contours`, `contour_interval`, `triplanar_sharpness`, ... | `data/terrain/painted_terrain_material.tres` | 03 |
| Color strip shader | `shaders/color_ramp.gdshader` | Unshaded bands: linear 0–1, sRGB-decoded 0–1, HDR 0–`hdr_max` with ticks | `data/debug/color_ramp_material.tres` | 03 |
| Paint math | `src/render/paint_math.gd` | `PaintMath` (static): `srgb_to_linear()`, `linear_to_srgb()`, `triplanar_weights(n, k)`, `contour_distance(h, interval)`, `contour_index(h, interval)`; CPU copies of shader formulas | `painting_the_ground.gd`, tests | 03 |
| OSC encoder | `src/audio/osc_encoder.gd` | `OscEncoder` (static): `encode_message(address, args) -> PackedByteArray` (types i, f, s), `type_tags()`, `padded_string()`, `padded_length()` | `OscSender`, tests | 04 |
| OSC sender | `src/audio/osc_sender.gd` | `OscSender` (Node), autoload `Osc`: `send(address, args) -> bool`, `set_destination(host, port)`, `enabled`, counters `messages_sent`, `bytes_sent`; unconnected `PacketPeerUDP` | `PlayerStateReporter`, `osc_bridge.gd`, `tools/godot/osc_send.gd` | 04 |
| Rate clock | `src/audio/rate_clock.gd` | `RateClock`: `rate_hz`, `tick(delta) -> bool`; at most one send per tick, backlog dropped | `PlayerStateReporter`, `SpatialAudioReporter`, tests | 04 |
| Player state reporter | `src/audio/player_state_reporter.gd` | `PlayerStateReporter` (Node): exports `player`, `send_rate_hz`; var `sender`; sends `/player/state ffffi` (x y z speed ground) at the rate and `/player/ground s` on change; `static state_arguments(player)` | Lesson 04 scene | 04 |
| Lesson 04 root | `src/lessons/osc_bridge.gd` | O key (`cycle_osc_rate`), OSC HUD lines | `scenes/lessons/04_osc_bridge.tscn` | 04 |
| OSC bundle | `src/audio/osc_bundle.gd` | `OscBundle` (static): `timetag_bytes(unix_seconds)` (NTP 32.32; ≤ 0 gives "immediately"), `timetag_to_unix(bytes)`, `encode_bundle(unix_seconds, messages)`; const `NTP_UNIX_OFFSET` | `OscSender.send_bundle()`, tests | 05 |
| OSC sender, Lesson 05 addition | `src/audio/osc_sender.gd` | `send_bundle(unix_seconds, [[address, args], ...]) -> bool`; counter `bundles_sent` (each element also counts in `messages_sent`) | `FootstepReporter`, `SpatialAudioReporter` | 05 |
| Gait clock | `src/audio/gait_clock.gd` | `GaitClock`: `step_length`, `phase`, `advance(distance) -> bool`, `strike_fraction`, `last_foot()`; at most one strike per call | `FootstepReporter`, tests | 05 |
| Surface classifier | `src/audio/surface_classifier.gd` | `SurfaceClassifier`: `read_material(ShaderMaterial)`, `weights_at(position, normal) -> Vector3` (grass, dirt, rock), `rockiness()`, `dirtiness()`, `noise_at()`, `has_noise()`; static `surface_weights(r, d)`, `dominant(w)`, `slope_degrees(n)`, `sample_bilinear(image, uv)`; enum `Surface`; CPU copy of the rules in `terrain_painted.gdshader` | `FootstepReporter`, `footsteps.gd`, tests | 05 |
| Footstep reporter | `src/audio/footstep_reporter.gd` | `FootstepReporter` (Node): exports `player`, `surface_material`, `timing` (enum `Timing` IMMEDIATE / TIMETAGGED), `latency_seconds`, `step_length`, `foot_offset`, `max_clock_drift`; vars `sender`, `gait`, `classifier`, `steps_sent`, `last_arguments`, `last_event_time`, `clock_lag`, `clock_resets`; static `step_arguments()`, `signed_slope_degrees(n, direction)`; sends `/foot/step ifffff` | Lesson 05 scene, `tools/godot/walk_steps.gd` | 05 |
| Lesson 05 root | `src/lessons/footsteps.gd` | K key (`toggle_step_timing`), footstep HUD lines | `scenes/lessons/05_footsteps.tscn` | 05 |
| Listener math | `src/audio/listener_math.gd` | `ListenerMath` (static): `to_listener_space(listener, point)`, `spherical(local) -> Vector3(azimuth, elevation, distance)` (az 0 ahead, + right; el + up; radians), `spherical_from(listener, point)`, `direction_azimuth(listener, direction)`, `unwrap_angle(previous, angle)` | `SpatialAudioReporter`, tests | 06 |
| Sound emitter | `src/audio/sound_emitter.gd` | `SoundEmitter` (`@tool` Node3D): exports `emitter_id`, `kind` (SynthDef name), `amp`, `show_marker`; internal marker sphere | Lesson 06 scene | 06 |
| Spatial audio reporter | `src/audio/spatial_audio_reporter.gd` | `SpatialAudioReporter` (Node): exports `listener`, `player`, `emitters_root`, `send_rate_hz`, `announce_interval`, `wind_from`, `wind_base`, `wind_per_meter`, `wind_reference_height`; vars `sender`, `last_spherical` (id → Vector3), `wind_strength`, `wind_azimuth`, `sends`, `announcements`; static `wind_strength_at()`; sends `/emitter/kind isf`, `/emitter/pos ifff`, `/wind ff` in bundles tagged "immediately" | Lesson 06 scene | 06 |
| Lesson 06 root | `src/lessons/spatial_audio.gd` | L key (`toggle_listener`), listener, wind, and emitter HUD lines | `scenes/lessons/06_spatial_audio.tscn` | 06 |
| SDF shapes | `src/sdf/sdf_shape.gd` and the files below | `SdfShape` Resource: `evaluate(p) -> float` (negative inside), `lipschitz_bound()`, `bounds() -> AABB`, `level_bounds(level) -> AABB`, `evaluate_bounded(p)`, `gradient(p, h)`; `_watch()` re-emits children's `changed`; static `merged_bounds()`, `merged_level_bounds()` | `SdfSlice`, tests; Lesson 08 meshing | 07 |
| SDF primitives | `src/sdf/sdf_sphere.gd`, `sdf_box.gd`, `sdf_capsule.gd`, `sdf_ellipsoid.gd` | `SdfSphere` (center, radius), `SdfBox` (center, half_extents, rounding), `SdfCapsule` (a, b, radius): exact. `SdfEllipsoid` (center, radii, rotation_degrees, `estimate`: `SCALED_SPHERE` bound 1, default; `GRADIENT` bound `INF`) | rock `.tres` files | 07 |
| SDF operators | `src/sdf/sdf_union.gd`, `sdf_smooth_union.gd`, `sdf_intersection.gd`, `sdf_subtraction.gd`, `sdf_transform.gd`, `sdf_repeat.gd`, `sdf_displace.gd` | `SdfUnion` (`shapes`), `SdfSmoothUnion` (`shapes`, `blend`; static `smin(a, b, k)`), `SdfIntersection` (`shapes`), `SdfSubtraction` (`base`, `cutter`), `SdfTransform` (`shape`, `translation`, `rotation_degrees`, uniform `scale`), `SdfRepeat` (`shape`, `period`, `count`), `SdfDisplace` (`shape`, `noise`: FastNoiseLite, `amplitude`, `noise_slope_per_frequency`) | rock `.tres` files | 07 |
| SDF slice | `src/sdf/sdf_slice.gd`, `shaders/sdf_slice.gdshader` | `SdfSlice` (`@tool` Node3D): exports `shape`, `slice_material`, `axis` (enum X/Y/Z), `origin`, `size`, `resolution`, `view`; `rebuild()`, `plane_basis()`, `grid_size()`, `texel_point(i, j)`; vars `image` (RGF: f, ‖∇f‖), `sample_count`, `build_milliseconds`, `smallest_value`, `smallest_gradient`, `largest_gradient` | Lesson 07 scene | 07 |
| Lesson 07 root | `src/lessons/sdf_primitives.gd` | Rocks placement; G (`cycle_slice_view`), H (`step_slice`); HUD lines | `scenes/lessons/07_sdf_primitives.tscn` | 07 |
| SDF grid | `src/sdf/sdf_grid.gd` | `SdfGrid` (RefCounted): static `sample(shape, cell)` (covers `bounds()` plus one spare layer), `fill(shape)`, `index()`, `point()`, `value()`, `cell_count()`; vars `origin`, `cell_size`, `dims`, `values` (PackedFloat32Array, x fastest), `sample_milliseconds` | `SdfMesher`, tests, `tools/godot/mesher_compare.gd` | 08 |
| Surface nets | `src/sdf/surface_nets.gd` | `SurfaceNets` (RefCounted): `CELL_FLOATS` 8, `EDGES`; static `edge_crossing(f0, f1)`, `is_inside(f)`, `cell_table(grid)`, `trilinear_gradient(f, u, v, w)`; `build(grid, table = [])`, `triangle_count()`, `mesh_arrays()`; vars `positions`, `normals`, `indices`, `cell_vertex`, `vertex_milliseconds`, `face_milliseconds` | `SdfMesher` | 08 |
| Surface nets on the GPU | `src/sdf/surface_nets_gpu.gd`, `shaders/compute/surface_nets.glsl` | `SurfaceNetsGpu` (RefCounted): `_init(shader_file: RDShaderFile)` creates a local `RenderingDevice`; `is_available()`; `run(grid) -> PackedFloat32Array` (cell table, empty without a device); `GROUP` 4 (matches `local_size`); vars `upload_milliseconds`, `dispatch_milliseconds`, `download_milliseconds` | `SdfMesher` | 08 |
| SDF mesher | `src/sdf/sdf_mesher.gd` | `SdfMesher` (`@tool` Node3D): exports `shape`, `material`, `cell_size` (0.15), `compute_shader`, `use_gpu` (true), `build_collision` (true); `rebuild()`, `gpu_available()`, `vertex_count()`, `triangle_count()`; vars `grid`, `nets`, `used_gpu`, `sample_milliseconds`, `vertex_milliseconds`, `face_milliseconds`, `collision_milliseconds`, `total_milliseconds` | Lesson 08 scene | 08 |
| Lesson 08 root | `src/lessons/field_to_mesh.gd` | R (`cycle_rock_view`), J (`toggle_mesher_backend`); `HUD/RockLabel` | `scenes/lessons/08_field_to_mesh.tscn` | 08 |
| SDF torus | `src/sdf/sdf_torus.gd` | `SdfTorus` (center, `major_radius`, `minor_radius`; axis y; exact); `analytic_gradient(p)` (ZERO on the axis and the core circle) | tests | 09 |
| Implicit curvature | `src/sdf/implicit_curvature.gd` | `ImplicitCurvature` (static): `DEFAULT_STEP` 0.01; `hessian(shape, p, h) -> Basis`, `mean_curvature(g, hess)` (H = ½ div n, +1/r on a sphere), `gaussian_curvature(g, hess)` (Goldman Eq. 4.1), `principal_curvatures(H, K) -> Vector2`, `sample(shape, p, h) -> Sample` (value, gradient, hessian, normal, mean, gaussian, k1, k2; 26 evaluations), `torus_curvatures(R, r, theta) -> Vector2(H, K)` | `CurvatureMesher`, tests | 09 |
| Curvature mesher | `src/sdf/curvature_mesher.gd`, `shaders/rock_weathering.gdshader` | `CurvatureMesher` (`@tool`, extends `SdfMesher`): enum `NormalSource` {TRILINEAR, GRADIENT}; exports `normal_source` (GRADIENT; re-assembles without resampling), `curvature_step` (0.01); vars `gradient_normals`, `mean_curvatures`, `gaussian_curvatures`, `curvature_milliseconds`; `normal_angle_stats() -> Vector2(mean, max)` degrees. Mesh `CUSTOM0` = (H, K, k1, k2), `ARRAY_CUSTOM_RGBA_FLOAT`. Shader uniforms `curvature_view` (0 weathered, 1 H, 2 K, 3 normals), colors, `wear_start`/`wear_full`, `cavity_start`/`cavity_full` (1/m), `dust_facing`, `dust_amount`, `map_scale` | Lesson 09 scene | 09 |
| Lesson 09 root | `src/lessons/implicit_curvature.gd` | U (`cycle_curvature_view`), I (`toggle_normal_source`); two lines appended to `HUD/RockLabel` | `scenes/lessons/09_implicit_curvature.tscn` | 09 |
| SDF to GLSL | `src/sdf/sdf_glsl.gd`, `shaders/sdf/sdf_library.gdshaderinc` | `SdfGlsl` (RefCounted): `translate(shape) -> String` (noise uniforms + `float sdf_map(vec3 p0)`; one line per node; vars `noises`, `noise_regions`, `unsupported`, `node_count`), static `splice(template_code, map_code)` (replaces `// SDF_MAP_BEGIN` … `// SDF_MAP_END`), `bake_noise_textures(cell)` (vars `noise_textures`, `noise_cells`, `noise_dims`, `bake_milliseconds`), static `bake_noise_slices(noise, region, cell) -> Array[Image]` (FORMAT_RF), `noise_uniforms() -> Dictionary`. Library functions `sdf_sphere`, `sdf_box`, `sdf_capsule`, `sdf_ellipsoid_scaled`, `sdf_ellipsoid_gradient`, `sdf_torus`, `sdf_smin`, `sdf_noise` (trilinear texture), constant `SDF_FAR` 1e30. Translates every class of `src/sdf/` that is an `SdfShape` | `RaymarchVolume`, tests | 10 |
| Raymarch volume | `src/sdf/raymarch_volume.gd`, `shaders/sdf/raymarch.gdshader` | `RaymarchVolume` (`@tool` Node3D): exports `shape`, `template`, `noise_cell` (0.1), `max_steps` (96), `epsilon_pixels` (0.5), `debug_view` (0 lit, 1 steps, 2 normals, 3 mean H); vars `material`, `generated_code`, `lipschitz` (INF → 2 with a warning), `proxy_bounds` (bounds() grown 0.05), `build_milliseconds`, `bake_milliseconds`, `node_count`; `rebuild()`. Shader uniforms `debug_view`, `max_steps`, `epsilon_pixels`, `step_scale`, `proxy_min`, `proxy_max`, `normal_step` (0.05), `curvature_step` (0.1), the Lesson 09 weathering colors and thresholds; `render_mode cull_front`; writes `DEPTH`, `NORMAL`, `LIGHT_VERTEX` | Lesson 10 scene | 10 |
| Sphere tracer (CPU) | `src/sdf/sphere_tracer.gd` | `SphereTracer` (static): `trace(shape, origin, direction, max_steps, tolerance, t_start, t_end, lipschitz = 1, floor_tolerance = 1e-5) -> Result` (`hit`, `t`, `steps`, `last_value`); `box_interval(box, origin, direction) -> Vector2` | tests, exercises | 10 |
| Lesson 10 root | `src/lessons/raymarching.gd` | P (`cycle_raymarch_view`), X (`cycle_march_budget`), Z (`toggle_formations`); `frame_milliseconds` (moving average of the frame time); places `Formations` children on the terrain | `scenes/lessons/10_raymarching.tscn` | 10 |
| Body proportions | `src/body/body_proportions.gd` | `BodyProportions` Resource: lengths and radii; `hip_height()`, `standing_height()` (1.74 m), `bone_specs()` (15 bones: name, parent index, rest offset, capsule segments; identity rest rotations; facing −z, left −x) | `BodyRig`, tests | 11 |
| Forward kinematics | `src/body/forward_kinematics.gd` | `ForwardKinematics` (static): `local_transform(rest, rotation, offset)` = (rest.basis · Basis(q), rest.origin + offset); `global_transforms(parents, locals)` (parents first); `rotate(q, v)` = v + 2w(u×v) + 2u×(u×v) | `BodyRig`, tests | 11 |
| Walk cycle | `src/body/walk_cycle.gd` | `WalkCycle` Resource: `stride_length` 1.4, hip 24°, knee 45°, arm 18°, elbow 15°, pelvis yaw 6°, chest counter-yaw 10°, bob 0.025 m; `sample(phase, amount) -> Pose` (`rotations` {bone: Quaternion}, `hips_offset`); static `pitch()`, `yaw()` | `BodyRig` | 11 |
| Body rig | `src/body/body_rig.gd` | `BodyRig` (`@tool` Node3D): exports `proportions`, `walk_cycle`, `material`, `amount_responsiveness` 6; `rebuild()`, `skeleton()`, `advance(distance, speed_fraction, delta)`, `apply_pose(pose or null)`; vars `phase`, `amount`, `build_milliseconds`, `pose_milliseconds` | `BodyPlayer` | 11 |
| Body player | `src/body/body_player.gd`, `scenes/body_player.tscn` | `BodyPlayer` (extends `Player`): enum `BodyView` {RIG, RIG_CAPSULE, CAPSULE}; vars `body_view`, `ground_speed`, `rig`; feeds the rig with the measured ground-plane motion | Lesson 11 scene | 11 |
| Lesson 11 root | `src/lessons/skeleton_from_code.gd` | E (`toggle_body_view`); body line in `HUD/Label` | `scenes/lessons/11_skeleton_from_code.tscn` | 11 |
| Two-bone IK | `src/body/two_bone_ik.gd` | `TwoBoneIk` (static): `solve(root, target, pole, a, b) -> Solution` (`root`, `middle`, `end`, `reached`, `root_angle`, `middle_angle`; law of cosines, pole by Gram–Schmidt, distance clamped to [\|a − b\|, a + b] less `STRAIGHT_MARGIN` 1e-4); `leg_bases(solution, pole) -> [upper, lower]` (−y along the bone, +x the hinge u × v); `foot_basis(normal, heading)`; `limit_tilt(normal, max_degrees)` | `FootRig`, tests | 12 |
| Foot rig | `src/body/foot_rig.gd`, `scenes/grounded_player.tscn` | `FootRig` (`@tool`, extends `BodyRig`): signal `foot_planted(side, point, normal, tick_fraction)`; enum `Solver` {WALK_CYCLE, OWN, ENGINE}; exports `solver`, `step_height` 0.10, `lead_fraction` 0.25, `replant_distance` 0.9, `ray_up` 0.6, `ray_down` 0.6, `ground_mask`, `reach_fraction` 0.98, `max_pelvis_drop` 0.35, `pelvis_responsiveness` 15, `max_foot_tilt_degrees` 30, `debug_draw`; vars `feet` (Array[FootState]: `planted`, `ankle`, `normal`, `contact`, `lift_*`, `target_*`, `swing`), `pelvis_offset`, `ankle_errors`, `ik_milliseconds`, `ray_count`; `home_point(side)`, `ground_ray(point)`, `ankle_target(side)`, static `swing_progress(side, phi)`, `swing_ease(u)` | Lesson 12 scene | 12 |
| Plant footsteps | `src/audio/plant_footstep_reporter.gd` | `PlantFootstepReporter` (extends `FootstepReporter`): queues `foot_planted`, sends `/foot/step` (same format) with the contact point's surface weights, the hit normal's slope, and the sub-tick strike time; landings as in Lesson 05; falls back to the gait clock when the rig is not a `FootRig` or its solver is WALK_CYCLE | Lesson 12 scene | 12 |
| Lesson 12 root | `src/lessons/feet_on_the_ground.gd` | Q (`cycle_foot_solver`), Y (`toggle_foot_debug`); places `StepRow` by the height at its first front edge; two lines in `HUD/RockLabel` | `scenes/lessons/12_feet_on_the_ground.tscn` | 12 |
| Segment masses | `src/body/segment_masses.gd`, `data/body/winter_segment_masses.tres` | `SegmentMasses` (`@tool` Resource): Winter Table 4.1 fractions and ratios (head-neck, trunk, upper arm, forearm-hand, thigh, shank, foot), `body_mass`; `segments(proportions)` → Array[Dictionary] {name, proximal_bone/point, distal_bone/point, fraction, ratio}; `total_fraction()` | `BalanceMonitor` | 13 |
| Center of mass | `src/body/center_of_mass.gd` | `CenterOfMass` (static): `segment_centers(skeleton, segments)`, `weighted_mean(centers, segments)`, `compute(skeleton, segments)`, in the skeleton's frame | `BalanceMonitor` | 13 |
| Support polygon | `src/body/support_polygon.gd` | `SupportPolygon` (static): `ground_point(p)` = (x, −z), `world_point(q, y)`, `cross(a, b, c)`, `convex_hull(points)` (monotone chain, counterclockwise, no collinear corners), `distance_to_segment()`, `signed_distance(polygon, p)` (positive inside, −INF for no corners), `area()` | `BalanceMonitor` | 13 |
| Sway pendulum | `src/body/sway_pendulum.gd` | `SwayPendulum` (RefCounted): vars `gravity`, `height`, `stiffness` 20, `damping` 4, `max_offset` 0.3, `offset`, `velocity` (Vector2: x right, y forward); `push(dv)`, `step(delta)` (semi-implicit Euler), `natural_frequency()`, `damping_ratio()` | `BalanceMonitor` | 13 |
| Balance monitor | `src/body/balance_monitor.gd` | `BalanceMonitor` (Node3D, priority −1): enum `State` {NO_SUPPORT, STABLE, MARGINAL, OUTSIDE}; exports `rig`, `masses`, `marginal_margin` 0.015, `hysteresis` 0.01, `contact_tolerance` 0.02, `stiffness` 20, `damping` 4, `push_speed` 0.4, `max_sway` 0.3, `send_rate_hz` 30, `debug_draw`; vars `center_of_mass`, `segment_centers`, `polygon`, `polygon_height`, `margin`, `state`, `center_height`, `pendulum`, `measure_milliseconds`, `sender`, `messages_sent`; `measure()`, `foot_in_contact(side)`, `sole_corners(side)`, static `next_state()`, `push(direction)`, `sway()`, `balance_arguments()`; OSC `/body/balance` (f i f f f), `/body/balance/state` (s) | Lesson 13 scene | 13 |
| Lesson 13 root | `src/lessons/balance.gd` | 1 (`toggle_balance_debug`), 2 (`push_body_side`), 3 (`push_body_forward`), Shift reverses a push; two lines in `HUD/RockLabel` | `scenes/lessons/13_balance.tscn` | 13 |
| Trigger response | `src/input/trigger_response.gd`, `data/input/trigger_response.tres`, `data/input/trigger_curve.tres` | `TriggerResponse` Resource: `inner_deadzone` 0.05, `outer_deadzone` 0.95, optional `curve`; `apply(raw: float) -> float` | `StanceController` | 14 |
| Axial stick response | `src/input/axial_stick_response.gd`, `data/input/walk_stick_axial.tres` | `AxialStickResponse` (extends `StickResponse`): `apply()` shapes x and y separately with the inherited `shape()`, length limited to 1 | `analog_stances.gd` (key 8) | 14 |
| One-pole filter | `src/input/one_pole_filter.gd` | `OnePoleFilter` (RefCounted): vars `time_constant`, `value` (Vector2); `static blend(delta, tau)` = 1 − e^(−dt/τ); `step(input, delta)`, `reset()` | `StanceController` | 14 |
| Critical spring | `src/input/critical_spring.gd` | `CriticalSpring` (RefCounted): vars `frequency` ω, `value`, `velocity` (Vector2); `step(target, delta)` (exact, tick-rate independent), `step_euler(target, delta)` (semi-implicit Euler, unstable above ω dt = 2(√2 − 1)), `reset()` | `StanceController` | 14 |
| Stance controller | `src/body/stance_controller.gd` | `StanceController` (Node, priority −1, after `BalanceMonitor`): enums `Stance` {STANDING, CROUCHED}, `Smoothing` {NONE, ONE_POLE, CRITICAL, CRITICAL_EULER}; exports `monitor`, `player`, `trigger_response`, `side_range` 0.10, `forward_lean` 0.04, `crouch_depth` 0.25, `smoothing` (CRITICAL), `time_constant` 0.12, `spring_frequency` 12; vars `stance`, `trigger_raw`, `trigger_shaped` (x left, y right), `shift_target`, `shift`, `crouch`; `read_input()`, `update(delta)`, `apply_to_rig()`, `toggle_stance()`, `cycle_smoothing()` | Lesson 14 scene | 14 |
| Lesson 14 root | `src/lessons/analog_stances.gd` | 4 (`toggle_crouch`), 5 / 6 (`shift_weight_left` / `_right`), 7 (`cycle_stance_smoothing`), 8 (`toggle_axial_deadzone`), 9 (`cycle_stance_tick_rate`); five lines in `HUD/RockLabel` | `scenes/lessons/14_analog_stances.tscn` | 14 |
| Hold finder | `src/climb/hold_finder.gd` | `HoldFinder` (static): enum `Kind` {KNOB, EDGE}, `KIND_NAMES`; classes `Criteria` (`min_mean` 3, `max_mean` 40, `min_gradient` 0.5, `min_up` 0.3, `face`, `min_facing`, `spacing` 0.2, `knob_ratio` 0.25) and `Hold` (`position`, `normal`, `mean`, `gaussian`, `k1`, `k2`, `gradient_length`, `score`, `kind`, `top_out`, `on_ground`); `passes()`, `candidates()`, `score()` = H (n · up), `suppress()`, `refine(shape, hold, criteria, steps = 2)`, `classify(k1, k2, ratio)`, `find()` (the three stages in one call; scratch scripts and tests), `in_reach(holds, center, radius, aim, exclude)` | `ClimbableRock` (`candidates()`, `suppress()`, `refine()` in `find_holds()`), `ClimbController`, tests | 15 |
| Climbable rock | `src/climb/climbable_rock.gd` | `ClimbableRock` (`@tool`, extends `CurvatureMesher`): exports `face_normal` (shape space, +z), `min_mean_curvature`, `max_mean_curvature`, `min_gradient`, `min_up`, `min_facing`, `hold_spacing`, `knob_ratio` (each reruns the search, no re-meshing), `show_holds`, `ground` (optional `Terrain`), `ground_clearance` 0.05; vars `local_holds` (shape space, all), `holds` (world, those at least `ground_clearance` above `ground`), `buried_count`, `candidate_count`, `rejected_count`, `hold_milliseconds`; `find_holds()`, `criteria()`, `face_normal_world()`, `count_kind()`; internal `HoldMarks` lines | Lesson 15 scene | 15 |
| FABRIK | `src/climb/fabrik.gd` | `Fabrik` (static): `solve(joints, bone_lengths, target, tolerance = 1e-4, max_iterations = 10) -> Result` (`joints`, `error`, `iterations`, `reachable`), `place_on_sphere()`, `lengths()` | `ClimbController` (arms, F2), tests | 15 |
| Reach solver | `src/climb/reach_solver.gd` | `ReachSolver` (static): `project_to_ball()`, `project_to_half_space()`, `solve(start, centers, radii, plane_point, plane_normal, max_sweeps = 32, tolerance = 1e-4) -> Result` (`position`, `residual`, `sweeps`), `residual()` | `ClimbController`, tests | 15 |
| Climb controller | `src/climb/climb_controller.gd` | `ClimbController` (Node3D): signals `limb_placed(limb, hold)`, `state_changed(state)`; enums `State` {WALKING, CLIMBING, MANTLING}, `Limb` {HAND_L, HAND_R, FOOT_L, FOOT_R}, `LimbState` {HOLD, REACH, MOVE}, `ArmSolver` {TWO_BONE, FABRIK}; const `REACH_ACTIONS` (`shift_weight_left` / `_right`); exports `player`, `rock`, `stance`, `reach_fraction` 0.98, `reach_speed` 0.9, `reach_spring_frequency` 14, `trigger_threshold` 0.3, `snap_radius` 0.3, `move_time` 0.35, `move_lift` 0.08, `foot_hip_gap` 0.4, `foot_hand_gap` 0.6, `foot_step_threshold` 0.1, `foot_lateral_cost` 0.5, `grab_distance` 0.9, `wall_clearance` 0.3, `min_clearance` 0.2, `arm_hang` 0.8, `leg_stand` 0.75, `pelvis_time_constant` 0.18, `mantle_time` 1.2, `arm_solver`, `fabrik_iterations` 10, `fabrik_tolerance`, `debug_draw`; vars `state`, `limbs` (Array[LimbData]: `state`, `hold`, `point`, `from_point`, `to_hold`, `progress`, `aim`, `spring`), `pelvis`, `pelvis_target`, `residual`, `sweeps`, `limb_errors`, `fabrik_iteration_counts`, `candidate`, `ascent`, `hand_moves`, `foot_moves`, `climb_milliseconds`, `refusal`; `begin_climb()`, `let_go()`, `cycle_arm_solver()`, `face_normal()`, `body_basis()`, `face_point()`, `face_distance()`, `limb_root()`, `limb_reach()`, `limb_target()`, `contact_points()`, `clearance()` | Lesson 15 scene | 15 |
| Climbing player | `src/climb/climbing_player.gd`, `scenes/climbing_player.tscn` | `ClimbingPlayer` (extends `BodyPlayer`): var `climbing` (true: camera and stick only, no walking, gravity or `move_and_slide()`); `body_mesh()`. The scene is a copy of `grounded_player.tscn` with this script | Lesson 15 scene | 15 |
| Climb balance monitor | `src/climb/climb_balance_monitor.gd` | `ClimbBalanceMonitor` (extends `BalanceMonitor`): export `climb`; vars `hand_pull` (F/W; INF hanging, NAN not climbing), `lever_distance`, `lever_height`; `measure()` adds the held contacts to the polygon; static `pull_ratio(com, hands, feet, normal)` | Lesson 15 scene | 15 |
| Lesson 15 root | `src/lessons/climbing.gd` | 0 (`toggle_climb`), F1 (`toggle_climb_debug`), F2 (`cycle_arm_solver`); places `ClimbFace` on the terrain, turns the camera toward it; five lines in `HUD/RockLabel` | `scenes/lessons/15_climbing.tscn` | 15 |
| Crawling player | `src/crawl/crawling_player.gd`, `scenes/crawling_player.tscn` | `CrawlingPlayer` (extends `ClimbingPlayer`): enums `Mode` {UPRIGHT, CRAWL, SCRAMBLE}, `BodyShape` {STAND, CROUCH, CRAWL}, `MODE_NAMES`, `SHAPE_NAMES`; exports `crouch_height` 1.55, `crawl_radius` 0.35, `crawl_length` 1.65, `crawl_offset` 0.225, `fit_lift` 0.02, `crawl_speed` 0.6, `scramble_speed` 0.45, `turn_rate` 2.5, `scramble_max_angle_degrees` 55, `camera_heights`, `camera_responsiveness`; vars `mode`, `body_shape`, `speed_scale`, `floor_angle_degrees`, `turn_blocked`; `shape_height()`, `shape_radius()`, `shape_transform(shape, yaw)`, `fits(shape, yaw)`, `set_body_shape()`, `headroom(limit)`, `walk_max_angle_degrees()`, `wish_direction()`, `facing()`, `ground_ahead(direction, distance)` | Lesson 16 scene | 16 |
| Posture controller | `src/crawl/posture_controller.gd` | `PostureController` (extends `StanceController`): signal `posture_changed(posture)`; enum `Posture` {STAND, CROUCH, CRAWL, SCRAMBLE}, `POSTURE_NAMES`; exports `climb`, `auto_scramble`, `probe_distance` 0.6, `push_threshold` 0.3, `walkable_degrees` 40; vars `posture`, `refusal`, `slope_ahead_degrees`, `transitions`, `refusals`, `sender`; static `shape_of()`, `mode_of()`; `request(target) -> bool`, `toggle_stance()` (key 4; while climbing the Lesson 14 toggle), `toggle_crawl()` (F3), `is_scramble_slope()`; OSC `/body/posture s` | Lesson 16 scene | 16 |
| Crawl controller | `src/crawl/crawl_controller.gd` | `CrawlController` (Node3D, after `Player`): signal `limb_planted(limb, point, normal)`; enum `Limb` {HAND_L, HAND_R, LEG_L, LEG_R}, const `SWING_START` (0.25, 0.75, 0, 0.5), `LIMB_NAMES`, `SIGNS`; inner classes `LimbContact`, `SurfaceFrame` (`n`, `forward`, `right`, `base`; one object, filled by `_frame()` every tick); exports `player`, `posture`, `monitor`, `stride_length` 0.4, `swing_fraction` 0.2 (range 0.05–0.5), `step_height` 0.06, `replant_distance` 0.5, `weight_shift`, `shift_range` 0.08, `shift_lead` 0.1, `shift_frequency` 12, `lift_margin` 0, `hold_timeout` 1, `slope_lean` 0.5, `max_lean` 0.3, crawl and scramble body heights and widths, `head_lift` 0.15, `transition_time` 0.4, `normal_time_constant` 0.15, `ray_up`, `ray_down`, `debug_draw`; vars `limbs` (Array[LimbContact]: `planted`, `contact`, `normal`, `point`, `lift`, `target`, `target_normal`, `target_valid`, `swing`), `phase`, `shift`, `holding`, `waiting_limb`, `wait_seconds`, `lifts`, `unstable_lifts`, `smallest_lift_margin`, `lift_test_margin`, `limb_errors`, `knee_errors`, `surface_normal`, `lean`, `pelvis`, `shoulders`, `crawl_milliseconds`; static `swing_progress()`, `lift_in()`, `plane_normal()`, `kneeling_leg()`; `is_active()`, `contact_points()` ([point, is_hand] of planted limbs), `swinging_limb()`, `contact_normal()`, `support_margin(ground_point, except)` | Lesson 16 scene | 16 |
| Crawl balance monitor | `src/crawl/crawl_balance_monitor.gd` | `CrawlBalanceMonitor` (extends `ClimbBalanceMonitor`): export `crawl`; var `support_count`; `measure()` builds the polygon from the planted limbs while crawling or scrambling | Lesson 16 scene | 16 |
| Crawl gap | `src/world/crawl_gap.gd` | `CrawlGap` (`@tool`, extends `BoxCourse`): exports `roof_height` 0.9, `gap_width` 1.1, `gap_length` 2.4, `apron` 1.2, `ramp_angle_degrees` 15; consts `WALL_THICKNESS`, `ROOF_THICKNESS`, `FLOOR_MARGIN`; `floor_rect()` | Lesson 16 scene | 16 |
| Lesson 16 root | `src/lessons/crawling_and_scrambling.gd` | F3 / Guide (`toggle_crawl`), F4 (`toggle_crawl_debug`); key 0 refused in low postures; places `CrawlGap` (highest terrain under its floor) and `Slab` (terrain at the 48° ramp's foot); four lines in `HUD/RockLabel` | `scenes/lessons/16_crawling_and_scrambling.tscn` | 16 |
| BRDF reference | `src/render/brdf.gd` | `Brdf` (static): enum `Model` {LAMBERT, WRAP, OREN_NAYAR, GGX} (= `light_model`), `MODEL_NAMES`; class `Params` (`albedo`, `wrap` 0.5, `sigma` 30° in radians, `roughness` 0.92, `f0` 0.04); `lambert()`, `wrap_cosine()`, `oren_nayar()`, `oren_nayar_angular()`, `ggx_distribution()`, `smith_lambda()`, `smith_masking()`, `smith_height_correlated()`, `schlick_fresnel()`, `ggx_specular()`, `diffuse_cosine()`, `specular_cosine()`, `reflected()` (pixel value π E (f cos θ_l), albedo included); integrals `directional_albedo(model, v, p, mu_steps, phi_steps, mu_min)`, `ggx_normalization(alpha)`, `projected_facet_area(v, alpha)`, `ggx_specular_albedo(v, roughness, f0)` (importance-sampled grid); `direction(theta, phi)` | `writing_light.gd` (HUD), tests | 17 |
| Custom light shaders | `shaders/lighting/brdf.gdshaderinc`, `shaders/lighting/custom_light.gdshaderinc` | GLSL copies of the `Brdf` formulas (`lambert_cosine`, `wrap_cosine`, `oren_nayar_cosine`, `ggx_distribution`, `smith_lambda`, `smith_g2`, `schlick_fresnel`, `ggx_specular_cosine`); `light()` with uniforms `light_model` (0–3), `light_term` (0 both, 1 diffuse, 2 specular), `light_wrap` 0.5, `light_sigma_degrees` 30, `light_f0` 0.04 | `LitShader` (appended to existing shaders) | 17 |
| Lit shader | `src/render/lit_shader.gd` | `LitShader` (static): `make(base: Shader, include: ShaderInclude) -> Shader` (base code + `#include` of the include's path; cached per base; refuses a base with `light()`), `material(base: ShaderMaterial, include) -> ShaderMaterial` (uniform values copied), `copy_parameters(from, to) -> int` (by name), `has_light_function(code)` | `ShadingSwitch`, `ShadingGallery`, tests | 17 |
| Shading switch | `src/render/shading_switch.gd` | `ShadingSwitch` (Node): signal `mode_changed`; enums `Mode` {BUILT_IN, LAMBERT, WRAP, OREN_NAYAR, GGX}, `Term` {ALL, DIFFUSE, SPECULAR}, `MODE_NAMES`, `TERM_NAMES`; exports `light_include`, `targets` (nodes with a cheap `material` setter: `Terrain`, `SdfMesher`), `start_mode`; vars `mode`, `term`, `originals`, `lit_materials`; `set_mode()` (copies base uniforms to the next material), `cycle_mode()`, `cycle_term()`, `material_for()` | Lesson 17 scene | 17 |
| Shading gallery | `src/render/shading_gallery.gd` | `ShadingGallery` (`@tool` Node3D): exports `light_include`, `rock_shape`, `rock_material`, `rock_cell_size` 0.06, `tile_field`, `tile_material`, `tile_size` 2.4, `tile_vertices` 49, `spacing` 2.7, `plinth_depth` 0.3 (below the lowest terrain point), `ground`, `label_height` 1.7; inner class `Column` (`mode`, `root`, `tile`, `plinth`, `rock`, `label`, `tile_material`, `rock_material`); vars `columns`, `rock_mesh`, `build_milliseconds`; `rebuild()`, `column_position(i)`, `row_height()`, `plinth_height(i)`, `set_term(term)` | Lesson 17 scene | 17 |
| Lesson 17 root | `src/lessons/writing_light.gd` | F5 (`cycle_shading_model`), F6 (`cycle_light_term`), F7 (`toggle_lesson_hud`); export `start_pitch_degrees`; camera toward `Gallery`; `HUD/LightLabel` (mode, term, sun elevation, N·L and N·V under the player, π f cos θ_l of the four models from `Brdf`) | `scenes/lessons/17_writing_light.tscn` | 17 |
| Lesson 03 root | `src/lessons/painting_the_ground.gd` | Paint view, contour, tonemapper, and fog keys; ColorStrip placement; export `ramp_tower` (placed at ground height when set); HUD lines | `scenes/lessons/03_painting_the_ground.tscn` | 03 |

## Input actions (`project.godot`)

| Action | Keyboard / mouse | Gamepad | Read by |
|---|---|---|---|
| `move_forward`, `move_back`, `move_left`, `move_right` | W S A D | Left stick | `player.gd` |
| `look_left`, `look_right`, `look_up`, `look_down` | Arrow keys (mouse handled separately) | Right stick | `player.gd` |
| `release_mouse` | Esc | — | `player.gd` |
| `cycle_debug_view` | Tab | Back / Select | `sandbox.gd` |
| `cycle_normal_method` | N | Y (north) | `sandbox.gd` |
| `cycle_tick_rate` | T | D-pad up | `walking_on_a_surface.gd` (30, 60, 144 Hz); no other scene reads it |
| `toggle_blend_rule` | B | D-pad down | `walking_on_a_surface.gd` |
| `cycle_paint_view` | V | D-pad left | `painting_the_ground.gd` |
| `toggle_contours` | C | D-pad right | `painting_the_ground.gd` |
| `cycle_tonemapper` | M | Left shoulder | `painting_the_ground.gd` (Linear, Reinhard, Filmic, ACES, AgX) |
| `toggle_fog` | F | Right shoulder | `painting_the_ground.gd` |
| `cycle_osc_rate` | O | X (west) | `osc_bridge.gd` (off, 10, 30, 60 Hz) |
| `toggle_step_timing` | K | B (east) | `footsteps.gd` (time-tagged, immediate) |
| `toggle_listener` | L | Left stick click | `spatial_audio.gd` (camera, head) |
| `cycle_slice_view` | G | A (south) | `sdf_primitives.gd` (distance, gradient length, sign) |
| `step_slice` | H | Right stick click | `sdf_primitives.gd` (horizontal cut 0.25–3.25 m in 0.5 m steps) |
| `cycle_rock_view` | R | — | `field_to_mesh.gd` (mesh, mesh + slices, slices) |
| `toggle_mesher_backend` | J | — | `field_to_mesh.gd` (pass 1 of surface nets on GPU or CPU; rebuilds) |
| `cycle_curvature_view` | U | — | `implicit_curvature.gd` (weathered, mean H, Gaussian K, normals) |
| `toggle_normal_source` | I | — | `implicit_curvature.gd` (gradient, trilinear normals; no resampling) |
| `cycle_raymarch_view` | P | — | `raymarching.gd` (lit, steps, normals, mean H) |
| `cycle_march_budget` | X | — | `raymarching.gd` (`max_steps` 16, 32, 64, 96, 192) |
| `toggle_formations` | Z | — | `raymarching.gd` (show or hide `Formations`) |
| `toggle_body_view` | E | — | `skeleton_from_code.gd` (rig, rig + capsule, capsule) |
| `cycle_foot_solver` | Q | — | `feet_on_the_ground.gd` (own IK, TwoBoneIK3D, walk cycle) |
| `toggle_foot_debug` | Y | — | `feet_on_the_ground.gd` (rays, plants, swing targets) |
| `toggle_balance_debug` | 1 | — | `balance.gd` (support polygon, center of mass, segment centers) |
| `push_body_side` | 2 (Shift: left) | — | `balance.gd` (push of `push_speed` to the right) |
| `push_body_forward` | 3 (Shift: back) | — | `balance.gd` (push forward) |
| `toggle_crouch` | 4 | D-pad up (shared with `cycle_tick_rate`) | `analog_stances.gd` (standing, crouched; from Lesson 16 on through `PostureController.toggle_stance()`, which also rises from a crawl to crouched and, while climbing, toggles only the Lesson 14 crouch) |
| `shift_weight_left` | 5 (held) | Left trigger (axis 4) | `StanceController.read_input()`, raw strength, action deadzone 0; `ClimbController` (left hand reaches above raw 0.3) |
| `shift_weight_right` | 6 (held) | Right trigger (axis 5) | `StanceController.read_input()`, raw strength, action deadzone 0; `ClimbController` (right hand reaches above raw 0.3) |
| `cycle_stance_smoothing` | 7 | — | `analog_stances.gd` (none, one-pole, spring, spring with Euler) |
| `toggle_axial_deadzone` | 8 | — | `analog_stances.gd` (player's `stick_response`: radial, axial) |
| `cycle_stance_tick_rate` | 9 | — | `analog_stances.gd` (`Engine.physics_ticks_per_second` 60, 120) |
| `toggle_climb` | 0 | Start | `climbing.gd` (`ClimbController.begin_climb()`, or `let_go()` while climbing) |
| `toggle_climb_debug` | F1 | — | `climbing.gd` (climbing lines and hold markers) |
| `cycle_arm_solver` | F2 | — | `climbing.gd` (`ClimbController.cycle_arm_solver()`: two-bone, FABRIK) |
| `toggle_crawl` | F3 | Guide | `crawling_and_scrambling.gd` (`PostureController.toggle_crawl()`: standing or crouched to crawling, crawling back) |
| `toggle_crawl_debug` | F4 | — | `crawling_and_scrambling.gd` (`CrawlController.debug_draw`: collision shape, contacts, swing paths) |
| `cycle_shading_model` | F5 | — | `writing_light.gd` (`ShadingSwitch.cycle_mode()`: built-in, Lambert, wrap, Oren–Nayar, GGX on Terrain, Rocks/Boulders, ClimbFace) |
| `cycle_light_term` | F6 | — | `writing_light.gd` (`ShadingSwitch.cycle_term()` and `ShadingGallery.set_term()`: diffuse + specular, diffuse only, specular only) |
| `toggle_lesson_hud` | F7 | — | `writing_light.gd` (`HUD/LightLabel` or the labels of Lessons 01–16) |

`player.gd` reads the move actions twice from Lesson 02 on: `Input.get_vector(..., 0.0)` for the raw stick (no deadzone), and either the built-in radial deadzone (0.15, the action deadzone) or `StickResponse.apply()` for the shaped stick.

One gamepad button carries two actions: D-pad up is `cycle_tick_rate` (read in the Lesson 02 scene only) and `toggle_crouch` (read from Lesson 14 on). Godot matches an event against every action that lists it; each scene reads one of the two. The Lesson 14 tick-rate key 9 has its own action, `cycle_stance_tick_rate`, so that T and D-pad up leave the tick rate alone in the scenes of Lessons 14 and later.

## Lesson scenes

| Scene | Lesson | Shows |
|---|---|---|
| `scenes/sandbox.tscn` | 00–01 | Height-field terrain, capsule walker, debug views |
| `scenes/lessons/02_walking_on_a_surface.tscn` | 02 | Steep hill, ramp tower, step row; shaped stick, steep sliding, camera look-ahead |
| `scenes/lessons/03_painting_the_ground.tscn` | 03 | Painted terrain (triplanar noise, contours), ramp tower in the painted material (45°–85°), color strip, tonemapper and fog keys |
| `scenes/lessons/04_osc_bridge.tscn` | 04 | Lesson 03 scene's WorldEnvironment, Sun, Terrain, ColorStrip, and Player (no `RampTower`; HUD at the top left) plus `StateReporter`: player state over OSC to sclang; O key for the rate |
| `scenes/lessons/05_footsteps.tscn` | 05 | Lesson 04 scene plus `Footsteps`: `/foot/step` bundles with time tags; K key for the timing |
| `scenes/lessons/06_spatial_audio.tscn` | 06 | Lesson 05 scene plus `Emitters` (three `SoundEmitter`) and `SpatialReporter`: listener-relative positions and wind over OSC; L key for the listener |
| `scenes/lessons/07_sdf_primitives.tscn` | 07 | Lesson 06 scene plus `Rocks` with two `SdfSlice` cuts through `boulder_pile.tres`; G and H keys |
| `scenes/lessons/08_field_to_mesh.tscn` | 08 | Lesson 07 scene plus `Rocks/Boulders` (`SdfMesher`: boulder pile as mesh and trimesh collision) and `HUD/RockLabel`; R and J keys |
| `scenes/lessons/09_implicit_curvature.tscn` | 09 | Lesson 08 scene with `Rocks/Boulders` as a `CurvatureMesher` and the weathering material; U and I keys |
| `scenes/lessons/10_raymarching.tscn` | 10 | Lesson 09 scene plus `Formations` (three `RaymarchVolume`: a pile beside the meshed one, a pile at scale 4, a 3 × 3 field of tors at scale 2.5); P, X, Z keys. |
| `scenes/lessons/11_skeleton_from_code.tscn` | 11 | Lesson 10 scene with `Player` replaced by `scenes/body_player.tscn`: a 15-bone procedural skeleton drawn with capsules and a placeholder walk cycle; E key. |
| `scenes/lessons/12_feet_on_the_ground.tscn` | 12 | Lesson 11 scene with `Player` from `scenes/grounded_player.tscn` (`FootRig`: raycast feet, two-bone IK, pelvis from the feet), `Footsteps` as `PlantFootstepReporter`, and a `StepRow` staircase; Q and Y keys. |
| `scenes/lessons/13_balance.tscn` | 13 | Lesson 12 scene plus `BalanceMonitor`: center of mass, support polygon, balance margin on the HUD and over OSC, pushes; keys 1, 2, 3. |
| `scenes/lessons/14_analog_stances.tscn` | 14 | Lesson 13 scene plus `Stance` (`StanceController`): weight shift from the triggers and the stick, crouch, four smoothing rules; the player has the Lesson 02 `StickResponse`; keys 4–9. |
| `scenes/lessons/15_climbing.tscn` | 15 | Lesson 14 scene with `Player` from `scenes/climbing_player.tscn`, `BalanceMonitor` as `ClimbBalanceMonitor`, and two new nodes: `ClimbFace` (`ClimbableRock`: `climbing_face.tres` meshed, 67 holds found, 59 above the terrain) and `Climb` (`ClimbController`); keys 0, F1, F2; triggers reach while climbing. |
| `scenes/lessons/16_crawling_and_scrambling.tscn` | 16 | Lesson 15 scene with `Player` from `scenes/crawling_player.tscn` (three collision shapes), `Stance` as `PostureController` (standing, crouched, crawling, scrambling), `BalanceMonitor` as `CrawlBalanceMonitor`, and three new nodes: `CrawlGap` (a passage 0.9 m high), `Slab` (a `RampTower` with a 48° ramp) and `Crawl` (`CrawlController`: four-point static gait); keys F3, F4; scrambling starts by itself. |
| `scenes/lessons/17_writing_light.tscn` | 17 | Lesson 16 scene with the player at (14.2, 42) and three new nodes: `Gallery` (`ShadingGallery`: five columns of rippled ground tile, plinth and rock, one per shading mode, labelled) and `Shading` (`ShadingSwitch`: terrain, boulder pile and climbing face between Godot's built-in light and four custom `light()` models), `HUD/LightLabel`; keys F5, F6, F7. `run/main_scene` points here. |

`run/main_scene` in `game/project.godot` points to the newest lesson scene.

## Tests

| Test | Covers |
|---|---|
| `tests/test_07_sdf_shapes.gd` | Exact distances of sphere, box (sharp, rounded), capsule; sphere gradient length 1; ellipsoid zero on the surface for both estimates, `SCALED_SPHERE` never above the brute-force distance and sampled ‖∇f‖ ≤ 1, `GRADIENT` bound `INF`; `smin` limits and the smooth-union surface height on the y axis; union, intersection, subtraction signs; transform (move, turn, scale); repetition with count limit; displacement within the amplitude; smooth union of two (3, 1, 1) ellipsoids contained in its `bounds()`; the three rock `.tres` files: sampled ‖∇f‖ below the bound, solid inside `bounds()` |
| `tests/test_07_sdf_scene.gd` | Lesson 07 scene: Rocks at ground height; both slices: image size, sample count, negative values, ‖∇f‖ ≤ bound, texel equals `evaluate()`; separate material copies; G cycles both views 1, 2, 0; H raises the cut 0.5 m; Lesson 06 scene has no Rocks |
| `tests/test_08_surface_nets.gd` | `edge_crossing`; trilinear gradient of a linear field; grid covers `bounds()` with a positive outer layer; unit sphere at 0.2 m: vertices in their cells and within 0.03 m, normals within 10°, closed mesh, χ = 2, all triangles outward; GPU table equals CPU table (windowed runs only; skipped headless) |
| `tests/test_08_mesher_scene.gd` | Lesson 08 scene: mesh and trimesh collision in internal children, vertex \|f\| below one cell; capsule dropped on the split boulder rests on the floor at feet height above 1.5 m; walking 2 s keeps the capsule center 0.3 m outside the rock; R cycles views, J switches `use_gpu`, headless falls back to CPU; Lesson 07 scene has no Boulders |
| `tests/test_09_implicit_curvature.gd` | Exact-derivative sphere: H = 1/r, K = 1/r², invariant under f → 3f, H flips under f → −f; numerical sphere r = 1.5 at origin and (5, 5, 5): H, K within 0.01; torus (1, 0.25) at 72 points: H within 0.01, K within 0.05, normal within 0.1° of the analytic gradient, K below −5 and above 3; Hessian of a linear field is 0, of x² + 2yz exact; principal curvatures (4, 0.8) from (2.4, 3.2); the non-distance field ‖p‖² − 2.25 gives H, K of the sphere of radius 1.5 within 0.01 |
| `tests/test_10_sdf_glsl.gd` | `SdfGlsl` translates a tree with every node type (13 nodes, none unsupported); the pile's code spliced into the template compiles (uniform list holds `sdf_noise_0`, `max_steps`, `step_scale`, `proxy_min`); one shared noise → one texture; a texel equals `get_noise_3dv` at its grid point; float literals carry a decimal point |
| `tests/test_10_sphere_tracer.gd` | `SphereTracer`: head-on ray at a unit sphere hits at t = 4 in 2 steps; offset ray misses; a field of Lipschitz bound 2 tunnels when stepped by f and hits at 4.75 when stepped by f / 2; `box_interval()` from outside, from inside, and a miss |
| `tests/test_11_forward_kinematics.gd` | `ForwardKinematics.rotate()` equals q · v and Basis(q r) = Basis(q) Basis(r) (50 random pairs); the rig has one bone per spec with its parent and rest; soles at y = 0 and head top at `standing_height()`; FK by hand equals `Skeleton3D.get_bone_global_pose()` for random rotations; `WalkCycle` at amount 0 is the rest pose, right side at φ + 0.5 equals left at φ, foot pitch cancels hip + knee |
| `tests/test_11_body_scene.gd` | Lesson 11 scene: `Player` is a `BodyPlayer` with 15 bones and 17 capsules, old capsule hidden; 1 s of `move_forward` advances the phase by distance / stride within 0.01 and raises the amount above 0.5; E cycles the views; Lesson 10 scene keeps `Player` |
| `tests/test_12_two_bone_ik.gd` | `TwoBoneIk` on 500 random reachable chains: end on target, bone lengths, law of cosines, knee on the pole side (all within 1e-5); far and near targets unreached, chain stretched or folded toward the target; rest bases near identity, bases are rotations with −y along the bones and a shared hinge; `foot_basis` follows the normal; `limit_tilt`; `swing_progress` intervals; `swing_ease` ends at rest |
| `tests/test_12_foot_rig.gd` | `FootRig` on a floor box, driven by hand at 3 m/s: right foot planted at rest, ankles at ankle height; stance ankles move less than 1e-4 m per tick; ankle error below 1e-4 m; pelvis in [−0.35, 0]; plants alternate every 0.70 m ± 0.02; plants past the edge on the 0.18 m step top; TwoBoneIK3D knees equal TwoBoneIk knees within 1e-4 m |
| `tests/test_12_feet_scene.gd` | Lesson 12 scene: `FootRig` and `PlantFootstepReporter`; 2 s of `move_forward`: at least 4 plants, one `/foot/step` per plant, ankle error below 1 mm, plants within 0.05 m of `height_at()`; Q cycles the solvers, Y the lines; Lesson 11 scene keeps `BodyRig` and `FootstepReporter` |
| `tests/test_13_support_polygon.gd` | `convex_hull()`: square with inner, repeated and collinear points → 4 corners, area +1; one point, collinear points; 200 random sets: left turns only, corners from the input, all points inside, area independent of order; `signed_distance()`: inside, on an edge, beside an edge, beyond a corner, one point, a segment, none; 2000 random points against an independent test (sign, magnitude within 1e-5); (x, −z) orientation |
| `tests/test_13_balance.gd` | Winter fractions sum to 1, 12 segments; two-segment weighted mean; standing `FootRig` on a floor box: c on the midline, 0.9–1.0 m high, both feet in contact, margin > 0; walking 3 m/s: one foot and c outside on most ticks; `SwayPendulum` push decays below 1 mm in 3 s, ω and ζ, kp < g/L falls to the limit; `next_state()` thresholds and hysteresis |
| `tests/test_13_balance_scene.gd` | Lesson 13 scene: monitor reads the player's rig and ticks first; standing margin > 0, c 0.9–1.0 m above the feet; 58–62 `/body/balance` of 44 bytes in 2 s, one `/body/balance/state` per change; 2, Shift + 2, 3 push, sway decays in 4 s; 1 toggles the lines; Lesson 12 scene has no `BalanceMonitor` |
| `tests/test_14_filters.gd` | `TriggerResponse` deadzone, saturation, monotonic, linear without a curve; `AxialStickResponse` snaps 10° to forward, equals radial on an axis, length ≤ 1; `OnePoleFilter` 1 − 1/e after τ, equal at 30/60/120/240 Hz; `CriticalSpring.step()` equals the closed form, no overshoot, equal at four rates; `step_euler()` differs between 60 and 120 Hz, stable below and unstable above ω dt = 2(√2 − 1) |
| `tests/test_14_stance_scene.gd` | Lesson 14 scene: `Stance` after `BalanceMonitor`, same priority, before `Player`; radial `StickResponse`; rig = rest + sway + shift − crouch; right trigger action shifts right, release returns; key 4 crouches (CoM lower by > 0.1 m, ankle errors < 0.01 m); keys 7, 8, 9; Lesson 13 scene has no `Stance` |
| `tests/test_15_climb_math.gd` | `ReachSolver`: ball and half-space projections, overlapping balls (residual 0), separate balls (residual = gap 0.2), 300 random feasible sets of three balls and a half-space; `Fabrik`: bone lengths, elbow in the plane of root, target and start elbow, converged elbow = `TwoBoneIk` with the start elbow as pole, out-of-reach straight chain, four-joint chain; `HoldFinder`: vertex tests, score, knob or edge, suppression, `refine()` onto a sphere (H = 1/r), rejection of a union crease by ‖∇f‖ = 0.31, `find()` on three vertices of a sphere, `in_reach()` filter, exclusion and order; `ClimbBalanceMonitor.pull_ratio()` |
| `tests/test_15_climb_scene.gd` | Lesson 15 scene: node types and order; more than 40 holds, at least 2 top-outs, every hold on the surface and inside the thresholds, spacing, world = transform · shape space less the holds in the terrain (`buried_count`); refusal at 1.2 m, start at 0.5 m, hands on their targets; a scripted climb (triggers and stick, steered to the highest hold in reach; climbing ticks stepped by hand) with residual < 1 mm and limb errors < 0.02 m on every tick, ending in a mantle, standing on the top, refusal "behind the face" there; key 0 lets go, the body lands clear of the face; F1, F2, 0; 9 changes the tick rate and T does not; `cycle_tick_rate` on T and D-pad up, `cycle_stance_tick_rate` on 9; Lesson 14 scene has no climbing (the `run/main_scene` check moved to `test_16_crawl_scene.gd`) |
| `tests/test_16_crawl_math.gd` | `CrawlController.swing_progress()`: one limb in the air for swing fraction 0.2 and 0.25, two for 0.3, each limb swinging its fraction; `lift_in()` over 50 cycles of random steps: 200 lifts in the lateral sequence, half-open interval; `support_margin()` of four contacts and of each triangle against an edge formula (2000 points), four-contact margin never below a triangle's, the crossing of the diagonals at margin 0 against all four triangles; `plane_normal()`; the lean d tan θ, clamped, vertical projection back on the base point; `kneeling_leg()` bone lengths and knee error; `PostureController.shape_of()`, `mode_of()` |
| `tests/test_16_crawl_scene.gd` | Lesson 16 scene (real-time physics, about 40 s): node types and wiring, `Crawl` after `Player`; roof 0.9 m above a floor at the highest terrain point; under the roof the stand and crouch shapes do not fit, the crawl shape fits along and not across; standing and crouched the body stops at the roof; crawling it passes, with three or four contacts, planted limbs within 0.06 m and no unstable lift on every tick, the drawn body inside the crawl shape (height, width, length) and, once lowered, inside the crouch shape; stand, 4 and F3 refused under the roof ("no headroom"); sideways stick turns at most to the P2 limit, the stick along the passage turns the body back to the axis, planted limbs within 0.06 m and no unstable lift for the rest of the passage; the upright body does not climb the slab, the scrambling body reaches the top (at most one unstable lift) and stands; F3, 0 ("not upright"), F4; one `/body/posture` per change; `toggle_crawl` on F3 and Guide (the only action on Guide), `toggle_crawl_debug` on F4, the Lesson 02 and 14 tick-rate bindings, T and 9; key 4 on the climbing face crouches without a posture change, and after the climb the posture is crouched; Lesson 15 scene has no crawling (`run/main_scene` check moved to `test_17_light_scene.gd`) |
| `tests/test_17_brdf.gd` | `Brdf` by numerical integration: Lambert directional albedo 1 (and 0.4 for ρ 0.4) at four view angles; wrap (1 + 2w)/(1 + w) over the hemisphere and 1 + w over the sphere; Oren–Nayar σ = 0 equals Lambert, reciprocity, albedo ≤ 1 and falling with σ; GGX D normalized for α 0.02–1; ∫ max(0, v·h) D = (1 + Λ) cos θ_v; G2 ≥ G1 G1; GGX specular albedo ≤ 1, 1 − ln 2 at α = 1, grid equals importance sampling; reciprocity; Schlick end values |
| `tests/test_17_light_scene.gd` | `LitShader` on the Lesson 03 and 09 shaders (base code + include, compiles with base and 5 light uniforms, cached, `copy_parameters()`); Lesson 17 scene: switch targets, start on the originals, F5 through four lit modes and back, both rocks share one lit material, Tab's `debug_view` survives switches, the Slab keeps the original; F6 on every lit material; F7; gallery columns, labels, materials, shared rock mesh, one row height, terrain below every tile and above every plinth bottom; F5–F7 bindings, Lesson 15–16 input-map checks, `run/main_scene`; Lesson 16 scene has no Shading or Gallery |
| `tests/test_17_light_pixels.gd` | Windowed only (headless: skipped). Linear readback of a float `SubViewport`: `LIGHT_COLOR` = π × energy, diffuse × ALBEDO afterward, specular unchanged, default diffuse = `diffuse_lambert` = custom Lambert; each custom model equals `Brdf.reflected()` on 24 tilted quads at roughness 0.5 and 0.92 |
| `tests/test_10_raymarch_scene.gd` | Lesson 10 scene: three `RaymarchVolume` with generated `sdf_map`, proxy covering `bounds()`, `step_scale` = 1 / L, placed at terrain height + scene offset; P, X, Z; Lesson 09 scene has no `Formations` |
| `tests/test_09_curvature_scene.gd` | Lesson 09 scene: `CurvatureMesher` with the weathering material; one H, K, normal per vertex; `CUSTOM0` RGBA float equals (H, K, k1, k2); unit gradient normals, mean angle to trilinear normals below 5°; median H in 0.2–2 /m, some K < 0; I switches normals, U cycles `curvature_view`; Lesson 08 scene keeps a plain `SdfMesher` |
| `tests/test_06_listener_math.gd` | `ListenerMath.spherical()` ahead, right, left, behind, overhead (azimuth 0 at the pole), (1, 1, −1); turned and moved listener; `direction_azimuth()` ignores position; three turns unwrap to 6π with steps below π; 179°, −179° → 181°; `wind_strength_at()` clamps |
| `tests/test_06_spatial_scene.gd` | Lesson 06 scene: 59–61 position bundles of 172 bytes in 2 s, 1–3 kind bundles of 152 bytes; the first `/emitter/pos` equals `ListenerMath` for camera and emitter; azimuth steps below π while the camera turns 0.3 rad per tick; L switches to the CameraPivot; Lesson 05 scene has no `SpatialReporter` |
| `tests/test_05_osc_bundle.gd` | Time tags: immediate = 0/1, Unix 1.5 s = `83 aa 7e 81 80 00 00 00`, round trip within 1 µs; bundle of `/a` = 28 bytes written out; loopback through `send_bundle()` byte-identical; `/foot/step` bundle = 64 bytes |
| `tests/test_05_gait_clock.gd` | 40 strikes in 10.1 s at 3 m/s, 0.75 m steps, at 30, 60, 144 Hz; rebuilt strike times on multiples of 0.25 s within 1e-9 s; alternating feet; one strike for a 10 m jump; `signed_slope_degrees` ±30 on a 30° plane, 0 across and at rest |
| `tests/test_05_surface.gd` | `SurfaceClassifier` reads the material; noise image arrives; clean-band rules (dirt low, grass high, rock at 40°, rockiness 0.5 at 27°, noise shift adds 8°); weights non-negative, sum 1; `sample_bilinear` centers, midpoint, wrap; Lesson 05 scene sends 9–12 bundles in 3 s of walking, tags in the future on arrival; K switches to plain messages; Lesson 04 scene has no `Footsteps` |
| `tests/test_04_osc_encoder.gd` | `OscEncoder` byte for byte: padding of 0–8 bytes, `/a`, `/abc`, `/oscillator/4/frequency 440.0`, `/foo 1000 -1 hello 1.234`, float32 rounding of 0.1, int32 wrap of 2³² + 5, UTF-8, `/player/state` = 44 bytes |
| `tests/test_04_osc_sender.gd` | `RateClock` (300 sends in 10 s at 30, 60, 144, 240 Hz ticks; gaps 4 and 5 at 144 Hz; one per tick; off; hitch); loopback packet equals encoder output; 20 sends to a closed port return true; Lesson 04 scene sends about 30 `/player/state` per second through the autoload and one `/player/ground`; O cycles the rate; Lesson 03 scene sends nothing |
| `tests/test_02_stick_response.gd` | Default `StickResponse` equals the Lesson 00 mapping (441 stick positions); walk response limits, monotonicity, direction; `Curve` override |
| `tests/test_02_smoothing.gd` | `Player.blend_factor()`: exponential rule identical at 30, 60, 144, 240 Hz; linear rule depends on tick rate and oscillates at kΔt = 2 |
| `tests/test_02_ground.gd` | Physics run (about 5 s): 44° ramp climbed, 46° not; 9 cm step climbed, 25 cm not; slide off a 55° ramp reaches √(2 g h) within 5 % and keeps horizontal velocity; sandbox Player keeps Lesson 00 defaults |
| `tests/test_03_paint_math.gd` | `PaintMath`: sRGB curves against `Color.srgb_to_linear()` / `linear_to_srgb()` at 256 values and round trip; triplanar weights sum to 1, side weight 0.1 / 0.5 / 0.9 at 30° / 45° / 60° for k = 4; contour distance and index, negative heights included |
| `tests/test_03_painted_scene.gd` | `terrain_painted.gdshader` compiles and declares the written uniforms; `terrain_material.tres` still uses `terrain.gdshader`; V, C, M (five steps return to the start), F, and Tab change the material and Environment in the lesson scene; `RampTower` shares the terrain's material, stands at ground height, and has a ramp of 60° or more |

## Known limits (Lesson 02)

- The capsule climbs steps up to 0.118 m (box edges with Jolt's default margin) at `floor_max_angle` 45°; taller steps are walls. There is no step-up rule (Lesson 02 exercise E4 is optional and not relied on).
- Stepping off the 0.25 m step at 3 m/s produces an `AIR` phase of 11 ticks (0.18 s) even with `floor_snap_length` 0.4.
- Walking off a ledge onto a slope steeper than `floor_max_angle` at full speed is a ballistic fall, not a slide.
- `_ground_height_below()` casts rays from `look_ahead_distance + 2` m above the sample point; under overhangs it reports the overhang.

## Known limits (Lesson 03)

- The surface rules (rock, dirt) run in the shader alone. CPU code cannot ask which surface lies under a point; `PaintMath` holds the sRGB, triplanar, and contour formulas, not the noise-shifted rules (Lesson 03 R3; needed by Lesson 05).
- The noise texture tiles every `noise_scale_meters` (24 m); the repetition is visible at small scales (Lesson 03 T6, exercise E4).
- Contour lines merge where their screen spacing falls to a few pixels (Lesson 03 O4, exercise E6). A flat region at exactly a contour height is painted in the contour color (P6).
- The keys change the loaded `painted_terrain_material.tres` and the scene's `Environment` in memory; nothing is saved.
- The sandbox terrain's steepest slope is 40.6°: on it the y projector keeps at least 65 % of the triplanar weight (k = 4), and the projections differ by little. The Lesson 03 scene's `RampTower` supplies planes at 45°–85°.
- `source_color` has no effect on `ground_noise.tres` because `NoiseTexture2D` writes an L8 image; with a color ramp (RGBA8) the hint decodes it (Lesson 03 T1).

## Known limits (Lesson 04)

- Godot sends; it does not receive. Port 9000 has no listener (exercise E5).
- No bundles or timetags (Lesson 05). Arrival intervals of a 30 Hz stream scatter over roughly 26–39 ms, with near-zero intervals after catch-up frames (Lesson 04 O5).
- `/player/ground` is sent on change only; a receiver started late does not know the ground state until the next change.
- Every run of the Lesson 04 scene, `tools/check.sh` included, sends to 127.0.0.1:57120.

## Known limits (Lesson 05)

- Footsteps come from distance walked (`GaitClock`), not from foot contacts. Standing still after walking leaves the phase mid-step; the next walk starts there (exercise E1). Step length does not change with speed (exercise E2).
- Time tags assume Godot and sclang share one system clock (same machine).
- `/foot/step` is sent once per strike over UDP; a lost packet is a missing step. With `latency_seconds` 0.05, no step of the measured walks arrived late; at 0.025, 6 of 30 did.
- The classifier uses `get_floor_normal()` (flat collision triangle) and the coarse noise at mip level 0; the shader uses interpolated vertex normals and filtered mip levels. Near a rule threshold sound and paint can disagree.
- Block 2 of `05_footsteps.scd` (the responder) was compiled but not run against a live server in the automated checks; the SynthDefs are checked by the offline render (`tools/footsteps_nrt.sh`).

## Known limits (Lesson 06)

- Every emitter is sent 30 times per second whether or not anything moved: 5312 bytes per second for three emitters (Lesson 06 O6; exercise E2).
- Footsteps are not spatialized; they stay centered (Lesson 06 R1).
- With two output channels neither `PanAz` nor the two-channel `DecodeB2` separates front from back. `PanAz` ignores elevation. There is no binaural decoding: the ATK class library is not installed (decision 0007; exercise E4).
- Distance cues are a 1/d gain above 2 m and a low-pass stand-in for air absorption, not fitted to ISO 9613-1 (exercise E6). No occlusion (exercise E3), no Doppler (exercise E1), no reverberation (Lesson 29).
- The wind is one direction and a strength from the player's height, not a field (Lesson 27).
- Blocks 2–4 of `06_spatial_audio.scd` were run against Godot with no server booted (the synths' messages went nowhere): the responders created three emitters and the wind bed. The SynthDefs are checked by the offline render (`tools/spatial_nrt.sh`), not by a live server.

## Known limits (Lesson 07)

- Nothing is meshed and nothing collides: the boulders exist as functions and as two plane cuts (Lesson 08).
- Evaluation runs in GDScript: about 5.4 µs per evaluation of the pile, 115 ms per rebuild of a 96-column cut. Pressing H rebuilds the horizontal cut and holds one frame for that long.
- The `GRADIENT` ellipsoid estimate is closer to the true distance outside but has no finite Lipschitz bound; the rock files use `SCALED_SPHERE`, which underestimates by up to 37 % outside an ellipsoid of radii 1.7, 1.05, 1.35 (Lesson 07 O4).
- `noise_slope_per_frequency` (6.0) rests on 200 000 random samples of the 2-octave noise (largest found 5.84); it is a measurement, not a proof.
- `SdfSmoothUnion` folds its children in order; three overlapping children give order-dependent fillets. `SdfRepeat` is exact only while the child lies inside half a period around its cell center. `SdfIntersection.bounds()` returns the merged, not the intersected, box.
- The |∇f| shown in the slice comes from finite differences on the grid: it falls toward 0 on ridges of the field (the medial axis), where neighbors lie on opposite slopes.

## Known limits (Lesson 08)

- The mesh is rebuilt on the main thread: about 0.92 s (GPU pass 1) or 1.28 s (CPU) for the boulder pile at 0.15 m, mostly sampling in GDScript (decision 0009; Lesson 08 E4).
- Surface nets rounds creases and drops features thinner than one cell. Where stones of a union touch, the mesh can be nonmanifold (8 edges at 0.15 m); 22 triangles at 0.15 m face against their vertex normals.
- Headless runs have no `RenderingDevice`; the GPU path and the GPU–CPU comparison run only in windowed runs (`tools/mesher_compare.sh`, `test_08_surface_nets.gd` without `--headless`).
- Footsteps on the boulders are classified by the terrain material under them, not as rock.
- R and J have no gamepad binding; no gamepad button is free.

## Known limits (Lesson 09)

- Curvature costs 26 `evaluate()` calls per vertex: about 620 ms for the boulder pile at 0.15 m, on top of the Lesson 08 rebuild (decision 0010).
- Where two stones of a union meet, f has a crease: the gradient there is a difference across the kink, can nearly vanish (smallest |∇f| about 1e-5), and H and K reach values like −9 × 10⁶ /m. The shader clamps them by its smoothstep thresholds; a later lesson that reads curvature (Lesson 15, holds) must reject such vertices.
- Curvature is per vertex and interpolated across triangles: features smaller than a cell (0.15 m) do not show.
- U and I have no gamepad binding.

## Known limits (Lesson 10)

- The GLSL formulas (`sdf_library.gdshaderinc`) are a hand-written copy of the GDScript ones; the composition is generated (decision 0011). A new SDF class needs a branch in `SdfGlsl._emit_node()` and a GLSL function; until then it is reported in `unsupported` and drawn as empty space.
- `FastNoiseLite` is not mirrored. Its values are baked into a 3D texture with 0.1 m texels and read with trilinear filtering; the gradient of that interpolant jumps at texel faces, so normals and curvature use steps of 0.05 m and 0.1 m (Lesson 10 O3). Baking costs about 35 ms per volume, on the main thread, at every rebuild.
- Each `RaymarchVolume` compiles its own shader at load time.
- The proxy casts no shadow; the raymarched rocks receive shadows (through `LIGHT_VERTEX`) but cast none (Lesson 10 E3). No collision: raymarched rocks cannot be walked on.
- Only uniform node scale is supported; the march runs in the node's local frame.
- The GPU time of a viewport (`viewport_get_measured_render_time_gpu()`) reads 0 on the Metal backend; performance is measured as frame time with vsync off (`tools/raymarch_perf.sh`).
- P, X and Z have no gamepad binding.

## Known limits (Lesson 11)

- The walk cycle is a placeholder: joint angles are sines of a phase. Nothing reads the ground. The stance foot slides (mean 1.37 m/s, up to 3.0 m/s against the ground at 3 m/s walking) and, while walking, the lowest sole point stays 0.016 m or more above the capsule's floor. Lesson 12 places the feet by raycasts and IK.
- The rig is visual only. Collision is still the Lesson 00 capsule.
- All rest rotations are the identity. Rigs from modeling programs point each bone's y axis along the limb (Exercise E4).
- E has no gamepad binding.

## Known limits (Lesson 12)

- Stepping is driven by the walk phase, which moves with distance only. Turning on the spot does not step: the planted feet stay and the legs twist until a foot is 0.9 m from its home point (`replant_distance`). Stopping mid-swing leaves the swing foot where the interpolation stood, on the line from lift-off to target (exercise E2).
- One vertical ray per swinging foot, through the landing point only. The ray does not see the edge of a step under the toes or heel, and the swing arc does not test for obstacles between lift-off and landing (exercise E3).
- The pelvis only lowers; it never rises above the walk cycle's height. When a target stays out of reach after the 0.35 m limit (after a drop from the stair row), the leg points at the target and the ankle misses it (up to 0.072 m measured).
- The knee pole is the body's heading; there are no joint limits besides the ankle tilt (30°).
- `TwoBoneIK3D` places the thigh and shin as `TwoBoneIk` does (knees within 2e-7 m), but leaves the foot's local rotation from the walk cycle: foot orientations differ by up to 34° between the two solvers. Its result is visible only inside `Skeleton3D.skeleton_updated`.
- Ray hits come from the collision shapes (terrain triangles, boulder trimesh), not from `Terrain.height_at()`: plants lie within 0.02 m of the analytic height.
- Q and Y have no gamepad binding. Every letter key A–Z is now bound; later lessons need digits, function keys, or modifiers.

## Known limits (Lesson 13)

- The margin is static: it ignores the velocity of the center of mass. While walking, c is outside the polygon on 93 % of the ticks at 3 m/s (flat floor). A capture point is exercise E5.
- Contact is "planted, or the lowest sole corner within 0.02 m of a ray hit". A low swing foot counts as support (39 % stable ticks at 1 m/s); a heel or toe over an edge counts as fully supported.
- The ground projection is vertical and the polygon flat (y dropped); on slopes the soles' tilt is ignored (exercise E3).
- With the `TwoBoneIK3D` solver the monitor reads the pose before the modifier; the leg segments use the walk cycle's angles.
- A push sways the rig only; the capsule, the camera and the physics do not move, and no push makes the body step or fall.
- Keys 1, 2, 3 have no gamepad binding.

## Known limits (Lesson 14)

- The weight shift and the crouch move the rig inside `BodyMesh`; the capsule, the camera and the collision do not move.
- The crouch lowers the rig straight down: the trunk stays vertical and the knees go forward (exercise E5). It is limited by the reach of `FootRig`'s rays (`ray_up` 0.6 m above the rig): at the spawn an unplanted foot loses its landing target between 0.50 and 0.55 m of depth.
- Lesson 13's `center_height` ("CoM above feet") is measured in the rig's frame and rises when the rig is lowered; the Lesson 14 HUD shows the height above the soles instead. `SwayPendulum.height` still uses `center_height`.
- `StanceController` adds to the rig's position every tick and relies on `BalanceMonitor` resetting it first; without a running monitor the offsets accumulate.
- The support polygon at rest is not centered under the body (staggered feet): the same trigger travel gives different margins on the two sides.
- Keys 7, 8, 9 have no gamepad binding. Free gamepad buttons left: Start, Guide. D-pad up carries two actions, `cycle_tick_rate` (Lesson 02 scene only) and `toggle_crouch` (Lesson 14 on); no scene reads both.

## Known limits (Lesson 15)

- Holds come from mesh vertices (cell 0.08 m on the climbing face); a curvature peak between vertices, or a feature smaller than a cell, gives no hold. The search (about 12 ms) runs at load and after a threshold change; meshing and curvature take about 1.25 s at load.
- Union creases fail the H test (H ≪ 0); the centers of sharp convex creases fail the upper H limit, but points within 0.004–0.008 m of such a ridge pass both tests with ‖∇f‖ 0.72–0.95 (Lesson 15 P3). The climbing face has no sharp crease.
- One climbing face per rock (`face_normal`); the rock must stand upright, turned about +y only, at scale 1. `ClimbController` treats the face as the plane through the mean of the holds.
- The capsule is kinematic while climbing: it does not collide, and nothing stops the body from passing through other geometry between holds. The mantle is a scripted motion.
- No dynamics: no momentum, no grip force, no fall from a lost hold. `hand_pull` is reported, not enforced. The Lesson 13 margin is negative on the wall at all times (measured −0.284 to −0.047 m over a climb).
- The feet choose their holds by themselves when no hand moves. A limb in MOVE can fall short of its path by about a centimeter (the arc is not checked against the reach ball); limbs on holds are in reach on every tick (residual below 10⁻⁶ m over the scripted climb).
- FABRIK (F2) with the default 10 iterations leaves the hand up to 3.4 mm from its target over the scripted climb; from cold starts it needs more iterations for folded and fully stretched arms.
- The Lesson 14 weight shift and the sway still move the rig while climbing; `_pose()` writes every joint relative to the rig, so they do not move the climbing body.
- A threshold change during a climb leaves the limbs on holds of the previous search.
- The knob grids of `climbing_face.tres` are centered at mid-height; their two lowest rows (6 knobs) lie in the ground of the lesson scene. `ClimbableRock` leaves out holds less than `ground_clearance` (0.05 m) above `ground`; the search itself runs in shape space and finds them.
- Keys F1 and F2 have no gamepad binding. Free gamepad button left: Guide.

## Known limits (Lesson 16)

- The lying crawl capsule is horizontal. The fit test accepts it while tan θ ≤ 0.02 / e (e the distance of the axis's uphill end from the origin): 4.6° facing uphill and 1.6° facing downhill (measured: fits at 4.75° and 1.66°, refused at 4.80° and 1.68°); across a slope it fits at any angle (tested to 30°), because its radius is no larger than the standing capsule's. A crawl therefore starts only on almost level ground or along a contour (Lesson 16 P2, O7; exercises E3, E4).
- While scrambling the collision shape is the upright crouch capsule; the hands and feet reach about 0.6 m up and down the slab from its axis and are not covered by it. Its origin floats 0.17 m above a 48° slab.
- Each shape changes in one tick; the drawn body follows: after a request to crouch the head is above the shape for 0.22 s, after a request to crawl for 0.38 s (exercise E2). The rounded ends of the crawl capsule leave the head's top front up to 0.08 m outside; the walking legs of the upright postures swing outside their capsules near the ground, as in Lessons 00–15.
- The gait is static: no momentum, no slip of a contact. It moves at about 0.37 m/s on the level and spends a fifth of the time waiting. The lift test runs at the moment of a lift only; the center of mass can leave the triangle during the swing that follows (6 of 245 ticks "outside" in a measured crawl).
- Turning on the spot advances the gait by the arc of the turn; through a turn in the passage and the turn back (stick along the passage) planted limbs stay within 0.02 m of their contacts. In the 1.1 m passage the lying capsule turns at most 16.6°. A stick more than 96° from the facing backs the crawl up without a turn. After a reversal of direction, limbs planted while backing lie behind their home points, and the limb error reaches 0.09–0.20 m until their next swing. A limb waiting at the reversal keeps its wait time, so the first lift after it can reach `hold_timeout` and go ahead unstable (Lesson 16 O4, E9).
- A scramble always faces up the slope; descending, the body backs down (exercise E7). The probe looks 0.6 m ahead along the stick and sees one slope; a slab with a rough or curved surface, or one narrower than the probe's reach, is not tested.
- Key 0 does not start a climb from a low posture; a climb does not start a crawl. `PostureController` refuses every request while `ClimbController` is not walking; key 4 then toggles the Lesson 14 stance only (the climb's crouch), and after the climb the upright posture follows the stance through `request()`.
- `/body/posture` is sent on change only; no SuperCollider file reads it in this lesson.
- No standard gamepad button is free: Guide is `toggle_crawl`. F4 has no gamepad binding.

## Known limits (Lesson 17)

- Only the Terrain, the boulder pile and the climbing face switch. `BoxCourse` nodes (`Slab`, `CrawlGap`, `StepRow`) rebuild their meshes and collision when their `material` changes and keep the built-in light; the raymarched `Formations` (Lesson 10), the body and the color strip are not switched either.
- `light()` does not receive the material's `SPECULAR`; the custom GGX uses `light_f0` (0.04) everywhere. On the terrain (`SPECULAR` 0.3, built-in f0 0.0144) the custom GGX is brighter than the built-in light (start view: 96.8 against 93.2 of 255). Godot's built-in Fresnel also lowers its grazing limit to 50 f0 when f0 < 0.02; the custom Schlick form keeps 1.
- The custom Smith term is the exact height-correlated G2; Godot's built-in uses Hammon's approximation. On tilted quads the whole pixel differs by at most 0.36 % (roughness 0.5), the specular term alone by up to 21 %.
- The GGX model adds Lambert and GGX without energy exchange: with ρ = 1, roughness 0.92, f0 0.04 the sum reflects 1.016 (normal view) to 1.049 (80°). The single-scatter GGX lobe loses energy at high roughness (0.40 at roughness 0.92, f0 = 1, normal view). Exercises E5 and E8.
- Wrap lighting answers light from below the horizon, but the shadow map darkens much of a closed object's far side through `ATTENUATION`; on the gallery rock wrap adds light down to N·L ≈ −0.4.
- The ground material's noise is sampled in world space, so the five gallery tiles show different noise patches; the five rocks are identical. The gallery's rock collision is one shared trimesh; tiles and plinths collide; nothing in the gallery is generated into the `.tscn` file.
- Lit shaders are generated at run time (and in the editor, by the `@tool` gallery); the shader editor cannot show the generated code. A base shader that defines `light()` is refused.
- `VIEW` is computed from the pixel's position relative to the camera, also for an orthographic camera; measurements with an orthographic camera need the camera far away (the pixel test uses 2000 m).
- F5, F6, F7 have no gamepad binding; no standard gamepad button is free.
