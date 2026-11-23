# Lesson 12. Feet on the ground

Lesson scene: `game/scenes/lessons/12_feet_on_the_ground.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–11 are unchanged; the Lesson 11 scene keeps its sine-cycle legs and its distance-clock footsteps.

Complete Lesson 11 exercise E5 before reading this lesson; it contains one solution. (`FootRig` fires an event when the walk phase crosses a heel strike, with the sub-tick fraction, and `PlantFootstepReporter` stamps `/foot/step` with it.)

## 1. Orientation

Lesson 11 ended with a body whose legs swing on sines and know nothing of the ground. Its stance foot slides at 1.37 m/s on average while the body walks at 3 m/s (Lesson 11 P7), and its soles float or sink on the slope at the spawn (Lesson 11 O3). This lesson is stage 3 of decision 0002: raycasts find the ground, a two-bone IK solver bends each leg, and the pelvis is placed from the feet. It answers four questions:

1. Given a hip and a point for the ankle, where is the knee? (law of cosines, the pole vector)
2. How does a joint position become a bone rotation? (global and local bases, Lesson 11 P1 in reverse)
3. When does a foot leave the ground, and where does it land? (a phase-timed swing, a landing ray, a planted foot held in world space)
4. How high are the hips when the feet are where they must be? (the reach of a leg; the pelvis lowered until every foot is in reach)

The method: `FootRig` extends Lesson 11's `BodyRig` and overrides `advance()` only. The walk phase still advances with distance and still decides which foot swings. A swinging foot travels from its lift-off point to a landing target that a vertical ray finds a quarter stride ahead of its hip. At the heel-strike phase the foot is planted: its position is stored in world space and does not move until its next swing. The pelvis is lowered until both ankle targets are within 98 % of the leg length. `TwoBoneIk`, a solver written out by hand, bends each leg; the knee bends toward the body's heading. The foot is turned so that its sole lies on the ground normal. Godot's `TwoBoneIK3D` can solve the same targets instead (Q). Every plant emits a signal; `PlantFootstepReporter` sends the Lesson 05 footstep message from it, so sound and picture share one clock. The result: legs that conform to the slope and to a staircase, and stance feet that stand still on the ground.

Goal served (`plan.md`): "the way the character realistically traverses over complex geometry"; "a humanoid player that can walk, crawl, climb, and balance". Lesson 13 reads the planted feet as the contact set of the support polygon; Lesson 15 needs the same solver for arms on holds.

Files:

| File | Role |
|---|---|
| `game/src/body/two_bone_ik.gd` | `TwoBoneIk` (static): `solve()` (law of cosines, pole), `leg_bases()`, `foot_basis()`, `limit_tilt()`. |
| `game/src/body/foot_rig.gd` | `FootRig` (`@tool`, extends `BodyRig`): feet, rays, stepping, pelvis, solver switch, debug lines, signal `foot_planted`. |
| `game/scenes/grounded_player.tscn` | A copy of `body_player.tscn` (Lesson 11) whose `Rig` runs `foot_rig.gd`. |
| `game/src/audio/plant_footstep_reporter.gd` | `PlantFootstepReporter` (extends `FootstepReporter`, Lesson 05): `/foot/step` per plant. |
| `game/src/lessons/feet_on_the_ground.gd` | Scene root. Extends `skeleton_from_code.gd` (Lesson 11); Q, Y; places the step row; two lines in `HUD/RockLabel`. |
| `game/scenes/lessons/12_feet_on_the_ground.tscn` | The Lesson 11 scene with the grounded player, the plant reporter, and a `StepRow` (Lesson 02) built as a staircase. |
| `game/project.godot` | Input actions `cycle_foot_solver` (Q) and `toggle_foot_debug` (Y); `run/main_scene`. |
| `game/tests/test_12_*.gd` | The solver on 500 random chains; the rig on a floor box with a step; the scene, the keys, one message per plant. |
| `docs/decisions/0012-foot-placement.md` | Why steps are timed by the phase, why the hand-written solver is the default, where footsteps come from. |

Q and Y are keyboard keys only; no gamepad button is free. With this lesson every letter key is bound.

Reading: John J. Craig, *Introduction to Robotics*, chapter 4 (inverse manipulator kinematics): solvability, the workspace, multiple solutions, and the geometric solution of a planar arm, where the law of cosines gives the elbow angle. Samuel R. Buss, "Introduction to Inverse Kinematics with Jacobian Transpose, Pseudoinverse and Damped Least Squares methods", section 1. David Rosen, "An Indie Approach to Procedural Animation" (GDC 2014). Godot class references `TwoBoneIK3D`, `SkeletonModifier3D`, `PhysicsDirectSpaceState3D.intersect_ray()`. The DDG text does not treat inverse kinematics; this lesson cites no section of it. Full entries: `docs/references.md`.

## 2. Predict

Notation: the thigh has length a = 0.44 m, the shin b = 0.42 m; the ankle sits 0.08 m above the sole, so the hip of a straight leg is a + b = 0.86 m above its ankle and 0.94 m above the floor. A chain is root (hip) → middle (knee) → end (ankle); d is the distance from root to target. The body faces −z, up is +y. A bone's frame at rest has the body's axes, and a leg bone points along −y (Lesson 11).

- **P1.** Law of cosines. The ankle target lies 0.70 m straight below the hip. Compute the interior knee angle β (between thigh and shin) and the angle α at the hip between the thigh and the line hip → ankle. Where is the knee, relative to the hip, if it bends forward (−z)? Draw the triangle.
- **P2.** Reach. For which d does a solution exist? Write the knee's forward offset k(d) = a sin α(d) and evaluate it for d = 0.80, 0.85, 0.859 and 0.8599 m. What happens to dk/dd as d → a + b? A walking leg is often close to straight. What does this mean for a knee whose target moves by a millimeter per tick?
- **P3.** The pole. The three lengths fix the triangle up to a turn about the line hip → ankle. The solver picks the turn with a pole point P: the knee lies in the half plane bounded by that line that contains P. Write the unit vector v in that plane, perpendicular to u = (target − hip)/d, in terms of P − hip (one step of Gram–Schmidt). Then write the knee as hip + a (cos α u + sin α v). When does the construction fail? What does a pole behind the body do?
- **P4.** From positions to rotations. The solver returns hip, knee and ankle. The thigh's global basis has +y = (hip − knee)/a (the bone points along −y) and +x the hinge axis, normal to the plane of the triangle. Which of u × v and v × u gives +x = (1, 0, 0) for a straight leg with the knee forward? The pose of a bone is local: G_child = G_parent · L_child (Lesson 11 P1). Write L for the thigh, given the global basis H of the hips, and for the shin, given the thigh's basis. Why is the inverse of a basis its transpose here?
- **P5.** The pelvis. On flat ground the walk plants each foot a quarter stride, 0.35 m, ahead of its hip, and the body passes over it until the foot is 0.35 m behind. A leg may stretch to R = 0.98 (a + b). How far below its rest height must the hip be when the foot is 0.35 m ahead or behind? The walk cycle already lowers the hips by `bob_height` = 0.025 m when the legs are spread. How much does the pelvis offset add? The pelvis yaws ±6° (`pelvis_yaw_degrees`) and the hip joints sit 0.10 m from the center: by how much does that change the horizontal distance?
- **P6.** The stance. A planted foot is stored in world space. The phase moves by distance / 1.4 m. During one stance, how far does the body move, and where is the foot relative to the hip at the start and at the end? What is the speed of the stance ankle relative to the ground? Compare with Lesson 11 P7.
- **P7.** The swing. The swing foot moves along lerp(lift, target, s(u)) with u ∈ [0, 1) the swing progress and s(u) = u − sin(2πu)/(2π). Compute s(0), s(1), s'(0), s'(1) and the largest s'. The target moves with the body, which walks at 3 m/s. The swing lasts as long as the stance. Estimate the largest horizontal speed of the swing ankle.
- **P8.** Footsteps. At 3 m/s, how many plants per second? Lesson 05's gait clock fires every 0.75 m: how many per second? A physics tick at 60 Hz moves the phase by how much? If a plant were stamped at the end of the tick in which the phase crossed the strike, by how much could the stamp be late, in ms and in meters of travel?
- **P9.** Cost. How many rays per tick does stepping need, if a ray is cast only for a swinging foot? Lesson 11 measured 8.5 µs per `apply_pose()`. Guess the cost of one `TwoBoneIk.solve()` plus `leg_bases()` in GDScript, and of the whole update.

## 3. Read

### 3.1 `two_bone_ik.gd`

Read the class header and its diagram, then `solve()` from top to bottom. Each Q/A in it is one of P1–P3:

- The clamp of d to [|a − b|, a + b], less `STRAIGHT_MARGIN` (10⁻⁴ m), and `reached`: P2.
- The direction u, and the case of a target on the root.
- The pole's perpendicular part v and the fallbacks when the pole lies on the line: P3.
- `cos_alpha` and `cos_beta` from the law of cosines; the clamp of both to [−1, 1] guards against rounding. The knee is `root + a (cos α u + sin α v)`: P1.

`leg_bases()`: read the two Q/A. The hinge is u × v, the same for both bones: a knee is a hinge. `foot_basis()`: +y is the ground normal, the toes are the heading projected onto the ground plane. `limit_tilt()`: the normal is turned toward up by `Vector3.slerp()` when it tilts more than the limit (30° in `FootRig`).

`test_12_two_bone_ik.gd` checks 500 random chains: the end on the target, both bone lengths, the law of cosines, and the knee on the pole's side, all to 10⁻⁵ m or better.

### 3.2 `foot_rig.gd`: the feet

Read the class header: the five steps of `advance()`. Then `FootState`: one per foot, all points in world space. Then, in order:

- `advance()`: the phase and the amount as in `BodyRig.advance()`; `WalkCycle.sample()` still gives the base pose (arms, torso, hips yaw and bob). Read the Q/A on the air: feet are released while the body is not on the floor and planted under the hips on the first tick back.
- `home_point()`: the point under a hip at the rig's origin height. `ground_ray()`: a vertical ray from `ray_up` above to `ray_down` below the rig's origin, excluding the player's own body (read the Q/A in `_ready()`).
- `swing_progress()` and its Q/A: the phase intervals of `WalkCycle` mapped to [0, 1) for the swing and [1, 2) for the stance. `swing_ease()` and its Q/A: P7.
- `_update_foot()`: the core of the stepping. Read the Q/A on detecting a strike within a tick, then the three branches: strike (plant, emit), swing (lift-off on the first swing tick, then a new landing ray every tick), stance (hold the plant; replant at home when it is more than `replant_distance` away).
- `_update_target()`: read the Q/A on the fixed lead. The ray goes through home + heading · (lead − back_distance). `back_distance` is nonzero only at the strike (read the Q/A in `_update_foot()`).
- `ankle_target()`: the planted ankle during a stance; during a swing, the eased interpolation plus an arc. Read the Q/A on the height of the arc.

### 3.3 `foot_rig.gd`: the solve

`_solve_and_pose()`:

1. The targets go from world space to the skeleton's frame (`global_transform.affine_inverse()`).
2. The pelvis. Read the Q/A: P5 in code. Note the asymmetry below it: the pelvis drops at once and rises with an exponential blend (Lesson 02), so that a foot is never out of reach because the pelvis lagged.
3. Per leg: the hip joint from the hips' basis and offset; the pole one meter ahead of the knee's rest position; `TwoBoneIk.solve()`, `leg_bases()`, `foot_basis()`. Read the Q/A on turning a global basis into a pose rotation: P4.
4. `apply_pose()` (Lesson 11) writes the result.

`_measure_errors()` and `_on_skeleton_updated()` fill `ankle_errors`, the distance from each ankle to its target after the pose. Read why the two solvers are measured at different moments (3.4).

`test_12_foot_rig.gd` drives a `FootRig` by hand over a floor box with a 0.18 m step, with no player and no input: the stance ankle moves less than 10⁻⁴ m per tick, the plants alternate every 0.70 m, the plants past the edge lie on the step top, and the pelvis stays within its limits.

### 3.4 `TwoBoneIK3D`

`rebuild()` calls `BodyRig.rebuild()` and adds an internal `TwoBoneIK3D` under the skeleton with two settings (left and right): root bone `UpperLeg`, middle `LowerLeg`, end `Foot`, a target node and a pole node, both top-level `Node3D` children of the rig that `_solve_and_pose()` moves every tick. Read the Q/A on the pole node.

A `SkeletonModifier3D` does not run when the code sets the pose. The skeleton runs its modifiers during its own update, later in the frame (`modifier_callback_mode_process`, idle by default), emits `skeleton_updated`, and afterward restores the pose that the code wrote. A probe confirmed it: inside a `skeleton_updated` callback the modified ankle stood on the target; after the frame, `get_bone_global_pose()` returned the unmodified one. Two consequences follow: `FootRig` measures the engine's ankle error inside that callback, and any code that reads bone positions (Lesson 13's center of mass) must read them there or compute them itself.

### 3.5 `plant_footstep_reporter.gd`

Read the header. `_ready()` connects to the rig's signal. The signal arrives during the player's physics tick; this node's tick runs after it because `Footsteps` comes after `Player` in the tree (Godot processes nodes of equal priority in tree order). `_physics_process()` keeps Lesson 05's clock and landing rule and replaces the gait clock by the queued plants. Read the Q/A on the strike time. `_emit_at()` is Lesson 05's `_emit()` with the contact point and normal of the foot instead of the capsule's.

### 3.6 The scene

`grounded_player.tscn` is `body_player.tscn` with one line changed: the script of `Rig`. Why not an inherited scene of `body_player.tscn` that only overrides the script? The base scene would first build a `BodyRig`, connect its `proportions.changed` signal, and then swap the script; the new script's setter connects again and Godot reports the connection as a duplicate. A copy avoids the swap.

`feet_on_the_ground.gd` places the `StepRow` by the terrain height at the front edge of its first step. Read its Q/A. The row has steps of 0.06, 0.12 and 0.18 m with 2 m spacing, so consecutive steps touch: a staircase of 0.06 m risers that climbs while the hillside under it falls away along −z, and ends in a drop of 1.3 m.

## 4. Run and observe

Start the lesson scene. Y draws the rays (gray), the planted contacts (green crosses) and the swing targets with the line from lift-off (orange).

- **O1.** Stand still at the spawn. Press Q until the HUD at the top right reads "walk cycle", then Q again for "own IK". Look at the feet from the side (arrow keys). Which foot changes, and how? Read the pelvis offset on the HUD. Why is it negative on a slope while the capsule stands still?
- **O2.** Press Y and walk uphill at full stick. Watch a green cross and the foot on it. Does the foot move on the ground during its stance? Compare with the Lesson 11 scene. Where does the orange target sit relative to the body when the foot lands?
- **O3.** Walk to the staircase, 6 m to the left of the spawn and 4 m behind it (turn around with the arrow keys; the labels read 6, 12, 18 cm). Walk up it and off its far end. Watch the pelvis offset and the ankle errors on each step, at the drop, and on landing.
- **O4.** Press Q until "TwoBoneIK3D" and walk. Do the knees change? The ankles? The feet? Press Q again for the walk cycle and compare all three.
- **O5.** Start `audio/supercollider/05_footsteps.scd` (Lesson 05) and walk. Do the sounds and the plants coincide now? Count the sounds per second at full stick, and compare with the Lesson 11 scene (Lesson 11 O5).
- **O6.** Two motions that the stepping does not handle. Stop in the middle of a step. Where does the swinging foot end up? Then stand still and turn on the spot with the stick (a small push in a new direction turns `BodyMesh`). What do the feet do, and when does a foot move?
- **O7.** In a scratch script, time `TwoBoneIk.solve()` with `leg_bases()`, and read `FootRig.ik_milliseconds` while walking. Compare with P9 and with Lesson 11 O6.

## 5. Tweak

Make each change, run, observe, and revert. Most are exported properties of `Player/BodyMesh/Rig`, editable in the Remote Inspector while the game runs (Lesson 00 O3).

- **T1.** Set `reach_fraction` to 1.0. Watch the knees in mid-stance and the pelvis value. Which number on the HUD changes, and why does P2 advise against a leg that straightens fully?
- **T2.** Set `lead_fraction` to 0, then 0.5. Where do the feet land, and what does the pelvis do? Explain with P5 and P6.
- **T3.** In `_solve_and_pose()`, place the pole behind the knee: `hip + Vector3(0.0, -a, 0.0) - heading`. Walk. Then press Q for `TwoBoneIK3D`, which receives the same pole. Do the two solvers agree?
- **T4.** Set `step_height` to 0.3 and walk on flat ground, then up the staircase. Which rule in `ankle_target()` already lifts the foot over a riser at the default height?
- **T5.** In `_update_foot()`, pass 0 instead of the back distance to `_update_target()` at the strike. Measure the spacing of the plants along the direction of travel in a scratch script (`foot_planted` gives the points). What changes, and for which foot?
- **T6.** Set `max_pelvis_drop` to 0 (the Lesson 11 hips). Walk on flat ground and watch the ankle errors.

## 6. Exercises

- **E1 ★ The pelvis curve.** Derive, as a function of the phase on flat ground, the pelvis offset that `FootRig` computes at amount 1 (P5 gives two points of it: the extremes). Include the hips yaw and the bob. Plot your curve against `pelvis_offset` recorded from a `FootRig` driven by hand, as `test_12_foot_rig.gd` drives it. Where does the curve have corners, and why?
- **E2 ★★ Settling and turning.** O6 shows two failures: a foot left in the air at a stop, and legs that twist when the body turns on the spot. Add a second trigger for steps: a foot whose home point has moved more than a threshold (in position or in heading angle) takes a step of its own, with its own swing clock, while the other foot stays planted. Keep the phase-timed steps while walking. Which thresholds look natural? Measure how many steps a half turn on the spot takes.
- **E3 ★★ Edges.** A single ray finds a landing point but not whether the whole foot is supported. Cast rays under the heel and the toes as well (the foot capsule spans 0.24 m along the heading). When they disagree by more than a tolerance, move the target back or forward until the foot is supported, or tilt it within the ankle limit. Test on the staircase: count plants whose toes or heel overhang an edge before and after.
- **E4 ★★ Heel and toe.** The foot keeps its ground orientation during the whole stance. A walker rolls from heel to toe: at heel strike the toes point up, at lift-off the heel rises. Add a pitch of the foot about its hinge that follows the stance progress, and move the IK target so that the contact point (heel, then ball of the foot) stays on the ground. What happens to the pelvis curve of E1?
- **E5 ★★ Feet for `TwoBoneIK3D`.** O4 shows that the engine's solver places the legs but not the feet. Make the feet match the own solver in `ENGINE` mode, either by computing the foot's local rotation from the engine's result inside `skeleton_updated`, or with a second modifier after `TwoBoneIK3D`. Measure the largest angle between the feet of the two solvers before and after.
- **E6 ★★ What the foot hits.** Lesson 08 noted that footsteps on the boulders are classified by the terrain material under them. The landing ray now knows the collider it hit. Send rock weights when the ray hits the boulder mesh, and add the vertical distance between lift-off and plant (a step up or down) to the message as a seventh argument. Change the SuperCollider responder of Lesson 05 to use it, and check the new message in `sclang` with a printing `OSCdef` before changing the synth.
- **E7 ★★★ Swing paths.** The swing arc is a sine bump over a straight line. It does not see obstacles between lift-off and landing (a rock edge, a riser taller than the arc). Use a shape cast along the arc to detect collisions and raise or reroute the swing. Then compare with a swing that follows a curve built from the ground heights sampled along the path.

## 7. Reflect

- **R1.** The stepping is timed by a phase that only distance advances. A person's steps also answer balance: a push causes a step. Which inputs would a step trigger need (center of mass, its velocity, the support polygon), and which of them does Lesson 13 compute?
- **R2.** The pelvis is lowered until the feet are in reach, never raised. What would a pelvis that also moves sideways and forward over the stance foot look like, and which quantity (Lesson 13) should decide its position?
- **R3.** Lesson 15 needs arms that reach holds. The same solver works for shoulder → elbow → wrist. Where should the elbow's pole point, and what goes wrong for a hand that reaches over the head? When are three or more bones (`FABRIK3D`, `CCDIK3D`) needed?
- **R4.** Each plant is now an event with a position, a normal, a speed and a sub-tick time. Which other body events (a heel lift, a knee fully straight, a foot that lands short of its target) could be sounds, and which belong in the generative score of Lesson 28 rather than in the foley of Lesson 05?

## 8. Answers

<details><summary>P1</summary>

cos β = (a² + b² − d²) / (2ab) = (0.1936 + 0.1764 − 0.49) / 0.3696 = −0.3247, β = 108.9°. cos α = (a² + d² − b²) / (2ad) = (0.1936 + 0.49 − 0.1764) / 0.616 = 0.8234, α = 34.6°. The knee lies a cos α = 0.362 m below the hip and a sin α = 0.250 m ahead of it. `TwoBoneIk.solve()` with the hip at (0, 0.94, 0) returns the knee (0, 0.578, −0.250), α = 34.58°, β = 108.95°.
</details>

<details><summary>P2</summary>

A triangle with sides a, b, d exists for |a − b| ≤ d ≤ a + b: 0.02 m ≤ d ≤ 0.86 m. Near d = a + b, α is small and cos α ≈ 1 − α²/2, so α grows like the square root of (a + b − d): the derivative dk/dd = a cos α dα/dd is unbounded at full extension. Values from the solver: k = 0.158 m at d = 0.80, 0.065 at 0.85, 0.021 at 0.859, 0.0066 at 0.8599 m. A millimeter of target motion in the last centimeter moves the knee by centimeters: a nearly straight leg jitters. This is the singularity of the two-link arm at the boundary of its workspace (Craig, chapter 4). `reach_fraction` keeps the legs 2 % short of straight.
</details>

<details><summary>P3</summary>

v = w / ‖w‖ with w = (P − hip) − ((P − hip) · u) u. The knee is hip + a (cos α u + sin α v): a cos α along the line, a sin α toward the pole. The construction fails when w = 0, that is when the pole lies on the line hip → target (and when d = 0, where u is undefined); `solve()` falls back to u × (1, 0, 0) or u × (0, 0, −1). A pole behind the body puts the knee behind the line: the leg bends like a bird's. The solver returns the mirror image: with the pole at hip + (0, −0.44, +1) the P1 knee is (0, 0.578, +0.250).
</details>

<details><summary>P4</summary>

For a straight leg u = (0, −1, 0) and, with the knee forward, v = (0, 0, −1). u × v = ((−1)(−1) − 0, 0, 0) = (1, 0, 0). So the hinge is u × v. With x the hinge and y = (hip − knee)/a, z = x × y completes a right-handed frame, which is the identity at rest. From G_thigh = H · L_thigh: L_thigh = H⁻¹ G_thigh = Hᵀ G_thigh, and L_shin = G_thighᵀ G_shin; the foot likewise, L_foot = G_shinᵀ F. The bases are rotations (orthonormal, determinant 1; `leg_bases()` calls `orthonormalized()`), so their inverse is the transpose (Lesson 11 P1). The rest bases are the identity, so the local pose rotation equals the local basis; with other rest rotations it would be rest⁻¹ L (Lesson 11 E4).
</details>

<details><summary>P5</summary>

R = 0.98 × 0.86 = 0.843 m. With h = 0.35 m the hip may sit √(0.843² − 0.35²) = 0.767 m above the ankle instead of 0.86 m: 0.093 m lower. The walk cycle's bob already lowers the hips by 0.025 m at full spread, so the pelvis offset adds about −0.068 m. The yaw of ±6° moves each hip joint fore and aft by 0.10 sin 6° = 0.010 m, and at full spread the hip of the leading leg is turned forward and the trailing one back: h ≈ 0.36 m, √(0.843² − 0.36²) = 0.762 m, offset about −0.073 m. Measured with a `FootRig` driven by hand on flat ground at 3 m/s: the offset ranges from −0.074 to 0.000 m.
</details>

<details><summary>P6</summary>

The body moves half a stride, 0.70 m, per stance at any speed, because the phase moves by distance / stride. A foot planted 0.35 m ahead of its hip ends the stance 0.35 m behind it. The stance ankle is held in world space, so its speed relative to the ground is zero, against the mean 1.37 m/s and the largest 2.99 m/s of the Lesson 11 cycle. Measured in the scene, walking 6 s uphill from the spawn: the largest speed of a stance ankle was 1.5 × 10⁻⁵ m/s, rounding in the skeleton's 32-bit transforms. The ankle missed its target by at most 3.4 × 10⁻⁷ m.
</details>

<details><summary>P7</summary>

s(0) = 0, s(1) = 1; s'(u) = 1 − cos(2πu), so s'(0) = s'(1) = 0 and the largest s' is 2 at u = 0.5. The swing takes as long as the stance, the time the body needs for 0.70 m: 0.233 s at 3 m/s. The foot lifts 0.35 m behind its hip and lands 0.35 m ahead of the hip, which has moved 0.70 m: 1.40 m in 0.233 s, a mean of 6 m/s, twice the body's speed. In mid-swing the remaining distance from lift-off to the moving target is about 1.05 m; the eased term gives 2 × 1.05 / 0.233 = 9 m/s, and the moving target adds s · 3 m/s = 1.5 m/s: about 10.5 m/s. Measured: 10.77 m/s. A foot in mid-swing moves at three to four times the speed of the body, as in human walking.
</details>

<details><summary>P8</summary>

3 / 0.70 = 4.29 plants per second; the gait clock gives 3 / 0.75 = 4.0. A 60 Hz tick moves the body 0.05 m and the phase 0.05 / 1.4 = 0.036. A stamp at the end of the tick could be late by up to one tick, 16.7 ms, during which the body moves 0.05 m. With the fraction the stamp falls on the moment the phase crossed the strike. The landing ray is moved back by the same remainder (T5).
</details>

<details><summary>P9</summary>

One foot swings at a time (the swings of the two feet do not overlap), so one ray per tick while walking, plus one at each plant. Measured: 449 rays in 450 ticks of walking. `TwoBoneIk.solve()` plus `leg_bases()` takes 2.6 µs (mean of 10 000 calls, headless). The whole `FootRig` update takes 39 µs per tick without physics (driven by hand over a floor box) and about 0.12 ms in the scene, rays and the base pose included: under 1 % of a 16.7 ms frame.
</details>

<details><summary>O1</summary>

At the spawn the capsule's origin stands 0.009 m above `height_at()`. In walk-cycle mode both soles sit at the origin's height on a slope that falls to the right: one sole hangs in the air, the other sinks into the ground. With own IK each ankle stands on its ray hit plus 0.08 m along the normal (ankle error 7 × 10⁻⁹ m) and the soles tilt with the slope. The pelvis offset reads −0.050 m: the downhill foot is lower than the origin, and the hips drop until that foot is in reach. The phase at rest is 0, where the left foot is in mid-swing, so the left foot stands where its interrupted swing left it (O6).
</details>

<details><summary>O2</summary>

The foot stays on its cross for the whole stance (P6). In the Lesson 11 scene the foot slides back and forth. The orange target sits about 0.35 m ahead of the hip and moves with the body; the swing line runs from the last plant to it. Walking 6 s uphill from the spawn gave 23 plants, each within 0.01 m of `height_at()` (the ray hits the collision triangles, not the analytic surface), at 0.70 m intervals along the direction of travel; the distance between consecutive plants of opposite feet was 0.74–0.79 m, since it includes the 0.20 m between the hips and the rise of the slope. The pelvis offset averaged −0.166 m after the first second: on a slope, the trailing foot is lower than the leading one.
</details>

<details><summary>O3</summary>

The capsule climbs the 0.06 m risers (Lesson 02 measured a limit of 0.118 m). Measured from z = 43 m at full stick: plants on the walkway stood 0.11 to 1.33 m above the terrain below them, each on a step top. The pelvis offset stayed between about −0.03 and −0.11 m on the walkway (mean −0.085 m over the run). At the far end the capsule falls about 1.3 m: both feet are released, the legs take the walk cycle's angles, and on landing both feet are planted under the hips; the reporter sends one landing (foot 2) and 13 plants gave 14 messages. On the ticks after the landing the pelvis hits its limit of −0.35 m and one ankle misses its target by up to 0.072 m.
</details>

<details><summary>O4</summary>

The knees and ankles do not change: driven by hand with the same targets and poles, `TwoBoneIK3D` put the knees within 1.9 × 10⁻⁷ m and the ankles within 2.4 × 10⁻⁷ m of `TwoBoneIk`'s. The feet change: the engine turns the thigh and shin and keeps the foot's local rotation from the walk cycle, which was computed for other thigh and shin angles. The largest angle between the feet of the two solvers over 2 s of walking was 34.4°. The walk cycle mode is Lesson 11: sliding stance feet, soles off the ground. E5 gives the engine's legs feet.
</details>

<details><summary>O5</summary>

Each sound comes with a plant: one `/foot/step` per plant (`test_12_feet_scene.gd` checks the count), stamped at the sub-tick moment of the strike. At 3 m/s, 4.29 per second, against the 4.0 of the gait clock in the Lesson 11 scene, where sounds and steps drifted apart and met again every 14 steps. The slope argument now comes from the normal under the foot and the surface weights from the contact point; on the staircase the plants report the terrain material, because the step boxes are painted with it.
</details>

<details><summary>O6</summary>

A stop: the phase stops with the distance, so the swing stops with it. The foot comes down onto the line from its lift-off to its target as the amount, and with it the arc, decays; it does not land on a ray hit, sends no plant, and may stand above or below the ground where the terrain curves between the two points. Turning on the spot: `BodyMesh` turns, the planted feet stay where they are, the hips turn above them and the legs twist. No step comes, since the phase does not move and a foot is replanted only beyond 0.9 m from its home point; after a half turn each foot is 0.20 m from its home point and the legs cross. E2 adds steps for both cases.
</details>

<details><summary>O7</summary>

2.6 µs per `solve()` with `leg_bases()` (mean of 10 000 calls, headless); `ik_milliseconds` reads about 0.12 ms while walking in the scene, which includes the rays, both solves, `WalkCycle.sample()` (5.1 µs) and `apply_pose()` (8.5 µs, Lesson 11 O6). The same update driven by hand over a single floor box took 39 µs per tick; the difference comes from the scene and was not broken down further. 0.12 ms is 0.7 % of a 16.7 ms frame.
</details>

<details><summary>T1</summary>

With R = a + b the pelvis drops less: the lowest offset on flat ground went from −0.074 m to −0.055 m (driven by hand). The ankle error rises from about 10⁻⁷ m to 10⁻⁴ m, the size of `STRAIGHT_MARGIN`: targets at full reach are clamped. The knee's sensitivity of P2 applies at every tick where a leg is straight: the knee position becomes ill-conditioned, and any noise in the targets (a ray across terrain triangles) shows as knee flicker. With 0.98 the leg stays out of the steep part of k(d).
</details>

<details><summary>T2</summary>

`lead_fraction` 0: the foot lands under the hip and ends the stance 0.70 m behind it. The pelvis reaches its limit of −0.35 m and the ankle still misses by up to 0.047 m (driven by hand on flat ground). 0.5: the foot lands 0.70 m ahead and ends under the hip; the pelvis again reaches −0.35 m, now at the landing, and every ankle reaches its target. Only 0.25 centers the stance under the hip and keeps the largest horizontal distance, 0.35 m, as small as possible.
</details>

<details><summary>T3</summary>

The knees bend backward with both solvers: the solver has no preference of its own, the pole decides (P3). `TwoBoneIK3D` follows the pole node in the same way. Driven by hand on a copy of the project, the knees of the two solvers agreed within 2.5 × 10⁻⁷ m. Their feet differed by up to 88.8°: the walk cycle's foot rotation assumes a knee that bends the other way.
</details>

<details><summary>T4</summary>

The arc rises 0.30 m at full amount; the feet lift high, like stepping through deep snow. The rule that clears a riser at the default is the term 0.5 |Δy| added to the arc's height, where Δy is the height difference between lift-off and landing: a 0.06 m riser adds 0.03 m. It assumes the riser lies halfway along the swing; E7 removes that assumption.
</details>

<details><summary>T5</summary>

The plant goes where the target is at the end of the tick, not at the strike: up to one tick of travel (0.05 m at 3 m/s) too far ahead. Driven by hand at 60 Hz (on a copy of the project): at 3 m/s the first plant landed at 0.70 m and every later one 0.05 m too far ahead, since 0.70 m is fourteen ticks of 0.05 m and every strike after the first fell at the start of a tick, a whole tick of travel before the tick's end; the gaps read 0.75, then 0.70. At 2.3 m/s the error changed from plant to plant (0.003 to 0.042 m), and the gaps read 0.69 and 0.729 m. With the correction every gap is 0.70 m at both speeds. Both feet are affected alike; the size depends on where each strike falls within its tick.
</details>

<details><summary>T6</summary>

The pelvis keeps the walk cycle's height. At the ends of each stance the foot is out of reach: the leg stretches toward it and the ankle misses by up to 0.048 m (driven by hand on flat ground). The foot lifts from its plant at the end of the stance and touches down late at the front.
</details>
