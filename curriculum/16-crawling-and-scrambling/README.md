# Lesson 16. Crawling and scrambling

Lesson scene: `game/scenes/lessons/16_crawling_and_scrambling.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–15 are unchanged; the Lesson 15 scene has no gap, no slab, one collision shape and no crawling.

Complete Lesson 13 exercise E3 before reading this lesson; it contains one solution. (P5 and `CrawlController._lean()` derive the offset d tan θ between the vertical projection of the center of mass and its projection along the slope's normal, and the lesson keeps the vertical projection.)

## 1. Orientation

Lessons 11–15 built a body that walks, balances on two feet and climbs a face with four limbs on holds. This lesson lowers the body to the ground. It answers four questions:

1. Which collision shape does each posture need, and how does the body know that a shape fits before it takes it? (shape queries, headroom)
2. What is the support polygon of four contacts, and where must the center of mass lie before one of them lifts? (Lesson 13's convex hull and signed distance, applied to four triangles)
3. In which order do four limbs step so that three always carry the body? (a static gait: the lateral sequence, the swing fraction, a weight shift)
4. What changes on a slab steeper than the walking limit? (the vertical projection of the center of mass on a slope, a lean, `floor_max_angle`)

The method: `PostureController`, a subclass of Lesson 14's `StanceController`, adds two postures to standing and crouched: crawling, on hands and knees, and scrambling, on hands and feet. Each posture has a collision shape: the Lesson 00 capsule, a shorter upright capsule, or a capsule lying along the body. A request for a posture first tests the new shape at the player's position with a shape query; under a roof the request is refused, with a reason on the HUD. In the low postures `CrawlingPlayer` moves at a walking pace of 0.6 m/s or less and `CrawlController` moves the four limbs in a fixed order, one at a time. Before a limb lifts, the center of mass must lie over the triangle of the other three contacts; if it does not, the limb waits, the body stops, and a sideways weight shift carries it over the triangle. A scramble starts by itself when the stick pushes toward ground steeper than the walking limit (45°) and no steeper than 55°; while the body scrambles, the capsule treats such ground as floor. The scene has a passage 0.9 m high (`CrawlGap`) and a slab of 48° (`Slab`).

Goal served (`plan.md`): "a humanoid player that can walk, crawl, climb, and balance ... the main focus of the player being balancing in various stances"; "travelling up rocky formations in a place like Joshua Tree". The four-point gait is a balance problem: every lift is decided by the margin of Lesson 13.

Files:

| File | Role |
|---|---|
| `game/src/crawl/crawling_player.gd` | `CrawlingPlayer` (extends `ClimbingPlayer`, Lesson 15): three collision shapes, `fits()`, `headroom()`, the crawl and scramble movement. |
| `game/scenes/crawling_player.tscn` | `climbing_player.tscn` with `crawling_player.gd` as root script. |
| `game/src/crawl/posture_controller.gd` | `PostureController` (extends `StanceController`, Lesson 14): the four postures, guarded transitions, the automatic scramble, `/body/posture`. |
| `game/src/crawl/crawl_controller.gd` | `CrawlController` (Node3D): gait schedule, lift test, weight shift, slope lean, limb contacts and pose. |
| `game/src/crawl/crawl_balance_monitor.gd` | `CrawlBalanceMonitor` (extends `ClimbBalanceMonitor`, Lesson 15): the support polygon from the planted limbs. |
| `game/src/world/crawl_gap.gd` | `CrawlGap` (`@tool`, extends `BoxCourse`, Lesson 02): floor, two walls, a roof, two ramps. |
| `game/src/lessons/crawling_and_scrambling.gd` | Scene root. Extends `climbing.gd` (Lesson 15); keys F3, F4; places the gap and the slab; four lines in `HUD/RockLabel`. |
| `game/scenes/lessons/16_crawling_and_scrambling.tscn` | The Lesson 15 scene with the crawling player, `PostureController` and `CrawlBalanceMonitor` in place of the Lesson 14–15 scripts, and three new nodes: `CrawlGap`, `Slab` (a Lesson 02 `RampTower`), `Crawl`. |
| `game/project.godot` | Input actions `toggle_crawl` (F3, gamepad Guide) and `toggle_crawl_debug` (F4); `run/main_scene`. |
| `game/tests/test_16_*.gd` | The gait schedule, the four-contact margins, the lean, the kneeling leg; the scene: the gap, the refusals, the turn, the drawn body inside its shape, the slab, the keys, key 4 on the climbing face and the input map. |
| `docs/decisions/0016-postures-and-four-point-gait.md` | Why the shapes are tested before use, why the gait is static, why scrambling raises the walking limit. |

Controls: F3 / Guide drops to a crawl, or rises from a crawl to the upright posture it came from. 4 / D-pad up (Lesson 14) switches between standing and crouched, and rises from a crawl to crouched; on the climbing face it pulls the hips in, as in Lesson 15, and the posture follows the crouch after the climb. Scrambling has no key: push the stick toward the slab. F4 hides or shows the collision shape and the crawl lines. The triggers (5 / 6) shift the weight as in Lesson 14; while crawling and scrambling their shift adds to the gait's. Guide was the last free standard gamepad button.

The HUD (`RockLabel`, bottom right) gets four lines: the posture and the reason of the last refusal; the shape and its height, the headroom, and the slope under the body / ahead of it; the gait phase, the limb in the air ("waits" while a limb waits), the sideways shift and the number of contacts; the lifts (and how many went ahead with the center of mass outside), and the largest limb error ("crawl error"; the Lesson 15 climb line has its own "limb error"). The balance margin is the one on the Lesson 13 line ("balance: ... margin").

Reading:

- R. B. McGhee, A. A. Frank, "On the stability properties of quadruped creeping gaits", *Mathematical Biosciences* 3, 1968: creeping gaits, with one leg lifted at a time, and their static stability margin, the distance from the ground point of the center of mass to the edge of the support polygon (Lesson 13's margin).
- Milton Hildebrand, "Symmetrical gaits of horses", *Science* 150, 1965, and "The quadrupedal gaits of vertebrates", *BioScience* 39(11), 1989: footfall sequences (lateral and diagonal), duty factor.
- Keenan Crane, *Discrete Differential Geometry: An Applied Introduction* (`discreteDifferentialGeometry.pdf`): §5.1 "Vector Area", pp. 85–87, the signed area of a polygon from cross products (P3, as in Lesson 13); §4.6.1, p. 68, the gradient as the direction of steepest ascent (P7: which way is up the slab); §3.1–3.2 for the normal of a graph surface, as in Lesson 01.
- Godot documentation, class references `PhysicsDirectSpaceState3D` (`intersect_shape()`, `cast_motion()`), `PhysicsShapeQueryParameters3D`, `CharacterBody3D` (`floor_max_angle`). Full entries: `docs/references.md`.

Three earlier exercises touch this lesson. Lesson 13 E3 compares the vertical projection of the center of mass on a slope with the projection along the ground normal; P5 derives the offset between the two and keeps the vertical projection, as Lesson 13 does (the notice at the top). Two stay open: Lesson 14 E4 asks for an uphill lean of the standing body, and `CrawlController` leans the four-point body only; Lesson 15 E6 gives the feet to the player while climbing, and here the gait moves every limb.

## 2. Predict

Notation: the player's origin lies at the bottom of the body; in a crawl it lies between the hands and the knees. "Along" is the body's horizontal facing, "right" its right. A shape is tested `fit_lift` = 0.02 m above its place.

- **P1. Shapes and clearances.** The standing capsule has radius 0.35 m and height 1.8 m. The crouch capsule has the same radius and height 1.55 m. The crawl capsule has the same radius again, length 1.65 m, lies along the facing with its lowest line at the origin's height, and has its center 0.225 m behind the origin. For each shape give the height of its top, its width, and how far it reaches behind and ahead of the origin. Which can enter the gap (roof 0.9 m above the floor, walls 1.1 m apart)? `fits()` tests a shape 0.02 m above the floor: under which lowest roof does it accept each shape, and under which lowest roof does a body already in that posture pass? Name a roof under which a crouched body walks through but cannot stand up. The drawn body measures 1.72 m standing (walking), 1.52 m crouched (walking), and, crawling, 0.69 m high, from 1.02 m behind the origin to 0.57 m ahead, 0.32 m to each side. Are the shapes large enough? Where does a capsule's rounded end leave a corner of the body outside?
- **P2. Turning and tilting a lying capsule.** (a) In the passage the body turns about its origin. Let e be the distance from the origin to the far end of the capsule's axis, r the radius, w the passage's width. Show that a turn by a brings the capsule to a wall when e sin a + r = w/2. Compute the largest turn for this capsule, for the same capsule centered on the origin, and for a capsule of radius 0.3 m and length 1.2 m centered on the origin. (b) On a plane of slope θ the body stands on its upright capsule of radius r = 0.35 m. The capsule's rounded bottom touches the plane off the vertical through the origin, so the origin floats r (1/cos θ − 1) above the plane, measured along the vertical (P5 d derives this). `fits()` tests the lying capsule 0.02 m above the origin. Find the steepest θ at which it fits facing uphill, facing downhill, and facing across the slope. For which radii ρ of the lying capsule does it fit across the slope at every θ?
- **P3. Four contacts.** Crawling at rest, the contacts measure: hands at right ∓0.16, along +0.219 m; knees at right ∓0.12, along −0.219 m. (a) Compute the area of the polygon (the shoelace formula, DDG §5.1). (b) Each lift leaves a triangle of three contacts. Show that the four triangles have one common point, and find it. What does this mean for a body that keeps its center of mass still? (c) With the ground point of the center of mass at right +0.059, along −0.047 m (the body shifted right), give the sign of its margin against each triangle. Which limbs may lift? (d) On the line along = −0.047 m, find the interval of "right" in which the center of mass may lie to lift the left leg, and the one to lift the right leg. How far must it move between the two lifts?
- **P4. The gait schedule.** Each limb's swing starts at a phase: left leg 0, left hand 0.25, right leg 0.5, right hand 0.75 (`SWING_START`), and lasts `swing_fraction` β of the cycle. The phase advances by the distance moved divided by `stride_length` (0.4 m). (a) For β = 0.2, 0.25 and 0.3, what is the largest number of limbs in the air at once? (b) At the crawl speed of 0.6 m/s and without waiting, find the duration of a cycle and of a swing, the ticks per swing at 60 Hz, and the lifts per meter. (c) A limb lands 0.5 (1 − β) · stride ahead of its home point, along the motion. Show that this puts the home point in the middle of its stance. (d) With β = 0.3, what does the lift test of the left hand see at phase 0.25, and what follows?
- **P5. On the slab.** While scrambling, the contacts lie in a plane of slope θ = 48° and the center of mass c lies d = 0.38 m above it along the normal n. (a) Show that the vertical line through c meets the plane d tan θ down the slope from the foot of the normal through c. Compute the distance, and its horizontal part. (b) The hands lie 0.319 m up the slope and the feet 0.569 m down it from the base point. How long is the polygon in Lesson 13's ground plane, where the heights are dropped? Is c over it without a lean? (c) `CrawlController._lean()` moves the body up the slope by `slope_lean` · d tan θ, with `slope_lean` 0.5 and at most `max_lean` 0.3 m. Compute the lean. (d) While scrambling, the collision shape is the upright crouch capsule, its lowest point at the origin. How far above the slab, along the vertical, does the origin float?
- **P6. The posture machine.** Draw the four postures as states and the transitions of section 3.2 (key 4, F3, the automatic scramble) as arrows. Mark the transitions that need the fit test. Which are refused under the 0.9 m roof, and with which reason? What would go wrong if the posture changed first and the shape were tested afterward? The shape changes in one tick, while the drawn body moves to its new pose over a few tenths of a second: for a change to a lower shape and for a change to a taller one, which leaves part of the drawn body outside its shape?
- **P7. The walking limit.** In Lesson 02 a contact steeper than `floor_max_angle` (45°) is a wall. (a) What stops an upright capsule pushed into a 48° slab? (b) The scramble probe casts a ray down 0.6 m ahead of the origin and asks for ground more than 0.05 m above or below the feet, with a slope between 45° and 55°. About how far from the slab's foot does the scramble start, on level ground? (c) `CrawlController` places the limbs by rays. Why does the capsule need a larger `floor_max_angle` at all? (d) The scrambling body turns to face −(n_x, 0, n_z), with n the floor normal. Derive this from the normal of a graph surface, (−h_x, 1, −h_z) (Lesson 01), and the gradient as the direction of steepest ascent (DDG §4.6.1).

## 3. Read

### 3.1 `crawling_player.gd`

Read the header: the class chain from `Player` to this file, the three shapes, the three movement modes. Then:

- The exports. `crouch_height`, `crawl_radius`, `crawl_length` and `crawl_offset` define the shapes (P1); `fit_lift` the lift of the fit test; `crawl_speed`, `scramble_speed`, `turn_rate` the low movement; `scramble_max_angle_degrees` the scramble's walking limit; `camera_heights` the camera pivot per shape.
- `_ready()`: the stand shape is read from the scene, the other two are built from the exports. Read its Q/A. The three queries are built once (the Lesson 02 pattern of `_ray_query`).
- `shape_transform()`: how a capsule, which lies along its own y axis, is laid along the facing and moved back by `crawl_offset`. `shape_height()` and `shape_radius()` are used by the posture controller, the HUD and the tests.
- `fits()`: the fit test. Read both Q/A blocks with P1 and P6 beside you. `intersect_shape()` returns the bodies the shape would overlap; an empty result means it fits.
- `set_body_shape()`: swaps the shape and its transform. It does not test; `PostureController` calls `fits()` first.
- `headroom()`: a sphere swept straight up with `cast_motion()`, which returns the fraction of the motion that is free. The HUD shows it.
- `_low_move()`: the movement in the low modes, the counterpart of `Player._physics_process()` (Lesson 02). Read the Q/A on `speed_scale`: a limb waiting for the balance stops the body in one tick.
- `_crawl_velocity()`: the body turns toward the stick only when the turned shape fits (P2), then moves along its facing. `turn_blocked` records a refused turn. Read the Q/A on where "behind" begins: a stick behind the body backs it up without a turn (O4).
- `_scramble_velocity()`: the body faces up the slope (P7 d) and moves in any direction.
- `_on_mode_changed()`: the walking limit, the planted feet of `FootRig`, and the last position of `BodyPlayer` (the same reason as `ClimbingPlayer.climbing`'s setter in Lesson 15).

### 3.2 `posture_controller.gd`

A subclass of `StanceController`: `_physics_process()` runs the Lesson 14 shift and crouch first (`super()`), then the automatic transitions. Read the header's table of postures, shapes and movement modes, and the list of transitions. Then:

- `shape_of()` and `mode_of()`: the two tables as functions (the math test checks them).
- `request()`: the guard. A climb in progress refuses everything. A posture with another shape asks `fits()`; read the Q/A on the two refusal words. Only then does `_apply()` change the posture.
- `toggle_stance()` replaces the Lesson 14 method of the same name, so key 4, read by `analog_stances.gd`, reaches the new posture machine with no change to the Lesson 14 root. While the body climbs, it calls the Lesson 14 method (`super()`): the climb reads that crouch, as in Lesson 15. `_follow_stance()` brings the posture to the stance after the climb; read its Q/A. `toggle_crawl()` is F3.
- `_apply()`: posture, shape, movement mode, the Lesson 14 stance (crouched only in CROUCH), the signal `posture_changed`, and `/body/posture` through the `Osc` autoload (Lesson 04).
- `_automatic_transitions()`: read both Q/A blocks with P7. The probe looks along the stick while it pushes; a scramble needs both the push and a slope in (45°, 55°]. "too steep" appears when the probe sees a steeper slope and the capsule touches a wall. A scramble ends when the ground under the body and ahead of it is walkable (below `walkable_degrees`, 40°); if the posture it came from does not fit, the body crawls.

### 3.3 `crawl_controller.gd`

The largest file of the lesson. Read the header: how the files relate, the gait, the body, the order inside one tick (`Crawl` ticks after `Player`, as `Climb` does in Lesson 15). Then in this order:

- `swing_progress()` and `lift_in()`: the gait schedule as two static functions (P4). `lift_in()` finds the limb whose swing starts within one tick's step; read its Q/A on the half-open interval.
- `support_margin()`: Lesson 13's `convex_hull()` and `signed_distance()` on the planted limbs other than one (P3).
- `_test_lift()`: the lift test. Read its two Q/A blocks. The phase stops just before the swing; `holding` and `waiting_limb` describe the wait; after `hold_timeout` (1 s) the limb lifts anyway and `unstable_lifts` counts it.
- `_low_tick()`: the order of one tick. The surface normal follows the plane of the contacts (`contact_normal()`, read its Q/A), the phase advances by the distance moved plus the arc of a turn, the lift test, the limbs, the shift, the body, the pose.
- `_update_limb()`, `_update_target()`, `_arc_height()`: a limb's swing and landing. The landing lead is P4 (c); read why a crawling knee slides instead of lifting.
- `_frame()`, `_span()`, `_home()`: the surface frame (normal, forward along the surface, right, a base point in the plane of the contacts), kept in one `SurfaceFrame` object that `_frame()` fills on every tick, and the home point of each limb.
- `_update_shift()`: the gait's weight shift, a `CriticalSpring` (Lesson 14) toward ±`shift_range`, switching sides `shift_lead` ahead of the next pair of swings (P3 d).
- `_place_body()` and `_lean()`: pelvis and shoulders, and the slope lean of P5. Read the two Q/A blocks of `_lean()`.
- `_pose()`: the torso from the pelvis to the shoulders, the head (`head_lift`), the arms by `TwoBoneIk` (Lesson 12), the legs by `TwoBoneIk` while scrambling and by `kneeling_leg()` while crawling. Read the Q/A blocks of `kneeling_leg()`: two-bone IK places the end joint, and a kneeling leg must place the middle one.
- `_take_snapshot()` and `_blend_pose()`: a posture change blends the bone poses over `transition_time` (0.4 s); read the Q/A.
- `_draw_debug()` and `_draw_shape()`: the collision shape (yellow) in every posture; while low, hand contacts (blue), knee or foot contacts (green), swing targets and paths (orange) and the torso line (white).

### 3.4 `crawl_balance_monitor.gd`

A subclass of Lesson 15's `ClimbBalanceMonitor`, which is a subclass of Lesson 13's `BalanceMonitor`. While the body crawls or scrambles, `measure()` rebuilds the polygon from `CrawlController.contact_points()`: four corners while all limbs stand, three while one swings. The margin and the state follow Lesson 13, and the OSC messages of Lesson 13 carry them unchanged. `support_count` is the "support" number on the HUD.

### 3.5 `crawl_gap.gd` and the slab

`CrawlGap` is a `BoxCourse` (Lesson 02): `_build()` adds a floor, two walls, a roof whose underside lies `roof_height` above the floor, and two ramps of `ramp_angle_degrees` (15°). The floor is flat, so the clearance is exact whatever the terrain does; the root sets the node's height to the highest terrain point under `floor_rect()`. Read the `_add_ramp()` Q/A, which reuses `RampTower`'s frame.

The slab is a `RampTower` from Lesson 02 with a platform 2 m high and 3 m wide and ramps of 48° (toward the gap), 60°, 35° (the walkable way down, on the far side) and 85°. No new class: a ramp steeper than 45° and no steeper than 55° is a slab.

### 3.6 The scene and the root

`16_crawling_and_scrambling.tscn` is the Lesson 15 scene with these changes: the root script (`crawling_and_scrambling.gd`) and name; the player from `crawling_player.tscn`; the `Stance` node's script swapped for `posture_controller.gd`, with `climb = ../Climb`; the `BalanceMonitor` node's script swapped for `crawl_balance_monitor.gd`, with `crawl = ../Crawl`; two nodes `CrawlGap` at (−7, terrain, 52) and `Slab` at (−15.5, terrain, 52), both turned so that their courses run along x; a node `Crawl` after `Climb`, with `player`, `posture` and `monitor` assigned; a taller `RockLabel`. The course runs west from the gap's entrance (x −4.6) to the slab's foot (x −12.2).

`crawling_and_scrambling.gd` places the gap and the slab on the terrain (read the two Q/A blocks) and turns the camera toward the gap's entrance. Its `_unhandled_input()` refuses a climb from a low posture before the Lesson 15 handler sees key 0 (read the Q/A), and handles F3 and F4. `_update_hud()` appends the four lines; read the Q/A on their length.

### 3.7 The tests

`test_16_crawl_math.gd` checks the schedule (one limb in the air for β ≤ 0.25, two for 0.3; the lateral sequence over 50 cycles of random steps), the four-contact margins against an independent edge formula, the crossing of the diagonals (P3 b), `plane_normal()`, the lean (P5 a, c), `kneeling_leg()` and the posture tables. `test_16_crawl_scene.gd` runs the scene in real-time physics for about 40 s: standing and crouched the body stops at the roof; crawling it passes; under the roof the three refusals; on every crawling tick three or four contacts, planted limbs within 0.06 m of their contacts, and the drawn body inside the crawl shape's height, width and length; the turn limit of P2, the turn back with the stick along the passage, and the planted limbs within 0.06 m after it; the slab refused upright and scrambled to the top; the keys, `/body/posture` and the input map; key 4 on the climbing face and the posture after the climb.

## 4. Run and observe

Start the lesson scene. The camera looks toward the gap's entrance; the player stands about 13 m from it, the slab beyond it. The yellow lines around the body are its collision shape (F4 hides them).

- **O1. Shapes.** Walk up the ramp onto the gap's floor in front of the roof. Press 4, 4, F3, F3, and watch the yellow shape, the body and the "shape" line. When the shape is lower than the body before, how long does the body take to come inside it? Press 1 (Lesson 13 lines) while crawling: what is the polygon now?
- **O2. The entrance.** Standing, push into the gap. Where does the body stop, relative to the roof's edge? Crouch (4) and push again. Then crawl (F3) and push. Halfway under the roof, press 4, then F3. Read "headroom" and the reason after "posture:".
- **O3. The gait.** Crawl straight through the passage. Watch "air" cycle through the limbs and "waits" appear. Count the lifts per meter (the floor is 4.8 m long). Watch the crosses on the floor: when does a cross turn into a swing path? Watch "shift" and the body's sway.
- **O4. Turning in the passage.** Under the roof, push the stick sideways. How far does the body turn? Then push the stick the other way: what does the body do, and why (the Q/A of `_crawl_velocity()`)? Push the stick along the passage to turn back. Watch "crawl error" throughout, and once more after crawling forward from the backed-up place.
- **O5. The slab.** Leave the gap, stand up (F3) and walk to the 48° slab. Push the stick toward it and keep pushing. Where does the posture change, and when does it change back? Read "slope" (under / ahead) and count the waits on the way up.
- **O6. Balance on four and three.** While scrambling, read "support" and the Lesson 13 margin. How often does the body stand on three limbs, and how small does the margin get? Compare with the crawl through the gap.
- **O7. A crawl on the hillside.** Walk back toward the spawn, onto the slope of the hill, and press F3. Read the reason. Which question of section 2 predicted it?
- **O8. Climbing from a crawl.** Crawl on the gap's floor and press 0 (Lesson 15's climb key). Read the climb line. With sclang listening on port 57120 (Lesson 04), evaluate `OSCFunc.trace(true, true)`, which prints every incoming message except the server's status replies; change posture a few times and count the `/body/posture` messages. `OSCFunc.trace(false)` stops the printing.

## 5. Tweak

With the game running, open the Remote tab of the Scene dock, select the node and edit the property in the Inspector; or edit the scene before running. T8 must be edited in the scene, because the root places the slab once, in `_ready()`.

- **T1.** Select `CrawlGap` and set **Roof Height** to 0.75, then 0.70. Crawl through each time. Which question of section 2 gives the limit?
- **T2.** Select `Crawl` and set **Head Lift** to 0.75. Look at the head and the yellow shape. Then set the roof to 0.75 (T1) and crawl through. What does the collision shape stand for, and what happens to everything outside it? Set **Head Lift** to 0 and compare.
- **T3.** Set **Swing Fraction** to 0.3. Crawl and read "air", "support" and "lifts". Compare with P4 (d).
- **T4.** Uncheck **Weight Shift**. Crawl 2 m and read the waits and the unstable lifts. Then check it again and set **Shift Range** to 0.04. Compare with P3 (d).
- **T5.** Set **Lift Margin** to 0.03. What does a margin buy, and what does it cost?
- **T6.** Set **Slope Lean** to 0 and scramble up the slab. Compare the time and the unstable lifts with the default.
- **T7.** Select `Player` and set **Scramble Max Angle Degrees** to 47. Push into the slab. Read the posture line.
- **T8.** In the scene, select `Slab` and set the first entry of **Ramp Angles Degrees** to 52. Run and scramble up. What changes in the lean and in the crawl error?

## 6. Exercises

- **E1 ★ The next triangle.** Draw the triangle of the three contacts that will carry the body during the next swing, colored by the lift margin of the center of mass against it, and show that margin on the HUD. Use P3 to predict where the body must be before each lift, and check it while crawling.
- **E2 ★ Shrink after the body.** The shape becomes lower in one tick while the drawn body follows over a few tenths of a second (O1). Keep the taller shape until the top of the drawn body has come below the new shape's top (measure the top as `test_16_crawl_scene.gd` measures the body), then swap. Measure the delay before and after. What should happen if the body moves under a roof during the delay?
- **E3 ★★ Drop test.** The lying capsule fits only on almost level ground (P2 b, O7). Replace the fit test of the crawl shape by a sweep: start the shape 0.3 m above its place, test that it fits there, and sweep it down with `cast_motion()` to where it comes to rest; raise the body by the remaining height before swapping the shape. Measure the steepest slope on which a crawl can start, facing up and facing down.
- **E4 ★★ A tilted crawl shape.** Tilt the lying capsule into the plane of the contacts (`CrawlController.contact_normal()`), and use it while scrambling instead of the upright capsule. Test every tilt step with `fits()`. Where does the body get stuck on the course, and why?
- **E5 ★★ Gaits compared.** Add two schedules: the diagonal sequence (left leg, right hand, right leg, left hand) and a trot (diagonal pairs at once, β = 0.5). Crawl 3 m on the gap's floor with each and count the waits and the unstable lifts. Which gait can only stand up while it moves, and why can the static lift test never accept it?
- **E6 ★★ Contact sounds.** On `limb_planted`, send `/crawl/contact` with the limb, the kind of contact (hand, knee or foot), the surface weights of Lesson 05's `SurfaceClassifier` and the limb's speed at landing through `/root/Osc`, appending arguments as Lessons 05 and 13 do. In SuperCollider, make hands slap, knees thud and feet scuff. Record a crawl's messages and render them offline with `Score.recordNRT`.
- **E7 ★★ Facing on the way down.** A scramble always faces up the slab, so a descent backs down it. On gentler slabs people face down. Measure the margins facing up and facing down while descending slabs of 35°, 40° and 48° (copies of `Slab` in a scratch scene), choose a slope at which the facing changes, and implement the change with hysteresis.
- **E8 ★★★ Postures from the world.** Let the body choose its own posture: sweep each shape along the stick's direction with `cast_motion()` and take the tallest one that passes the next meter, with hysteresis so that the posture does not flicker under a sloping roof. Build a course of roofs at 1.7 m, 1.2 m and 0.8 m and compare the automatic choice with the keys.
- **E9 ★★ Backing up.** Crawl forward, back up 0.3 m and crawl forward again, and read "crawl error" (O4). Use P4 (c) to explain why a limb planted while the body backs up ends its stance far behind its home point once the body moves forward. Let the phase run backward while the body backs up (the phase step signed by the motion along the facing), so that the swings run in reverse order, and measure the crawl error again. What must change in `lift_in()` and in the lift test, and which limb lifts first after a reversal?

## 7. Reflect

- **R1.** Lesson 02 R5 asked where the decision between walking, scrambling and climbing should live. `PostureController` decides between walking and scrambling from a probe ahead; Lesson 15's `ClimbController` starts a climb on a key. Which surface quantities (slope, curvature, holds in reach, headroom) would merge them into one decision, and at which slope should a scramble give way to a climb?
- **R2.** The scramble follows the plane of its four contacts, not the normal under one point. On a rough rock (Lessons 20 and 22: detail normals, curvature on meshes), over what length does the body average the surface? Which features of a rock would a crawling body feel, and which would only the eye see?
- **R3.** The lateral sequence sounds four beats per cycle at equal intervals of phase, and the waits stretch some of them. Lesson 28 maps traversal state to music. Would you send the gait to SuperCollider as an event per lift, as the phase at 30 Hz, or both? Which of the two keeps the hesitations audible?
- **R4.** Lessons 26–27 add plants and wind. Should a bush be an obstacle to the crawl shape, a volume that slows the body, or nothing? Which query of this lesson would find it, and at what cost per tick?

## 8. Answers

<details><summary>P1</summary>

Tops: 1.80, 1.55 and 2r = 0.70 m. Widths: 0.70 m for all three. The upright capsules reach 0.35 m behind and ahead. The lying capsule's axis runs from (0.825 − 0.35) − 0.225 = 0.25 m ahead of the origin to 0.475 + 0.225 = 0.70 m behind it, and the end caps add r: it reaches from 1.05 m behind to 0.60 m ahead. Only the crawl shape enters the gap: 0.70 < 0.9 and 0.70 < 1.1.

`fits()` places the shape 0.02 m up, so it accepts a shape under a roof at least its top + 0.02 m high: 1.82, 1.57 and 0.72 m. Measured, with the body on the gap's floor: 1.821, 1.571 and 0.721 m accepted, 1.819, 1.569 and 0.719 m refused. A body already in a posture passes under a roof just above its shape: measured, the standing body stops under 1.80 m and passes under 1.81 m, the crouched body stops under 1.55 m and passes under 1.56 m, the crawling body stops under 0.70 m and passes under 0.71 m. A crouched body walks under any roof from 1.56 m up to 1.82 m and cannot stand up there (a request needs 1.821 m).

The shapes cover the measured body in height (1.72 < 1.80, 1.52 < 1.55, 0.69 < 0.70), in width (0.32 < 0.35) and along the crawl (1.02 m behind and 0.57 m ahead, against 1.05 and 0.60). A capsule's end is a half sphere: at the height of the head, 0.23 m above the axis, the front cap reaches only √(0.35² − 0.23²) = 0.26 m past the end of the axis. The head's top front lies outside the cap by up to 0.080 m (measured, the largest distance of any segment's end sphere beyond the capsule). It leaves the shape only at that corner, where a roof's edge or a wall's top would have to meet both the head's height and its reach. The standing capsule of Lesson 00 never covered the walking legs: a swinging foot reaches 0.47 m beyond it, close to the ground.
</details>

<details><summary>P2</summary>

(a) Turned by a, the far end of the axis lies e sin a to the side of the passage's middle line, and the capsule reaches r beyond it: e sin a + r ≤ w/2. Here e = 0.825 − 0.35 + 0.225 = 0.70 m and w/2 − r = 0.20 m: a = asin(0.20 / 0.70) = 16.6°. Centered (e = 0.475 m): 24.9°. Radius 0.3 m, length 1.2 m, centered (e = 0.30 m, w/2 − r = 0.25 m): 56.4°. The near end (0.25 m ahead) does not bind. Measured: the turn stops at 14.3°; the next step of 2.4° (`turn_rate` 2.5 rad/s for one tick) would pass 16.6°, and `fits()` refuses it.

(b) Let P be the point of the plane straight below the origin. The lying capsule's axis lies 0.02 + r = 0.37 m above the origin, so h = 0.37 + r (1/cos θ − 1) above P. A point at height h above P and at horizontal distance x up the slope from P lies (h − x tan θ) cos θ = h cos θ − x sin θ from the plane, and h cos θ = 0.37 cos θ + r (1 − cos θ) = 0.35 + 0.02 cos θ. The capsule comes closest to the plane at the end of its axis that lies farthest up the slope, x = e, and fits while 0.35 + 0.02 cos θ − e sin θ ≥ r = 0.35, that is, while tan θ ≤ 0.02 / e. Facing uphill the front end binds, e = 0.25 m: θ ≤ 4.6°. Facing downhill the back end, 0.70 m behind the origin, lies up the slope: θ ≤ 1.6°. Across the slope the axis runs along a contour, x = 0, and the distance 0.35 + 0.02 cos θ exceeds r at every slope. For a lying radius ρ the axis lies 0.02 + ρ above the origin, and the condition across the slope reads (ρ + 0.02 + r (1/cos θ − 1)) cos θ ≥ ρ, that is, (r − ρ)(1 − cos θ) + 0.02 cos θ ≥ 0. It holds at every slope for ρ ≤ r and fails on steep slopes for ρ > r: a lying cylinder no wider than the upright capsule lies inside the space that the upright capsule's lower sphere sweeps along the contour. Measured on a tilted box: uphill the shape fits at 4.75° and not at 4.80°, downhill at 1.66° and not at 1.68°, across at every slope tested, up to 30°. The measured limits lie above the derived 4.57° and 1.64° because the body rests 0.4 to 0.8 mm higher than r (1/cos θ − 1) (measured; the size of `CharacterBody3D.safe_margin`, 0.001 m), and the limit tan θ ≤ (0.02 + δ) / e rises with that height δ.
</details>

<details><summary>P3</summary>

(a) A trapezoid: (0.32 + 0.24)/2 × 0.438 = 0.1226 m². Measured: 0.1229 m².

(b) The triangle without the left hand (right hand, left knee, right knee) and the triangle without the right knee (left hand, right hand, left knee) lie on the two sides of the diagonal from the right hand to the left knee and share only that segment. The other two triangles share only the other diagonal. All four share the crossing of the diagonals: by symmetry at right 0, and along the diagonal from the left hand (−0.16, 0.219) to the right knee (0.12, −0.219) where right = 0, t = 0.16/0.28 = 0.571, along = 0.219 − 0.438 t = −0.031 m. There the margin against every triangle is 0. A body that keeps its center of mass still can lift each limb in turn only from that one point, with no margin at all. The body must move between lifts. `test_16_crawl_math.gd` checks that the crossing has margin 0 against all four triangles.

(c) Measured, against the triangle without each limb: left hand +0.058, right hand −0.041, left leg +0.041, right leg −0.058 m; against all four contacts +0.077 m. The left limbs may lift. A computation by hand from the same contacts gives the same four numbers.

(d) Lifting the left leg leaves the right knee and both hands. On the line along = −0.047 m the left edge of that triangle runs from the left hand (−0.16, 0.219) to the right knee (0.12, −0.219): t = (0.219 + 0.047) / 0.438 = 0.607, right = −0.16 + 0.28 t = +0.010 m. Its right edge runs from the right hand (0.16, 0.219) to the right knee: right = 0.16 − 0.04 t = +0.136 m. The interval for the left leg is (+0.010, +0.136) m; by symmetry the right leg needs (−0.136, −0.010) m. Between the two lifts the center of mass must cross at least 0.020 m. The gait shifts the body ±0.08 m (`shift_range`); the center of mass follows by ±0.059 m, 0.74 of the shift, because the hands and knees stay where they are.
</details>

<details><summary>P4</summary>

(a) The swings occupy [0, β), [0.25, 0.25 + β), [0.5, 0.5 + β), [0.75, 0.75 + β). For β ≤ 0.25 they do not overlap: at most one limb in the air. For β = 0.3 consecutive swings overlap by 0.05: two limbs. The math test counts this on 10 000 phases.

(b) A cycle covers one stride: 0.4 / 0.6 = 0.667 s. A swing lasts 0.2 of it: 0.133 s, 8 ticks. Each limb lifts once per stride: 4 / 0.4 = 10 lifts per meter. Measured on the gap's floor: 16 lifts in 1.554 m (10.3 per meter) in 4.18 s, a mean speed of 0.37 m/s, of which 0.80 s spent waiting.

(c) A limb stands for (1 − β) of the cycle, while the body moves (1 − β) · stride. Landing half of that ahead of the home point, it stands from +0.5 (1 − β) · stride to −0.5 (1 − β) · stride relative to the moving home point: the home point is the middle of the stance. Here 0.5 × 0.8 × 0.4 = 0.16 m. `FootRig.lead_fraction` (Lesson 12) does the same for two feet.

(d) At 0.25 the left leg is still in the air (its swing ends at 0.3). The test sees two planted contacts, the right hand and the right knee: a segment, against which Lesson 13's signed distance is negative everywhere. The left hand waits, the phase stops, and the left leg, whose swing needs the phase to advance, never lands. After `hold_timeout` the hand lifts anyway as an unstable lift. Measured with β = 0.3 (T3): every lift is unstable.
</details>

<details><summary>P5</summary>

(a) Take the base point b at the foot of the normal: c = b + d n. The vertical line c − t · up meets the plane where (c − t up − b) · n = 0, t = d / cos θ. The point is b + d n − (d / cos θ) up; it lies in the plane, and its distance from b is d |n − up / cos θ| = d √(1/cos² θ − 1) = d tan θ. For d = 0.38 m: 0.422 m down the slope, 0.282 m of it horizontal (d sin θ). Measured at mid-slab: d = 0.379 m, d tan θ = 0.421 m.

(b) Distances along the slope shrink by cos 48° = 0.669 in the ground plane: the hands lie 0.213 m ahead of the base point and the feet 0.381 m behind it, a polygon 0.594 m long instead of 0.888 m. Without a lean c projects about 0.28 m behind the base point, inside the four-contact polygon but close to its lower edge, and the triangles of three are smaller. Measured with `slope_lean` 0 (T6): 11 of 32 lifts waited the full second and went ahead with c outside.

(c) 0.5 × 0.421 = 0.211 m up the slope, below `max_lean`. Measured: 0.211 m at mid-slab, 0.218 m at most over the scramble. The ground point of c moves 0.211 × 0.669 = 0.141 m uphill.

(d) The capsule's lower sphere, radius r, touches the slab at the point where the slab's normal passes through its center. Its center lies r / cos θ above the slab along the vertical, and the origin r below the center: r (1/cos θ − 1) = 0.35 × 0.494 = 0.173 m. Measured: 0.174 m. `CrawlController._frame()` therefore moves its base point along n onto the plane of the contacts, not onto the origin.
</details>

<details><summary>P6</summary>

Transitions: STAND → CROUCH (4); CROUCH → STAND (4); STAND or CROUCH → CRAWL (F3); CRAWL → the upright posture it came from (F3) or CROUCH (4); STAND, CROUCH or CRAWL → SCRAMBLE (automatic, push toward a slab); SCRAMBLE → the posture before it, or CRAWL when that one does not fit (automatic). 4 and F3 while scrambling are refused ("scrambling"). While climbing every request is refused ("climbing"); key 4 then changes only the Lesson 14 stance, and after the climb the upright posture follows it through a tested request. Every transition between different shapes calls `fits()`. STAND → CROUCH cannot fail (the crouch capsule lies inside the standing one: same radius, same bottom); the changes to a taller shape (CROUCH → STAND, CRAWL → CROUCH or STAND, CRAWL → SCRAMBLE) and the change to the longer crawl shape can. Under the 0.9 m roof every posture but CRAWL is refused, with "no headroom" (measured for key 4, F3 and a request for STAND; the headroom reads 0.899 m). Testing after the change would put the player in a posture whose shape overlaps the roof; `move_and_slide()` separates an overlap along whatever normal it finds, down through the floor or sideways into a wall (the Q/A of `fits()`).

A lower shape leaves the drawn body above it until the pose has come down: measured, 0.22 s after a request to crouch and 0.38 s after a request to crawl, with the head above the shape's top. A taller shape is tested before it is taken, and the body rises into it. Grow the shape before the body and shrink it after the body (E2).
</details>

<details><summary>P7</summary>

(a) The capsule's lower sphere meets the slab with the slab's normal, 48° from up: a wall contact. `move_and_slide()` stops the motion into the wall, and the capsule stays on the level ground in front of it. Measured with `auto_scramble` off: the origin stops 0.19 m before the slab's foot, the ground state stays FLOOR, and the body rises 0.12 m in 3 s, the rise of the terrain toward the slab.

(b) On level ground the probe's point must lie 0.05 / tan 48° = 0.045 m past the foot: the scramble starts 0.6 − 0.045 = 0.555 m from it. Measured: 0.589 m. The terrain before the slab rises toward it, so the feet lie below the slab's foot and the hit is 0.05 m above them sooner.

(c) The capsule carries the body; the limbs are drawn. On a wall contact gravity slides the capsule down and the stick cannot push it up the surface; on a floor contact the capsule is held, snapped to the surface, and moved along it. Without a larger limit the capsule stays at the foot of the slab, wherever the hands are drawn.

(d) The normal of y = h(x, z) is proportional to (−h_x, 1, −h_z) (Lesson 01): its horizontal part is −∇h. The gradient points in the direction of steepest ascent (DDG §4.6.1), so up the slope is −(n_x, 0, n_z), normalized. On level ground the horizontal part vanishes and the facing stays.
</details>

<details><summary>O1</summary>

The yellow shape changes in the tick of the key press; the body follows. Measured from a standing rest: after 4 the head comes below the crouch shape's top in 0.22 s; after F3 the whole body is inside the crawl shape's height in 0.38 s, within the 0.4 s pose blend (`transition_time`). The shape line reads 1.80, 1.55 and 0.70 m. With the Lesson 13 lines on, the polygon has four corners at rest (the trapezoid of P3, 0.123 m², against 0.081 m² for the two standing soles), three while a limb swings.
</details>

<details><summary>O2</summary>

Measured: standing, the origin stops 0.352 m before the roof's edge, so the capsule's front lies within 2 mm of it; crouched, at the same place. Crawling, the body passes. Under the roof the headroom reads 0.899 m (the roof at 0.9 m; `cast_motion()` leaves a fraction of a millimeter), and 4, F3 and a request to stand give "no headroom". Leaving the gap, F3 returns to the upright posture the crawl came from.
</details>

<details><summary>O3</summary>

Measured over the first 1.55 m under the roof: 16 lifts (10.3 per meter, P4 b), 4.18 s, waits 0.80 s, no unstable lift, the smallest margin at a lift 0.003 m (`lift_margin` is 0), the margin on the Lesson 13 line at least +0.007 m with a mean of +0.075 m, three contacts on 161 of 251 ticks, planted limbs within 0.031 m of their contacts (a knee: `kneeling_leg()` aims the thigh at the contact and the knee lands short of it or past it). A cross turns into an orange path when its limb lifts; the hands lift 0.06 m, the knees slide. The shift sways between −0.079 and +0.080 m (measured), changing side twice per cycle. The crawl tick took 0.12 ms on average, 0.17 ms at most.
</details>

<details><summary>O4</summary>

Measured in the order of O4 (stand, crouch and crawl from the entrance to the middle of the passage, then the three sticks): the turn stops at 14.3° after 0.30 s (P2 a: 16.6°, less one step). The phase advances by the arc of the turn, so a limb steps during it; the crawl error stays at 0.017 m.

The opposite sideways stick does not turn the body back. It points 104° from the facing, and `_crawl_velocity()` counts a stick more than 96° from the facing (wish · facing < −0.1) as "behind": the body backs up at 0.6 × sin 14.3° = 0.15 m/s without turning. Held for 3 s it backed 0.28 m (0.95 s of it waiting), and the crawl error rose to 0.088 m.

The stick pushed along the passage then turns the body back to the passage's axis in 0.17 s while it crawls 0.02 m forward. When the opposite stick was released, the right hand had waited 0.95 s for its lift; the wait goes on under the new stick, and at 1 s (`hold_timeout`) the hand lifts with a margin of −0.009 m. This is the one unstable lift of O4. Over the rest of the passage (2.06 m, 21 lifts, none unstable) the crawl error reaches 0.127 m. The backing causes it: a limb planted while the body backed up landed behind its home point (the landing lead points along the motion, P4 c), and when the body moves forward it falls farther behind until its next swing. Measured after backing 0.1, 0.2, 0.3 and 0.5 m on the straight crawl: the crawl error over the next 0.8 m reached 0.146, 0.092, 0.131 and 0.196 m, and two of the four backing runs contained one unstable lift each, after a wait of `hold_timeout`.

Without the backing step, with the stick along the passage straight after the turn (`test_16_crawl_scene.gd` repeats this case), the turn back takes 0.10 s, the crawl error stays at 0.018 m, and 0.020 m over the rest of the passage, with no unstable lift. A reversal of the motion breaks the assumption of P4 (c); E9 asks for a gait that runs backward.
</details>

<details><summary>O5</summary>

Measured from 0.6 m before the slab's foot, the stick held toward it: the posture changes to scrambling 0.59 m before the foot (P7 b), the slope line reads 48° / 48° on the slab, and the body reaches the top in 13.8 s, rising 2.12 m, with 32 lifts and 2.3 s of waiting. One lift goes ahead unstable (margin −0.011 m) at the foot, where the legs stand on the level ground and the hands on the slab. On the top, with level ground under and ahead, the posture returns to standing: two posture changes in all, two `/body/posture` messages.
</details>

<details><summary>O6</summary>

Measured over the scramble: three contacts on 571 of 824 ticks (69 %); margin mean +0.070 m, smallest −0.019 m; polygon area 0.140 m² on average, against 0.248 m² for the four scrambling contacts at rest on level ground. Over the straight crawl: three contacts on 64 % of the ticks, mean margin +0.075 m, smallest +0.007 m, mean area 0.097 m². Standing at rest, the same body has a margin of +0.027 m. Over another 1.5 m of crawl the Lesson 13 state was "stable" on 212 ticks, "marginal" on 27 and "outside" on 6, with no unstable lift: the test runs at the moment of a lift, and the body keeps moving during the swing that follows.
</details>

<details><summary>O7</summary>

"no room" (P2 b). At the spawn the hill slopes 15.8° (12.6° on the terrain's collision triangle there); measured with the body turned in steps of 30°, the crawl shape fits in one facing only, 12° from the contour line. A lying capsule fits on a slope only when it lies almost along a contour.
</details>

<details><summary>O8</summary>

"climb: walking (not upright)": the root refuses before `begin_climb()` runs (section 3.6). Each posture change sends one `/body/posture` message of 32 bytes (the address, padded to 16 bytes, the type tags ",s" padded to 4, a name of 8 to 10 characters padded to 12); `test_16_crawl_scene.gd` counts one message per change.
</details>

<details><summary>T1</summary>

0.75 m: the crawl passes (shape top 0.70 m, body 0.69 m). 0.70 m: the body stops at the roof's edge. Measured: stops under 0.70 m, passes under 0.71 m (P1). Under 0.70 to 0.72 m a body cannot drop to a crawl (the fit test needs 0.721 m), but a body already crawling passes from 0.71 m.
</details>

<details><summary>T2</summary>

Head Lift 0.75 raises the top of the head to 0.81 m (measured 0.812), 0.11 m above the crawl shape. Under a 0.75 m roof the capsule slides through and the head passes through the roof. Physics knows only the shape; whatever is drawn outside it goes through geometry. Head Lift 0 puts the head in line with the torso: the highest point is then the chest, 0.663 m.
</details>

<details><summary>T3</summary>

Measured over the first 1.55 m: every one of the 15 lifts is unstable, each after the full second of waiting (P4 d), and the 1.55 m take 19.2 s instead of 4.2 s. "air" reads "waits" on 900 of 1152 ticks: during each wait the limb before the waiting one is still in the air (the left leg while the left hand waits), and "support" reads 3. "support" reads 2 on 90 ticks, where two swings overlap after a timeout. The margin falls to −0.080 m.
</details>

<details><summary>T4</summary>

Without the weight shift (first 1.55 m): 7 of 16 lifts unstable, 7.0 s of waiting, 10.5 s in all. The center of mass sits near the middle line, where P3 (d) leaves no triangle for a leg's lift. With `shift_range` 0.04 m: no unstable lift, 1.2 s of waiting, 4.6 s in all. The center of mass moves about ±0.03 m (0.74 of the shift, P3 d), more than the 0.010 m that P3 (d) requires, and the spring takes longer to bring it past that limit before each lift.
</details>

<details><summary>T5</summary>

Measured over the first 1.55 m: no unstable lift. A limb lifts only with c at least 0.03 m inside its triangle, so the body waits 2.58 s (against 0.80 s) and takes 6.1 s (against 4.2 s). The smallest margin on the Lesson 13 line rises from +0.007 to +0.014 m, the mean from +0.075 to +0.079 m. The margin is paid for in time.
</details>

<details><summary>T6</summary>

Measured: 23.1 s to the top instead of 13.8 s; 11 of 32 lifts unstable, 11.5 s of waiting; the mean margin +0.058 m instead of +0.070 m. P5 (b): the triangles of three no longer contain the center of mass when a hand lifts.
</details>

<details><summary>T7</summary>

The probe still finds 48°, now steeper than the scramble's limit: the posture stays standing, "posture: standing (too steep)", and the capsule stops at the foot as in P7 (a).
</details>

<details><summary>T8</summary>

Measured at 52°: the body still scrambles (52 ≤ 55) and reaches the top in 13.2 s with 30 lifts, none unstable, and 1.5 s of waiting. The lean grows to 0.243 m at mid-slab (d tan 52° is larger), and the largest crawl error rises to 0.083 m: at this slope some contacts fall outside a limb's reach from the leaning body. The mean margin is +0.060 m.
</details>
