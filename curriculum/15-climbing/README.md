# Lesson 15. Climbing

Lesson scene: `game/scenes/lessons/15_climbing.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–14 are unchanged; the Lesson 14 scene has no climbing face, its player is a `FootRig` body without a climbing mode, and its balance monitor counts the feet alone.

## 1. Orientation

Lessons 11–14 built a body that walks, keeps its feet on the ground and shifts its weight. This lesson puts it on a rock face. It answers four questions:

1. Which points of a surface can a hand or a foot hold? (the normal n = ∇f / ‖∇f‖ and the curvatures H, K, k₁, k₂ of the field's zero set, Lesson 09; the creases where these numbers mean nothing)
2. Where must the body be so that every limb reaches its hold? (one reach sphere per limb around its shoulder or hip; the intersection of the spheres; alternating projections)
3. How is one limb turned to reach a point? (the closed-form two-bone solver of Lesson 12 against FABRIK, an iterative solver without a pole)
4. What keeps a body on a vertical face, and how hard must the hands pull? (Lesson 13's center of mass and support polygon with the hands added; moments about the feet)

The method: a new rock, `data/rocks/climbing_face.tres`, is a rounded box with 42 ellipsoid knobs, built from the SDF Resources of Lesson 07 and meshed by the `CurvatureMesher` of Lessons 08–09. A subclass, `ClimbableRock`, reads the per-vertex normals and mean curvatures, keeps the vertices that bend outward and face up toward the climber, thins them to one per 0.2 m, moves each onto the surface with Newton steps and measures it again; points on a crease of the field are dropped, and so are holds in the terrain or less than 0.05 m above it. Key 0 starts a climb when the face is close and both hands have a hold in reach. `ClimbController` then runs one state machine for the body (walking, climbing, mantling) and one per limb (hold, reach, move). Holding a trigger (5 or 6) makes a hand reach; the stick moves it over the face; releasing the trigger grabs the nearest hold. The feet follow by themselves. Each tick, the pelvis is placed in the intersection of the reach spheres of the limbs on holds, and each limb is solved alone. When both hands hold the top edge, the body mantles onto the top and walks again. Key 0 during a climb lets go.

Goal served (`plan.md`): "a humanoid player that can walk, crawl, climb, and balance"; "travelling up rocky formations in a place like Joshua Tree"; "use (differential) geometry ... to create surfaces and effects". The holds come from the curvature of the rock's field, not from markers placed by hand.

Files:

| File | Role |
|---|---|
| `game/data/rocks/climbing_face.tres` | `SdfDisplace` of an `SdfSmoothUnion`: a rounded box (2.9 × 5.4 × 1.2 m, rounding 0.12 m) and two `SdfRepeat` grids of one `SdfEllipsoid` knob (radii 0.15, 0.07, 0.11 m). |
| `game/src/climb/hold_finder.gd` | `HoldFinder` (static): the four vertex tests, the score, suppression, Newton refinement, knob or edge, reach queries. |
| `game/src/climb/climbable_rock.gd` | `ClimbableRock` (`@tool`, extends `CurvatureMesher`): thresholds as exports, holds in shape and world space (the holds in the ground left out), the top-out test, hold markers. |
| `game/src/climb/fabrik.gd` | `Fabrik` (static): FABRIK for one chain of any length. |
| `game/src/climb/reach_solver.gd` | `ReachSolver` (static): projections onto balls and a half-space; the pelvis. |
| `game/src/climb/climb_controller.gd` | `ClimbController` (Node3D): the state machines, the reach, the feet, the pelvis, the pose, the mantle, debug lines. |
| `game/src/climb/climbing_player.gd` | `ClimbingPlayer` (extends `BodyPlayer`, Lesson 11): gives up walking, gravity and collision response while `climbing` is true. |
| `game/scenes/climbing_player.tscn` | `player.tscn` with `climbing_player.gd` and a `FootRig`, built as `grounded_player.tscn` (Lesson 12) is. |
| `game/src/climb/climb_balance_monitor.gd` | `ClimbBalanceMonitor` (extends `BalanceMonitor`, Lesson 13): polygon from all held contacts; hand pull F/W. |
| `game/src/lessons/climbing.gd` | Scene root. Extends `analog_stances.gd` (Lesson 14); keys 0, F1, F2; five lines in `HUD/RockLabel`; places the rock on the terrain and turns the camera toward it. |
| `game/scenes/lessons/15_climbing.tscn` | The Lesson 14 scene with the climbing player, `ClimbFace`, `Climb`, and `ClimbBalanceMonitor` in place of `BalanceMonitor`. |
| `game/project.godot` | Input actions `toggle_climb` (0, gamepad Start), `toggle_climb_debug` (F1), `cycle_arm_solver` (F2); `cycle_tick_rate` back on T and D-pad up (Lesson 02), with the Lesson 14 key 9 as its own action `cycle_stance_tick_rate` (decision 0015); `run/main_scene`. |
| `game/tests/test_15_*.gd` | The solvers and the hold tests on known shapes; the scene: holds (the ones in the ground left out), approach, a scripted climb to the top, letting go, the keys. |
| `docs/decisions/0015-climbing.md` | Why holds come from vertex curvature, why the pelvis is a point in an intersection of balls, why the capsule is kinematic while climbing. |

Controls while climbing: 5 / left trigger (held) reaches with the left hand, 6 / right trigger with the right hand; WASD / left stick moves the reaching hand; release the trigger to grab. 4 / D-pad up (Lesson 14 crouch) brings the hips toward the rock. The camera keys work as before. Of the three new actions, `toggle_climb` alone has a gamepad binding (Start); Guide is the last free button. (D-pad up carries two actions: Lesson 02's tick rate, read only in the Lesson 02 scene, and Lesson 14's crouch.)

Reading:

- Keenan Crane, *Discrete Differential Geometry: An Applied Introduction* (`discreteDifferentialGeometry.pdf`), §3.4 "Curvature of Surfaces" and §3.4.1 "Principal, Mean, and Gaussian Curvature", pp. 38–41: normal curvature, principal directions and curvatures as eigenvectors and eigenvalues of the shape operator, H = (κ₁ + κ₂)/2, K = κ₁κ₂, the bottle with κ₁ = 1, κ₂ = 0, developable surfaces (K = 0). §4.6.1, p. 68: the gradient as the direction of steepest ascent, which makes ∇f / ‖∇f‖ the outward normal of the zero set. The hold tests of section 2 are these definitions applied to a field.
- Andreas Aristidou, Joan Lasenby, "FABRIK: A fast, iterative solver for the Inverse Kinematics problem", *Graphical Models* 73(5), 2011: the backward and forward passes, reachability.
- L. M. Bregman, "The method of successive projection for finding a common point of convex sets", *Soviet Mathematics Doklady* 6, 1965; Stephen Boyd, Jon Dattorro, "Alternating Projections", lecture notes, Stanford EE392o, 2003: convergence of cyclic projections onto convex sets. R. L. Dykstra, "An algorithm for restricted least squares regression", *Journal of the American Statistical Association* 78, 1983: cyclic projections with a correction term that reach the nearest point of the intersection (P6).
- Lesson 09 README (the curvature formulas and the crease in O4) and Lesson 12 README (the two-bone solver and its pole). Full entries: `docs/references.md`.

Lesson 09 E6 asks for a crease detector and a repair of the vertex values. `HoldFinder` uses one of the detectors that E6 lists (a small ‖∇f‖) to reject a point; it does not repair anything, and E6 stays open.

## 2. Predict

Notation: f is the rock's field in shape space, negative inside; g = ∇f; n = g / ‖g‖; H = (k₁ + k₂)/2 and K = k₁k₂ with k₁ ≥ k₂, positive where the surface bends away from n (H = +1/r on a sphere, Lesson 09). "Face" is the climbing face's outward normal (+z in shape space). A hold passes when 3 ≤ H ≤ 40 /m, ‖g‖ ≥ 0.5, n · up ≥ 0.3 and n · face ≥ 0.2.

- **P1.** The two direction tests. Take normals in the vertical plane spanned by up and face: n = cos φ · face + sin φ · up, with φ the angle above horizontal. For which φ do both tests pass? Does the flat top of the rock (n = up) pass? A climber's hand pulls down and out on a hold; which way must the hold face for that pull to press the fingers into the rock?
- **P2.** The rounded box. Its edges are quarter cylinders of radius 0.12 m and its corners are sphere octants of the same radius. Compute k₁, k₂, H and K on a flat face, on an edge and at a corner. Which pass the H test? `HoldFinder.classify()` calls a hold a knob when k₂ ≥ 0.25 k₁ and an edge otherwise; classify the edge and the corner. Compare with DDG's bottle (κ₁ = 1, κ₂ = 0) and its remark on developable surfaces.
- **P3.** A crease. f = min(a, b) for two unit spheres whose surfaces meet along a circle, where their unit normals nₐ and n_b make an angle θ. At a point of the circle, `SdfShape.gradient()` takes central differences: [f(p + h e) − f(p − h e)] / 2h along each axis e. Show that the result is (nₐ + n_b)/2 to first order in h, and that its length is cos(θ/2). Lesson 09 P5 asked this for opposite normals (θ = 180°). For which θ does the gradient test reject the point? What sign do you expect for H at a union's crease? At an intersection's crease (f = max(a, b))?
- **P4.** Newton onto the surface. `refine()` steps p ← p − f(p) g / ‖g‖². From a point at radius 1.03 m, take the step for the sphere field f = ‖p‖ − 1, then for f = ‖p‖² − 1 (the same zero set, not a distance). Give the radius after one, two and three steps. How does the error shrink from step to step? For a field that is an exact distance, the level set f = d through a vertex is the surface offset by d; how does an offset change a principal curvature k?
- **P5.** Reach spheres. A limb with joint offset o (shoulder or hip, from the pelvis) and length R reaches a target t when ‖p + o − t‖ ≤ R for the pelvis p. Rewrite this as a ball for p: center and radius. The measured offsets are a shoulder at (±0.19, 0.44, 0) and a hip at (±0.10, 0, 0) from the pelvis; arm reach 0.98 × (0.29 + 0.27) m, leg reach 0.98 × (0.44 + 0.42) m. A hand target sits 0.03 m from its hold along the hold's normal; take that normal equal to the face normal. A foot target sits 0.08 m above its hold and 0.10 m out from the face (toward the climber's back). With the pelvis 0.30 m in front of the plane of the holds, what is the largest vertical distance between a hand hold above the shoulder and a foot hold below the hip of the same side? At 0.20 m?
- **P6.** Alternating projections. Two balls of radius 0.6 have centers (0, 0, 0) and (1, 0, 0). From (0.5, 1, 0), project onto the first ball, then onto the second, and repeat twice. Where does the sequence go? Is the limit the point of the intersection nearest the start? Repeat with radius 0.4: the balls no longer meet. What happens to the sequence, and what is left as the distance from the final point to the first ball?
- **P7.** The feasible set of the pelvis is the intersection of the balls of the limbs on holds and the half-space in front of the face. Is it convex? When a hand lets go to reach, does the set grow or shrink? The pelvis follows its target with a one-pole filter (Lesson 14): it moves along the segment from its old position toward the target. When does that segment stay inside the set, and when can it leave it? Why does the controller let one limb move at a time?
- **P8.** FABRIK on two bones. Root r, elbow e, hand h, target t, all reachable. Each pass puts a joint on the line between its neighbor and its own old position. Show that the elbow never leaves the plane through r, t and the starting elbow e₀. How many elbow positions solve the reach, and which one does FABRIK converge to? Which pole makes `TwoBoneIk.solve()` (Lesson 12) give the same elbow? Count the square roots per FABRIK iteration and per two-bone solve.
- **P9.** Hand pull. A climber stands on foot holds and hangs from hand holds h meters above them. Its center of mass is d meters in front of the line of the feet, along the face normal. Taking moments about the line of the feet (the foot forces have no lever arm there), find the horizontal pull F of the hands as a fraction of the weight W. Assume the hand and foot holds lie in one vertical plane. Evaluate it for d = 0.171 m and h = 0.884 m. The Lesson 14 crouch moves the pelvis from 0.30 to 0.20 m in front of the holds; how does F change? Where does the Lesson 13 margin put the center of mass relative to a polygon of contacts that all lie near the face?

## 3. Read

### 3.1 `data/rocks/climbing_face.tres`

Open it in the Inspector (or as text). The tree, from the leaves: one `SdfEllipsoid` knob (radii 0.15, 0.07, 0.11 m: wide, flat, protruding 0.11 m); two `SdfRepeat` copies of it, period 0.7 m in x and y and count (1, 3, 0), so 3 × 7 knobs each; two `SdfTransform` that place the grids on the front face (z = 0.6), centered at y = 2.0 and 1.65, the second shifted by (0.35, −0.35) m so that the knobs interleave; an `SdfBox` (center y 1.7, half extents 1.45, 2.7, 0.6, rounding 0.12); an `SdfSmoothUnion` with blend 0.04 m that fillets each knob into the face; an `SdfDisplace` with `granite_noise.tres` at amplitude 0.025 m. Shape space has the foot of the face at y = 0, z = 0.6. The box reaches 1 m below that point, so the rock stands buried in the slope. `SdfRepeat` puts as many copies below a grid's center as above it, so the lowest knob rows sit at y = −0.1 and −0.45: in the lesson scene these 6 knobs lie in the ground (section 3.3), and 36 stand above it. Compare with Lesson 07's `split_boulder.tres`: the same classes, a different purpose.

### 3.2 `hold_finder.gd`

Read the header: the four tests and where section 2 derives them. Then:

- `Criteria` and `Hold`: plain data classes. A `Hold` keeps H, K, k₁, k₂ and ‖g‖ from its last measurement.
- `passes()`: tests 1, 3, 4 and the H half of test 2 (H ≤ 40 /m) on the vertex values. The gradient half of test 2 waits for `refine()`, because `CurvatureMesher` keeps the normalized gradient and not its length.
- `candidates()` and `score()`: the score H · max(n · up, 0) and its Q/A.
- `suppress()`: non-maximum suppression. Walk through it with a line of ten candidates 0.05 m apart and spacing 0.2 (the test does).
- `refine()`: two Newton steps (P4), then `ImplicitCurvature.sample()` (Lesson 09, 26 evaluations) at the new point, then the tests again with the gradient test included. Read its two Q/A blocks with P3 beside you.
- `classify()`: knob or edge from k₂ / k₁ (P2, DDG §3.4.1).
- `find()`: the three stages in one call, for scratch scripts (E2) and the tests. `ClimbableRock` runs the stages itself, because it tests each refined hold for a top-out.
- `in_reach()`: the reach-sphere query; it returns the holds within a radius of a center, nearest to an aim point first.

### 3.3 `climbable_rock.gd`

A subclass of Lesson 09's `CurvatureMesher`. `rebuild()` calls the inherited meshing and curvature, then `find_holds()`. The threshold setters call `_queue_hold_search()` instead of `_queue_rebuild()`: the search takes about 12 ms, the mesh and curvature about 1.25 s, so the thresholds can be changed in the running game's remote Inspector (section 5).

- `face_normal`: the one outward direction of the climbing face, in shape space. Every hold is tested against it, and `ClimbController` builds the body's frame from it.
- `_update_world_holds()` and `_notification()`: holds are found in shape space and copied to world space whenever the node moves. The scene root moves the rock onto the terrain in `_ready()`. With `ground` assigned (the scene assigns `Terrain`), a hold less than `ground_clearance` (0.05 m) above `Terrain.height_at()` stays in `local_holds` but is left out of `holds` and not drawn; `buried_count` counts them. Read the Q/A: the search knows nothing of the terrain, and whether a hold is in the ground depends on where the rock stands.
- `_below_top()`: the top-out test, a sphere-traced ray (Lesson 10's `SphereTracer`) straight down from a point 0.6 m above and 0.35 m behind the hold. Read its Q/A. A hold is a top-out when the ray lands on a flat surface (normal y ≥ 0.8) within 0.25 m of the hold's height.
- `_draw_holds()`: orange crosses for knobs, yellow for edges, cyan for top-outs, each with a 0.1 m line along the hold's normal.

### 3.4 `fabrik.gd`

Read the header: the two passes on a list of joint positions. `place_on_sphere()` is the projection of a point onto a sphere's surface, the counterpart of `ReachSolver.project_to_ball()` for a ball. In `solve()`:

- the exit before the loop for a target beyond the chain's length (the straight chain, `reachable` false);
- the loop: backward from the end, forward from the root; the tolerance check at the top of each iteration, so a warm start that already reaches costs no iteration;
- `bone_lengths` is passed in and never recomputed from the joints, so rounding cannot make the bones drift.

Compare with `TwoBoneIk.solve()` (Lesson 12): no pole, any number of bones, no law of cosines, and a result that depends on the starting pose (P8). `ClimbController._solve_arm_fabrik()` keeps the last tick's arm joints in world space for the warm start and returns the result as a `TwoBoneIk.Solution`, so the rest of the pose code does not change. The engine's `FABRIK3D` node is the same algorithm as a `SkeletonModifier3D`; decision 0015 explains why this lesson uses its own (exercise E4 compares them).

### 3.5 `reach_solver.gd`

Read the header: one ball per holding limb, a half-space for the face, and the intersection of all of them (P5, P6). `project_to_ball()` and `project_to_half_space()` are the two closest-point maps. `solve()` applies them in turn, sweep after sweep, until no projection moves the point by more than the tolerance (0.1 mm), and reports the largest violation as `residual`: 0 when every limb reaches.

### 3.6 `climb_controller.gd`

The largest file of the lesson. Read the header first: the files around it, the two state machines, the controls, and the order of one tick. Then in this order:

- Geometry: `body_basis()` (x right, y up, z along the face normal: the body faces −z, into the rock), `face_point()` and `face_distance()` (the plane through the mean of the holds), `limb_root()`, `limb_reach()` (`reach_fraction` 0.98 of the two bones), `limb_target()` (the hand 0.03 m out along the hold's normal; the ankle 0.08 m above the foot hold and 0.10 m out from the face, toward the climber's back, so the toes stand on the hold).
- `begin_climb()`: the approach tests (pelvis within `grab_distance` 0.9 m of the plane and in front of it; a hold in reach for each hand from a pelvis stepped in to `wall_clearance`), then the grab: hands on the holds nearest a point 0.4 m above each shoulder, feet on the ground under the hips. `refusal` names the failed test; the HUD shows it.
- `_climb_tick()`: the per-tick order. One limb may be in REACH or MOVE; when none is, a trigger may start a reach, the mantle may start, or `_plan_feet()` may start a foot move.
- `_update_reach()`: the stick drives the aim's velocity, not its position (Q/A), the aim stays in the reach sphere, a `CriticalSpring` (Lesson 14, ω = 14 rad/s) smooths it, and the candidate is the hold nearest the hand within `snap_radius` 0.3 m. Releasing the trigger starts a MOVE to the candidate, or back to the old hold.
- `_update_move()`: an eased arc (Lesson 12's `swing_ease`) lifted `move_lift` 0.08 m off the face, `move_time` 0.35 s. `_start_move()` sets the limb's point at once; its Q/A explains the one-tick error this prevents.
- `_plan_feet()`: the three steps in its Q/A. The foot's new ball is added and `ReachSolver` must still find a common point (residual below 1 mm).
- `_preferred_pelvis()`, `_solve_pelvis()`, `_balls()`, `_destination()`: P7. The pelvis wants to hang below the hands and stand above the feet; the solver moves that wish into the feasible set; a moving limb counts with the hold it travels to; the filtered pelvis is projected once more. `_clamp_reaching_hand()` keeps the reaching hand within its arm after the pelvis moved.
- `_place_body()`: the capsule under the pelvis, `BodyMesh` turned to face the rock.
- `_pose()`: four independent limbs. The arms use the two-bone solver with a pole down, out and away from the face, or FABRIK; the legs use the two-bone solver with a pole toward the face and out (a frog stance); the feet tilt to the hold's normal, limited to 30° (Lesson 12 `limit_tilt()`). The rotations are written as a `WalkCycle.Pose` through `BodyRig.apply_pose()`, as Lesson 12 does.
- `_start_mantle()` and `_mantle_tick()`: a ray finds the top behind the hands; two overlapping eased ramps carry the capsule up and over (Q/A).

### 3.7 `climbing_player.gd`

While `climbing` is true, `_physics_process()` turns the camera and reads the stick and does nothing else: no walking, no gravity, no `move_and_slide()`. The setter's Q/A explains why `_last_position` is reset (Lesson 11 turns distance moved into walk phase). The scene file `climbing_player.tscn` is built as `grounded_player.tscn` is: it inherits `player.tscn`, sets the root script, hides the capsule and the nose, and adds `Rig` with `foot_rig.gd`. It is a copy of `grounded_player.tscn` with the root script changed; Lesson 12 section 3.6 explains why such copies replace inherited scenes that swap the `Rig` script.

### 3.8 `climb_balance_monitor.gd`

A subclass of Lesson 13's `BalanceMonitor` that overrides `measure()`: it calls the original (center of mass from the segment table, the feet polygon), then, while climbing, rebuilds the polygon from every limb in HOLD (hands included, projected to the ground as Lesson 13 does) and computes `hand_pull` with `pull_ratio()` (P9). Read the two Q/A blocks of `pull_ratio()`. The OSC messages of Lesson 13 carry the new margin in the same format.

### 3.9 The scene and the root

`15_climbing.tscn` is the Lesson 14 scene with these changes: the root script (`climbing.gd`) and name; the player from `climbing_player.tscn`; the `BalanceMonitor` node's script swapped for `climb_balance_monitor.gd` with `climb = ../Climb`; a node `ClimbFace` (`ClimbableRock`, `climbing_face.tres`, the Lesson 09 weathering material, cell 0.08 m, `ground` = `Terrain`) at (5.5, 0, 47.5) turned 180° about y, so its face looks toward the spawn; a node `Climb` (`ClimbController`) after `Stance`, with `player`, `rock` and `stance` assigned; a taller `RockLabel`. `Climb` ticks after `Player` (same priority, later in the tree), so the stick it reads is this tick's.

`climbing.gd` sets the rock's height from `Terrain.height_at()` at the foot of the face, as Lesson 12 places `StepRow`, and turns the camera toward the rock at the start. Its `_unhandled_input()` handles 0, F1 and F2; `_update_hud()` appends the climb state (with the refusal), the four limb states, the ascent, the move counts, the reach residual, the hand pull, the arm solver, the largest limb error and the climbing tick's time.

`test_15_climb_scene.gd` climbs the face with scripted input: it holds a trigger action, steers the stick toward the highest hold within reach plus 0.25 m, and releases when the controller's candidate is that hold. Read `_reach()` there; it is the same policy as a player's thumb, written as code.

## 4. Run and observe

Start the lesson scene. The camera looks toward the climbing face; the player stands about 9 m from it. `RockLabel` (top right) ends with five climbing lines. Walk to the face; the capsule (radius 0.35 m) stops against the knobs, which protrude 0.11 m.

- **O1. Holds.** Before climbing, count the hold markers by color: orange knobs, yellow edges, cyan top-outs. Compare with "holds" on the HUD. How many knobs carry one marker, how many two? Press U (Lesson 09) to show the H map, then return to the weathered view. Where on a knob do the markers sit: on its top, its front, or between? Why are the knob bases dark in the weathered view?
- **O2. Approach.** Stand 1.5 m from the face and press 0. Step closer and press 0 again until the climb starts. Then walk to the side of the rock, past its edge, and press 0. After a climb to the top (O6), press 0 on the top. Read the reason after "climb:" each time.
- **O3. A reach.** Climbing, hold 5. Watch the yellow circle (the left arm's reach sphere, cut by the plane of the face through the shoulder) and the red circle (the candidate hold). Push W, then A or D, and watch the body follow the hand. Release 5 with a candidate, then without one. Count the foot moves that follow a hand move ("moves ... feet").
- **O4. Hanging off the face.** Read "hand pull" and the Lesson 13 line "balance: ... margin". Is the body "stable" in Lesson 13's sense? Press 4 (crouch) and read both again. Press 4 to stand.
- **O5. Two arm solvers.** Press F2 ("arms FABRIK"). Reach with each hand and watch the elbows. Compare "climb tick" on the HUD with the two-bone solver. Press F2 again.
- **O6. Top out.** Climb until both hands hold cyan holds. Watch the state change to "mantling" and back to "walking", and read the final ascent.
- **O7. Let go.** Start a new climb, make two or three reaches, and press 0. Where does the body land, and how long does the fall take?

## 5. Tweak

The thresholds of `ClimbFace` rerun the hold search in about 12 ms without re-meshing. With the game running, open the Remote tab of the Scene dock, select `ClimbFace` and edit them in the Inspector; or edit them in the scene before running.

- **T1.** Set **Min Up** to 0.6. How many holds remain, and which ones disappear? Express 0.3 and 0.6 as angles of the normal above horizontal.
- **T2.** Set **Hold Spacing** to 0.1. How many holds now, and how many on one knob? What does a smaller spacing cost the hand's candidate search?
- **T3.** Set **Min Mean Curvature** to 6. Count the holds and the top-outs. Then climb. What stops the climb, and which number of P2 predicted it?
- **T4.** Set **Min Gradient** to 0.8. Most knob holds vanish, although the field has no crease there. Why is ‖∇f‖ below 0.8 on a knob? Does the low gradient spoil the curvature measured there (Lesson 09 P6, and its test on ‖p‖² − 2.25)?
- **T5.** Select `Climb` and set **Reach Fraction** to 0.9, then 0.85. Climb with the same pattern of reaches. How many hand moves does the face take now?
- **T6.** Set **Wall Clearance** to 0.45 and read the hand pull. Then set **Arm Solver** to FABRIK and **Fabrik Iterations** to 1, then 3, and watch the hands and the HUD's "limb error" during a reach. What does the limb error correspond to on screen?

## 6. Exercises

- **E1 ★ Hold inspector.** While a hand reaches, show the candidate's H, K, k₁, k₂, ‖∇f‖, kind and score on the HUD. Climb to three different knobs and the top edge, and compare the numbers with P2. Which of the four tests does each hold pass with the smallest margin?
- **E2 ★ The test that decides.** Write a scratch script that counts, for every vertex of a `CurvatureMesher`, the first test it fails. Run it on the climbing face and on the Lesson 09 boulder pile. Explain why the pile, with these thresholds, yields almost no holds, and choose thresholds that give it holds a hand could use. Which test carried the change?
- **E3 ★★ A grip budget.** Give each hold a grip limit as a fraction of body weight, from its kind and its H (a broad edge with small H is a sloper). When `hand_pull` exceeds the sum of the limits of the held hands for longer than 0.5 s, let go. Where on the face does the body fall with and without the crouch? Use the trigger's raw value (Lesson 14) as the grip effort while a hand holds. Above `trigger_threshold` (0.3) the same trigger starts a reach and the hand lets go: decide first how grip and reach share the trigger (for example, grip effort on [0, 0.3], or a second, higher threshold for the reach).
- **E4 ★★ `FABRIK3D`.** Replace `Fabrik` for the arms by the engine's `FABRIK3D` modifier. Lesson 12 found that a modifier's result is visible inside `Skeleton3D.skeleton_updated` and nowhere else; read the elbows there. Compare the elbows with `Fabrik` warm-started from the same pose, and the cost per tick.
- **E5 ★★ Contact sounds.** On `limb_placed`, send `/climb/hold` with the limb, the kind, H, K and the travel time through `/root/Osc` (Lesson 04; append-only arguments as Lessons 05 and 13 do). In SuperCollider, map H to the brightness of a short tap and the kind to its envelope (a knob rings, an edge clicks). Record a climb's messages and render them in non-real-time mode with `Score.recordNRT`.
- **E6 ★★ Feet under control.** The feet move by themselves. Give them to the player: while Shift is held, 5 and 6 reach with the left and right foot instead of a hand, with the foot's reach sphere around its hip. Keep `_plan_feet()` as the fallback when no foot input arrives for a second.
- **E7 ★★ The boulder pile.** Make `Rocks/Boulders` (Lesson 09) a `ClimbableRock`. It has no single face: replace the facing test by the direction from the hold to the climber's pelvis at query time, and replace `face_point()` and `body_basis()` by the mean position and mean normal of the holds in use. Which parts of `ClimbController` assume one plane, and what breaks first?
- **E8 ★★★ Dynamic move.** When the reach sphere does not contain a hold the player aims at, let the trigger's release launch the pelvis on a ballistic arc (Lesson 02) toward it. If the hand passes within `snap_radius` of the hold near the arc's apex, catch it; otherwise fall with `let_go()`. Derive the launch speed from the distance to the hold, and limit it by what the legs could push.

## 7. Reflect

- **R1.** Lesson 16 (crawling and scrambling) puts four limbs on the ground. Which parts of this lesson carry over unchanged: the reach balls, the feasible set, the support polygon of all contacts? What changes when the "face" is the ground and gravity points into it?
- **R2.** Lesson 22 computes curvature on the mesh itself (angle defect, cotangent mean curvature). Would holds found that way agree with the field's holds on the knobs? At a crease? Which estimate needs the field, and which needs nothing but triangles?
- **R3.** Lesson 20 adds detail normals in the shader. A hand on a hold sees the field's normal; the eye sees the detail normal. Should a hold follow the detail? What would a climber notice if the two disagree?
- **R4.** The climb produces discrete events (a hold taken, a top-out) and continuous values (hand pull, ascent, margin). Lesson 28 maps traversal state to music. Which of these suit a rate of 30 Hz, which suit events, and which should SuperCollider smooth?

## 8. Answers

<details><summary>P1</summary>

n · up = sin φ ≥ 0.3 gives φ ≥ 17.5°; n · face = cos φ ≥ 0.2 gives φ ≤ 78.5°. Normals between 17.5° and 78.5° above horizontal, tilted toward the climber, pass. A normal with a sideways part passes when both components are large enough; the measured holds have n · up from 0.48 to 0.98, and many lean sideways (for example (0.61, 0.67, 0.41) on the side of a knob). The flat top (φ = 90°) fails the face test: n · face = 0. The top-out holds sit on the rounded edge, where the normal turns from the face to the top; measured normals there are about (0, 0.92, 0.38), φ = 67°. A hand loads the hold down by a and pulls it out (toward the climber) by b: F = −a · up + b · face. The fingers are pressed into the rock when F has a component against n: F · n = −a sin φ + b cos φ < 0, that is tan φ > b/a. The up test is the grip condition, and an outward tilt of n (the term b cos φ) weakens the grip: with a = 1 and b = 0.25, F · n is −0.11 at φ = 20°, −0.53 at 45°, −0.85 at 70° and −1 at 90° (n = up). An incut hold (n · face < 0) presses harder still. The face test is not a grip condition: it keeps the holds that a climber on the face can reach and see, and drops those on the top, the back and the sides of the rock; it also drops incuts.
</details>

<details><summary>P2</summary>

Flat face: k₁ = k₂ = 0, H = K = 0, fails the H test. Edge (a cylinder of radius r = 0.12 m): k₁ = 1/r = 8.33 /m across the edge, k₂ = 0 along it; H = 4.17 /m, K = 0. It passes (3 ≤ 4.17 ≤ 40) and is an edge (k₂ < 0.25 k₁). This is DDG's bottle, scaled: one principal curvature, a developable piece (K = 0). Corner (a sphere of radius 0.12 m): k₁ = k₂ = 8.33 /m, H = 8.33 /m, K = 69.4 /m², a knob. Measured on the face: the top-edge holds have H 3.93 to 4.79 /m, K from −0.58 to 1.16 /m² and k₁ 7.70 to 9.63 /m (the displacement noise of amplitude 0.025 m perturbs them); a top-corner hold has H 8.31 /m and K 69.04 /m², a knob. Of the 59 holds above the ground, 47 are knobs and 12 edges; 10 of the edges and 2 of the knobs are top-outs. (The search finds 67; the other 8 lie on the two lowest knob rows, in the ground or within 0.05 m of it, section 3.3.)
</details>

<details><summary>P3</summary>

At the crease a = b = 0. Along an axis e, f(p ± h e) = min(a(p ± he), b(p ± he)) ≈ min(±h gₐ·e, ±h g_b·e). The difference quotient is [min(x, y) − min(−x, −y)] / 2 with x = gₐ·e, y = g_b·e, and min(x, y) + max(x, y) = x + y, so the component is (gₐ + g_b)·e / 2. With unit normals, ‖(nₐ + n_b)/2‖ = cos(θ/2). The test ‖g‖ ≥ 0.5 rejects θ > 120°. Measured on two unit spheres: θ = 60° gives 0.8660, 120° gives 0.5000, 143.6° gives 0.3122, each equal to cos(θ/2) to four decimals.

A union's crease is concave (a groove): H is negative and large, because the second difference of a kink grows as 1/h. Measured with h = 0.01 m: H = −56.7 /m at θ = 60°, −171.9 at 120°, −302.5 at 143.6°. One step (0.01 m) away from the crease, ‖g‖ = 1.000 and H = 1.00 /m, the sphere's value. A union's crease therefore fails the H test before the gradient test is reached; Lesson 09's pile had creases with ‖∇f‖ down to 1.2 × 10⁻⁵ (θ near 180°). An intersection's crease is convex (a ridge): H is positive and large, +58.7 /m at θ = 60° and +174.4 /m at 120°, and fails the upper limit of 40 /m. Between 0.004 and 0.008 m from such a ridge the measured H falls through [3, 40] while ‖g‖ is 0.72 to 0.95: those points pass both tests. A sharp ridge yields holds beside its edge, within one curvature step. The climbing face has no sharp crease (rounded box, smooth union): no vertex has H above 40 /m and no hold fails the gradient test.
</details>

<details><summary>P4</summary>

For f = ‖p‖ − 1, g = p/‖p‖ and ‖g‖ = 1: the step is r ← r − (r − 1) = 1, exact after one step. For f = ‖p‖² − 1, g = 2p: r ← r − (r² − 1)/(2r) = (r² + 1)/(2r). From 1.03: 1.000437, 1.0000000954, 1.0000000000 (measured). The error goes 0.03 → 4.4 × 10⁻⁴ → 9.5 × 10⁻⁸: each error is about the square of the previous one divided by 2r, the quadratic convergence of Newton's method. On a distance field the level set f = d is the offset surface, whose principal curvatures are k / (1 + k d). A vertex a few centimeters off a knob of curvature 10–20 /m measures a different H than the surface point. Measured on the face: refinement moved the holds by up to 0.034 m, and their H changed by up to 10.1 /m.
</details>

<details><summary>P5</summary>

‖p − (t − o)‖ ≤ R: a ball of radius R around c = t − o, where o is the offset turned into the body's frame (`_balls()`). Arm reach 0.5488 m, leg reach 0.8428 m. At clearance 0.30 m the shoulder lies 0.27 m from its hand target in the horizontal direction, and the hip 0.20 m from its foot target. The hand can be √(0.5488² − 0.27²) = 0.478 m above the shoulder; the ankle √(0.8428² − 0.20²) = 0.819 m below the hip; the shoulder is 0.44 m above the hip and the foot hold 0.08 m below the ankle. Largest span: 0.478 + 0.44 + 0.819 + 0.08 = 1.817 m. At clearance 0.20: √(0.5488² − 0.17²) + 0.44 + √(0.8428² − 0.10²) + 0.08 = 0.522 + 0.44 + 0.837 + 0.08 = 1.879 m. Measured by bisection with `ReachSolver` and the same offsets: 1.8165 m and 1.8787 m. The knob rows are 0.35 m apart in height, so a hand and a foot can be five rows apart. The game places the hand target along the hold's own normal (`limb_target()`), not along the face normal. For a top-edge normal (0, 0.92, 0.38) the target lies 0.028 m above the hold and 0.011 m in front of it; the shoulder is then 0.289 m from the target in the horizontal direction, the hand reaches √(0.5488² − 0.289²) = 0.467 m above the shoulder, the hold can lie 0.467 − 0.028 = 0.439 m above it, and the largest span falls by 0.04 m, to 1.778 m.
</details>

<details><summary>P6</summary>

Radius 0.6, measured: (0.268, 0.537), (0.516, 0.355), (0.494, 0.340), (0.502, 0.335), (0.499, 0.333), (0.500, 0.332). `ReachSolver.solve()` with its default tolerance (10⁻⁴ m) stops after 5 sweeps at (0.50001, 0.33167) with residual 1.2 × 10⁻⁵ m; with tolerance 10⁻⁶ m it takes 8 sweeps and ends at (0.5000, 0.3317) with residual 0. Here the limit is the top of the lens, √(0.36 − 0.25) = 0.3317, which is also the point of the intersection nearest the start: the start lies on the symmetry plane. In general cyclic projections reach a point of the intersection, not the nearest one; Dykstra's algorithm adds a correction term that yields the nearest point. The controller needs a point, not the nearest one.

Radius 0.4: the balls are 0.2 m apart. The sequence alternates between the two balls, (0.179, 0.358), (0.633, 0.160), (0.388, 0.098), (0.605, 0.063), (0.398, 0.042), (0.601, 0.028), and closes on the pair of nearest points (0.4, 0) and (0.6, 0). After 200 sweeps it ends at (0.6000, 0, 0) on the second ball with residual 0.200, the gap. The residual reports how far the body would have to stretch.
</details>

<details><summary>P7</summary>

Balls and half-spaces are convex, and an intersection of convex sets is convex. Letting go removes one ball: the set grows or stays. While the balls stay the same, the old pelvis and the target both lie in the set, and so does the segment between them. When a limb takes a new hold its ball moves, the set changes, and the old pelvis can lie outside the new set; the segment can then leave the set too. `_solve_pelvis()` projects the filtered point into the set once more (two solves per tick; measured 2.16 sweeps per tick on average, at most 6, over the scripted climb). With one limb moving, three limbs hold: their three balls and the half-space leave a set that contains the pelvis, and the moving limb's destination is checked against them before the move (`_plan_feet()`) or kept within the arm (`_update_reach()`). Measured over the scripted climb: largest residual below 10⁻⁶ m, largest limb error 0. To see why a moving limb counts with its destination, remove the `MOVE` case from `_destination()` and run the scripted climb: the moving hand falls short of its target by up to 0.075 m during its move (measured).
</details>

<details><summary>P8</summary>

Each placement puts a joint on the line through two points that already lie in the plane P through r, t and e₀ (the target, a neighbor, or the joint's old position). The root and the target never move. By induction every joint stays in P. Measured on 2000 random starts: the largest distance of the final elbow from P is 2.6 × 10⁻⁷ m (float rounding).

The reachable elbows form a circle around the axis r–t. P cuts it in two points, one on each side of the axis; FABRIK converges to the one on the side of e₀. `TwoBoneIk.solve()` with pole e₀ chooses the elbow in the plane of r, t and the pole, on the pole's side: the same point. Measured: converged FABRIK elbows lie within 2.0 × 10⁻⁴ m of the two-bone elbows (the tolerance is 10⁻⁴ m on the hand).

Cost: one FABRIK iteration measures the end's distance to the target (the tolerance check) and places 2n points, one square root each: 2n + 1 square roots, 5 for two bones. The two-bone solve takes 4 square roots (the distance to the target, the length of the pole's perpendicular part, its normalization, and √(1 − cos² α)), 2 acos calls and no iteration. Measured: 3.83 µs per FABRIK solve against 1.84 µs per `TwoBoneIk.solve()` for one target. Convergence depends on the target: from random cold starts with 10 iterations, targets 0.30–0.45 m from the shoulder converge in 2.9 iterations on average and all reach 10⁻⁴ m; targets within 0.15 m (a folded arm) miss in 994 of 1000 cases; targets beyond 0.45 m (near full extension) in 225 of 1000. In the game the warm start keeps the count low (O5).
</details>

<details><summary>P9</summary>

About the line of the feet: the weight W acts at horizontal distance d and turns the body away from the face; the hand pull F acts at height h and turns it back. F h = W d, F/W = d/h. For d = 0.171 m, h = 0.884 m: F/W = 0.193. Measured in the scene after four reaches: d 0.171 m, h 0.884 m, hand pull 0.193 W. The crouch brings the pelvis to 0.20 m from the holds: d falls to 0.086 m and the pull to 0.098 W. The contacts all lie within a few centimeters of the face, so the polygon is a thin strip along it, and the center of mass projects in front of it: the margin is negative, −0.170 m standing (about −d), and Lesson 13 reports "outside". Lesson 13's static balance has no answer on a wall: the body stays on because the hands pull, and F/W measures how hard.

Two assumptions stand behind F/W = d/h. First, the hand and foot holds lie in one vertical plane. The hand force also has a vertical part V; if the hands lie a distance e in front of the line of the feet along the normal, the balance reads W d = F h + V e. `pull_ratio()` measures d from the feet and does not read the hands' depth, and a knob protrudes 0.11 m. Second, the holds can deliver F. A hold with n · face > 0 pushes the hand out along n; the inward pull on the body must come from friction, and the reaction on the hand must stay inside the friction cone around n. Lesson 15 models neither friction nor grip force (decision 0015).
</details>

<details><summary>O1</summary>

Measured: 59 markers: 45 orange knobs, 2 yellow edges, 12 cyan top-outs (10 edges along the top and 2 knobs at the top corners); the HUD shows "holds 59". Of the 42 knobs, 36 stand above the ground: 25 carry one marker and 11 carry two, on either shoulder of the knob, 0.2 m or more apart. The 6 knobs of the two lowest rows lie in the ground (the tips of the row at y = −0.1 reach its surface); the 8 holds found there are left out (section 3.3). The markers sit on the upper front of each knob, between its top (n · face too small) and its front (n · up too small), where H is large and both direction tests pass. The H map (blue below 0, white at 0, full red from 2 /m) shows each knob red inside a blue ring. The ring is the smooth union's fillet, a concave groove: of the 516 vertices of the face within 0.13–0.20 m of a knob's center, 479 have H below 0.2 /m (the shader's `cavity_start`), down to −11.5 /m. The weathered view paints them as cavities, dark. The search itself: 8492 vertices; 6660 fail the lower H limit, 1401 the up test, 180 the face test, 0 the upper H limit; 251 candidates are thinned to 68, of which 67 pass after refinement, and 59 of those lie 0.05 m or more above the terrain.
</details>

<details><summary>O2</summary>

Measured with the player placed at distances from the box's front face: 0.45, 0.6 and 0.8 m start a climb, 1.0 m and beyond give "face too far" (the pelvis is 0.035 m closer to the plane of the holds than to the box, so the limit `grab_distance` 0.9 m falls between). Beside the rock, 2.2 m along it, the reason is "no hold in reach". On the top after a mantle it is "behind the face": the pelvis lies behind the plane of the holds.
</details>

<details><summary>O3</summary>

The candidate appears when the hand comes within 0.3 m of a hold inside the reach sphere, and the pelvis follows the hand (the preferred pelvis is drawn toward a reaching hand). Released without a candidate, the hand returns to its old hold. In the scripted climb of `test_15_climb_scene.gd`, 9 hand moves took the body to the top, with 19 foot moves: 3 at the start (both feet leave the ground for knobs, the right one twice), then two after each of the first eight hand moves (one per foot), and none after the ninth, which starts the mantle. The hands alternate; from the second to the seventh hand move each hand takes the knob row 0.35 m above the other hand, and the last two take the top edge. Each move takes 0.35 s.
</details>

<details><summary>O4</summary>

Measured after four reaches: hand pull 0.193 W, margin −0.170 m, state "outside". Crouched: 0.098 W and −0.085 m, still "outside". Over the whole scripted climb the pull ranged from 0 (feet on the ground below the hips at the start) to 0.24 W, mean 0.18 W, and the margin from −0.284 to −0.047 m.
</details>

<details><summary>O5</summary>

Measured over the scripted climb with FABRIK on the arms: 1.84 iterations per arm per tick on average, 10 at most; largest hand error 3.4 mm; the climbing tick 0.21 ms on average against 0.17 ms with the two-bone solver (largest 0.38 and 0.32 ms). The same holds were taken in the same order with either solver. FABRIK starts from the two-bone elbow when it is switched on and afterward keeps each new elbow in the plane of the shoulder, the hand target and the last elbow (P8); the two-bone solver takes the plane of its fixed pole.
</details>

<details><summary>O6</summary>

Measured over the scripted climb: 983 climbing ticks (16.4 s), the pelvis 3.06 m above its starting height when the mantle starts, 4.61 m after it. The mantle lasts `mantle_time` 1.2 s. The player ends standing at y 4.964 m on the top, whose undisplaced height is 4.958 m (the noise moves the surface by up to 0.025 m).
</details>

<details><summary>O7</summary>

`let_go()` moves the capsule 0.45 m in front of the plane of the holds (clear of the face for its radius 0.35 m) and returns it to physics. Measured after two reaches (left hand, then right hand, as `test_15_climb_scene.gd` does): the feet fall 0.91 m in 27 ticks (0.45 s; free fall √(2 · 0.910 / 9.8) = 0.43 s), and the body lands 0.45 m in front of the face and walks. After four reaches: 1.62 m in 36 ticks.
</details>

<details><summary>T1</summary>

0.3 is 17.5° above horizontal, 0.6 is 36.9°. Measured: 48 holds remain above the ground (37 knobs), against 59. The holds removed are those with n · up between 0.48 (the smallest on the face) and 0.6, on the sides and fronts of the knobs. Suppression then keeps other points: on one knob of the top row the hold moves up the knob, close enough to the top to count as a top-out (13 top-outs).
</details>

<details><summary>T2</summary>

Measured: 99 holds above the ground (67 knobs). Several markers now share one knob. The candidate search (`in_reach()`) and the foot search are linear in the number of holds, and suppression is quadratic in the worst case.
</details>

<details><summary>T3</summary>

Measured: 46 holds above the ground, 45 knobs, 1 edge, and 2 top-outs. The top edge (H 3.9–4.8 /m, P2: 1/(2 · 0.12) = 4.17) falls below 6 and leaves no holds; the two top-corner knobs (H 8.31 and 8.61 /m, 2.7 m apart) remain. The policy of `test_15_climb_scene.gd` (`_reach()`) stops after one hand move, at an ascent of 0.37 m: the right hand's target, the highest hold within its reach plus 0.25 m, lies beyond the arm's reach and never becomes the candidate, and the left hand finds no hold above its own within that range. A policy that tries the next-highest hold after a miss (a scratch script, not the test) climbs to an ascent of 2.92 m and stops there: no reachable hold lies higher, both hands cannot reach the two corners at once, and the mantle never starts. A player climbing by hand meets the second limit.
</details>

<details><summary>T4</summary>

Measured: 16 holds remain above the ground (19 in all); 49 of the 68 suppressed candidates fail the gradient test. The knob is an `SdfEllipsoid` with the scaled-sphere estimate (Lesson 07): f = (‖q / r‖ − 1) · min(r). On its surface ‖∇f‖ = min(r) · ‖q / r²‖, which is 1 at the tip of the shortest axis (0.07 m) and 0.07/0.15 = 0.47 at the tip of the longest. The holds measure 0.55 to 0.80 there (the smooth union and the noise mix in the box). The curvature formulas divide by ‖g‖ and depend on the zero set alone (Lesson 09 P6; its test on ‖p‖² − 2.25), so H is not spoiled. The gradient test guards against near-zero gradients, not against fields that are no exact distance.
</details>

<details><summary>T5</summary>

Measured with the scripted policy: reach fraction 0.98 takes 9 hand moves (19 foot moves), 0.9 takes 10 (19), 0.85 takes 11 (18). Each reaches the top. Shorter arms take smaller steps up the same knob rows; the residual stays below 10⁻⁴ m (largest 4.7 × 10⁻⁵ m, at 0.85).
</details>

<details><summary>T6</summary>

Measured: with wall clearance 0.45 m, d = 0.305 m and the pull is 0.345 W, against 0.193 W at 0.30 m (P9). With FABRIK and 1 iteration per tick, the largest hand error over the scripted climb is 0.128 m; with 3, 0.051 m; with 10 (the default), 3.4 mm. The limb error is the distance between the hand and its target: with 1 iteration the hand stops up to 0.128 m short of where it should be. Each tick continues from the last pose, so the error shrinks over the following ticks while the target stays still.
</details>
