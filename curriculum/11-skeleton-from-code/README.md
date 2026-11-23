# Lesson 11. A skeleton from code

Lesson scene: `game/scenes/lessons/11_skeleton_from_code.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–10 are unchanged; they keep the capsule.

## 1. Orientation

Since Lesson 00 the player has been a capsule with a box for a nose. Phase 4 replaces what is drawn, not what collides: the capsule still meets the world, and a body is drawn inside it. This is stage 2 of decision 0002 (`docs/decisions/0002-character-model.md`). The lesson answers four questions:

1. How is a body described as data? (bones, parents, rest transforms; capsules attached to bones)
2. Where is a hand, given the angles of the joints above it? (rigid transforms, composition, forward kinematics)
3. How is a joint angle stored and combined? (rotation matrices and unit quaternions)
4. How does the body move with the capsule before it knows where the ground is? (a walk phase driven by distance; a placeholder cycle of sines)

The method: a `BodyProportions` resource lists 15 bones with their lengths. `BodyRig` builds a `Skeleton3D` from that list at load time and hangs one `MeshInstance3D` with a `CapsuleMesh` on each bone through a `BoneAttachment3D`. Every physics tick, `BodyPlayer` (a subclass of `Player`) measures how far the capsule moved on the ground plane. `BodyRig` turns the distance into a phase, `WalkCycle` turns the phase into one quaternion per joint, and the skeleton composes the joints from the hips outward. The result: a figure of capsules that walks where the capsule walks, turns where it turns, and stands still when it stops. Its feet do not yet know where the ground is (O3, O4); Lesson 12 places them.

Goal served (`plan.md`): "a humanoid player that can walk, crawl, climb, and balance". Every later lesson of Phase 4 writes into this skeleton: Lesson 12 the leg angles, Lesson 13 the center of mass (it needs the bone positions of this lesson), Lesson 14 the stances.

Files:

| File | Role |
|---|---|
| `game/src/body/body_proportions.gd` | `BodyProportions` (`@tool` Resource, so that the rig also builds in the editor): lengths and radii; `bone_specs()` returns the bone list. |
| `game/src/body/forward_kinematics.gd` | `ForwardKinematics`: local transform of a bone, global transforms of a chain, quaternion rotation written out. |
| `game/src/body/walk_cycle.gd` | `WalkCycle` (Resource): joint angles as functions of a phase. `Pose` holds the result. |
| `game/src/body/body_rig.gd` | `BodyRig` (`@tool` Node3D): builds the skeleton and its capsules; `advance()` and `apply_pose()`. |
| `game/src/body/body_player.gd` | `BodyPlayer` (extends `Player`): feeds the rig with the capsule's motion; body view switch. |
| `game/scenes/body_player.tscn` | Inherits `scenes/player.tscn`; hides `Capsule` and `Nose`; adds `BodyMesh/Rig`. |
| `game/data/body/default_proportions.tres`, `placeholder_walk.tres`, `body_material.tres` | The data the rig reads (decision 0004). |
| `game/src/lessons/skeleton_from_code.gd` | Scene root. Extends `raymarching.gd` (Lesson 10); E key; one HUD line. |
| `game/scenes/lessons/11_skeleton_from_code.tscn` | The Lesson 10 scene with `Player` instanced from `body_player.tscn`. |
| `game/project.godot` | Input action `toggle_body_view` (E); `run/main_scene`. |
| `game/tests/test_11_*.gd` | FK by hand against `Skeleton3D`; quaternion identities; walk-cycle symmetry; the scene, walking, the E key. |

E is a keyboard key only; no gamepad button is free.

Reading: John J. Craig, *Introduction to Robotics*, chapter 2 (rotation matrices, homogeneous transforms, composition, the order of compound rotations) and chapter 3, sections 3.1–3.3 (link frames and forward kinematics of a chain). Ken Shoemake, "Animating rotation with quaternion curves" (1985), sections 1–3. Godot documentation: "Using 3D transforms"; class references `Skeleton3D`, `BoneAttachment3D`, `Quaternion`. The DDG text does not treat rotation groups or quaternions; this lesson cites no section of it. Full entries: `docs/references.md`.

## 2. Predict

Notation: a rigid transform T = (R, t) maps a point x to R x + t, with R a rotation matrix (RᵀR = I, det R = 1). The body faces −z, up is +y, its left is −x. Each bone's frame at rest has the same axes as the body. Lengths (`default_proportions.tres`): thigh 0.44 m, shin 0.42 m, ankle height 0.08 m, spine 0.22 m, chest 0.26 m, neck 0.08 m, head 0.24 m, shoulder half-width 0.19 m, shoulder drop 0.04 m, upper arm 0.29 m, forearm 0.27 m.

- **P1.** Write the composition of two rigid transforms, T₂ ∘ T₁ = (R₂, t₂)(R₁, t₁), as one pair (R, t). Write the inverse of (R, t). Why is the inverse of R its transpose? How many numbers describe a rigid transform in 3D, and how many does a `Transform3D` store?
- **P2.** The hip joints sit at height thigh + shin + ankle above the soles. Compute it, and the height of the top of the head. Then the left shoulder joint (x, y, z) and the left wrist at rest. Rotate the left upper arm by +90° about its x axis: where is the wrist? Bend the elbow by another +90° about its own x axis: where is the wrist now? Use: a rotation by a about +x sends (x, y, z) to (x, y cos a − z sin a, y sin a + z cos a).
- **P3.** Order. Let v = (0, −1, 0), a limb hanging down. Compute R_y(90°) R_x(90°) v and R_x(90°) R_y(90°) v. Describe each in words: which rotation acts about the body's axes, and which about axes that the first rotation has already turned? In a chain hips → thigh, a pose rotation q of the thigh is applied in the thigh's rest frame. Should the code write `rest_basis * Basis(q)` or `Basis(q) * rest_basis`? When do the two agree?
- **P4.** A unit quaternion q = (cos(θ/2), sin(θ/2) u) with ‖u‖ = 1 rotates by θ about u through v ↦ q v q*. Write the quaternion of +90° about +x. Expand q v q* for q = (w, u) into v + 2w (u × v) + 2u × (u × v), and apply it to v = (0, −1, 0). Why do q and −q give the same rotation? What does the product q₁ q₂ do to a vector?
- **P5.** Interpolation. Average the identity matrix and the matrix of a half turn about +y entry by entry. Is the result a rotation? Now take the quaternions of the same two rotations, average them, normalize. Which rotation results? Which of the two quaternions of the half turn did you use, and does the answer depend on it?
- **P6.** Forward kinematics. With 15 bones whose parents come before their children, how many matrix products compute every global transform? How many local transforms lie on the chain from the root to the left wrist? A change of the hip yaw by 1° moves which points of the body, and how far does it move the left wrist at rest?
- **P7.** The walk cycle swings each thigh by ±24° (`hip_swing_degrees`) and keeps the leg straight while the foot is on the ground. During one stance the ankle moves backward relative to the hips by how much? The body moves forward by half a stride, 0.70 m, during one stance. If the two numbers agree, does the foot stand still on the ground at every instant? Sketch the ankle's horizontal position over the stance as a function of time, and the body's.
- **P8.** The legs have length l = 0.86 m from hip to ankle. Swung by ±24°, how far does the ankle rise relative to the hips compared with a vertical leg? The cycle lowers the hips by `bob_height` = 0.025 m when the legs are spread. With the hips at their rest height when the legs pass each other, where are the soles relative to the floor of the capsule over a cycle?
- **P9.** `BodyPlayer` advances the phase by distance / stride_length with stride_length = 1.4 m. At 3 m/s, how many cycles per second, and how many steps? Lesson 05's `FootstepReporter` fires one footstep every 0.75 m. Do the sounds and the visible steps stay together?

## 3. Read

### 3.1 `body_proportions.gd`

Read the exported lengths, `hip_height()` and `standing_height()`. Then `bone_specs()`. Each entry has a name, a parent index, an offset (the joint in the parent's frame) and a list of segments, each a capsule from a to b with a radius, in the bone's own frame. Follow the left leg: `UpperLeg.L` sits at (−0.10, 0, 0) in the frame of `Hips`; `LowerLeg.L` at (0, −0.44, 0) in the frame of `UpperLeg.L`; `Foot.L` at (0, −0.42, 0) in the frame of `LowerLeg.L`. Its capsule lies along −z with its lowest point on y = −ankle_height. Read the Q/A on identity rest rotations.

Questions while reading: why does the loop over sides append `UpperLeg`, `LowerLeg`, `Foot`, then `UpperArm`, `LowerArm`, and why do the parent indices come from `specs.size()` at that moment? What would break if `Chest` came after `UpperArm.L` in the list?

### 3.2 `forward_kinematics.gd`

Three functions, each a line of P1–P6.

- `local_transform()`: the rest translation, and the rest rotation followed by the pose rotation. Read the Q/A on the order: this is P3.
- `global_transforms()`: one pass over the list, G_i = G_parent(i) · L_i. Read the Q/A on why one pass suffices: this is P6.
- `rotate()`: P4 in code. Godot's `Quaternion * Vector3` computes the same; the function exists to make the formula visible.

`test_11_forward_kinematics.gd` checks `rotate()` against Godot on 50 random rotations, Basis(q r) = Basis(q) Basis(r), and the whole FK pass against `Skeleton3D.get_bone_global_pose()` with a random rotation on every bone. The largest difference is below 10⁻⁵ m.

### 3.3 `body_rig.gd`

`rebuild()`:

- `add_bone()`, `set_bone_parent()`, `set_bone_rest()` build the bone list from the specs. Read the Q/A on `reset_bone_poses()`. In Godot 4 a bone's pose is the whole local transform: it replaces the rest, it is not added to it. A probe with two bones (rest offsets 1 and 0.5 along y) gives the child a global position (0, 1.5, 0) after `reset_bone_poses()` and (0, 0, 0) without it.
- One `BoneAttachment3D` per bone with segments. An attachment is a `Node3D` whose transform the skeleton overwrites with the bone's global pose, so its children follow the bone.
- `_capsule()`: read the two Q/A. A `CapsuleMesh` lies along its own y axis with its center at the origin, and `height` includes both caps, so height = |b − a| + 2r.

All of this goes into internal children (`INTERNAL_MODE_FRONT`), as the terrain mesh of Lesson 01 does: the `.tscn` holds only the `Rig` node and its three resources.

`advance()`: the phase moves by distance / stride_length and wraps with `fposmod`. The amount follows the speed fraction with the exponential blend of Lesson 02 (`1 − exp(−k Δt)`, k = `amount_responsiveness` = 6 per second). `apply_pose()` writes position and rotation into each bone. Note `get_rotation_quaternion()`: the skeleton stores quaternions, not matrices.

### 3.4 `walk_cycle.gd`

Read the class header: one phase φ ∈ [0, 1) per stride, left leg swinging forward on φ ∈ (−0.25, 0.25) and right leg on (0.25, 0.75), with left heel strike at φ = 0.25 and right at 0.75. Then `pitch()` and its Q/A: a positive angle swings a limb forward (P2's rotation formula). `sample()`:

- Hips: a sine. Knees: bent only during the swing (Q/A).
- Feet: the Q/A on minus the sum. This is the 2D version of P6: angles about parallel axes add.
- Arms: opposite to the leg on the same side.
- Pelvis yaw and chest counter-yaw: read the Q/A on the sign.
- `hips_offset`: twice per cycle, cos(4πφ).

Each angle is multiplied by `amount`. The pose is a function of (φ, amount) only: no time, no ground, no memory.

### 3.5 `body_player.gd` and `body_player.tscn`

`body_player.tscn` is an inherited scene: its root is an instance of `player.tscn` with a different script, and its `[node ... parent="BodyMesh"]` entries override or add children. Open it in a text editor and compare with `player.tscn`. `Rig` is added under `BodyMesh`; `Player._physics_process()` already turns `BodyMesh` toward the direction of travel (Lesson 00), so the body faces where it walks without new code.

`_physics_process()` calls `super(delta)`, then measures the motion. Read the Q/A on measuring position instead of reading `velocity`, and on teleports.

Why does the lesson subclass `Player` instead of editing it? The scenes of Lessons 00–10 use `player.tscn`, and the earlier root scripts type the node as `Player` (`sandbox.gd`: `@onready var _player: Player = $Player`). A subclass passes that type check, and the earlier scenes keep their capsule.

### 3.6 `skeleton_from_code.gd` and the scene

The root adds the E key (body view: rig, rig and capsule, capsule) and appends one line to `HUD/Label`: view, phase, amount, ground speed. The scene file differs from the Lesson 10 scene in three lines: the script, the root's name, and the path of the player scene.

## 4. Run and observe

Start the lesson scene.

- **O1.** Stand still, then press E twice to see the rig inside the capsule, then the capsule alone. Walk with the rig and capsule view. Which parts of the body leave the capsule, and when? Which parts of the capsule does the body never fill? What does this mean for the collision of Lesson 12's feet and Lesson 15's hands?
- **O2.** Walk at full stick, then at half stick, and watch the HUD's phase, amount and speed. How does the cadence change with speed? How does the size of the steps change? A real walker at half speed takes shorter steps at a slightly lower cadence; which of the two does the placeholder do? (Measured in a test run: after 2 s of full stick uphill from the spawn the speed was 2.81 m/s and the amount 0.94.)
- **O3.** Stand still at the spawn, which lies on a slope that falls to the right of the view direction. Look at the feet from the side with the arrow keys. Then walk uphill for 2 s and stop. Where are the soles relative to the ground in each case? (Measure in a scratch script: the sole height minus `Terrain.height_at()` below it.)
- **O4.** Walk at full stick and watch one foot during its stance (the time it should stand on the ground). Does it stay at one place on the ground? Lower the walk speed in the editor (`walk_speed` on `Player`, 1.0) and watch again.
- **O5.** Start `audio/supercollider/05_footsteps.scd` (Lesson 05) and walk. Do the footstep sounds coincide with the visible steps? Count visible steps between two moments when a sound and a step coincide.
- **O6.** In a scratch script, time `BodyRig.rebuild()`, `WalkCycle.sample()` and `BodyRig.apply_pose()`. Compare with the 16.7 ms of a frame at 60 Hz and with the sampling time of the boulder pile (Lesson 08: about 640 ms).

## 5. Tweak

Make each change, run, observe, and revert.

- **T1.** In `placeholder_walk.tres` (Inspector), set `stride_length` to 0.7, then 2.8. What changes in the cadence? Which setting makes the feet slide less? Predict before measuring.
- **T2.** In `ForwardKinematics.local_transform()`, swap the product to `Basis(rotation) * rest.basis`. Does anything change on screen? Why? (P3.)
- **T3.** In `WalkCycle.sample()`, replace `maxf(0.0, c)` by `maxf(0.0, -c)` in the left knee and `maxf(0.0, -c)` by `maxf(0.0, c)` in the right knee. Describe the walk.
- **T4.** Set the foot rotations to `Quaternion.IDENTITY` (remove the compensation). Watch the toes during the swing and the stance.
- **T5.** In `BodyRig._capsule()`, remove the branch for d close to −y, so that `Quaternion(Vector3.UP, d)` handles every segment. Does any capsule change? Print `Quaternion(Vector3.UP, Vector3.DOWN)` in a scratch script and explain.
- **T6.** Set `amount_responsiveness` on `Rig` to 1, then 30. Start and stop walking. Which value looks closer to a person who starts walking, and which artifact appears at the other?

## 6. Exercises

- **E1 ★ Stride from geometry.** The stride is a constant 1.4 m while the swing amplitude scales with `amount`. Derive, from P7, the stride that makes the ankle's mean backward speed during the stance equal to the walking speed, as a function of the hip amplitude and the leg length. Make `stride_length` follow the amount in a copy of `WalkCycle`, and measure the mean and largest slip of the stance foot at amounts 0.25, 0.5 and 1 before and after (use the slip measurement of O4).
- **E2 ★ Blending with slerp.** Replace the scaling of angles by `amount` with a blend: compute the full walk pose (amount 1) and the rest pose, and interpolate each joint with `Quaternion.slerp()`. For which joints is the result identical to the scaling, and why? Add a joint whose pose is a composition of two rotations (the hips: yaw and a forward lean) and find where the two methods differ.
- **E3 ★★ Frames on screen.** Draw the axes of every bone frame (three short lines per bone, red x, green y, blue z) with an `ImmediateMesh`, computed from `ForwardKinematics.global_transforms()` and not from the skeleton. Toggle it with a free key. Use it to check P3 visually: rotate one bone by R_y R_x and by R_x R_y.
- **E4 ★★ Bone-aligned rest frames.** Rigs exported from modeling programs point each bone's +y along the limb, so a leg bone has a rest rotation of a half turn. Write a second `bone_specs()` with such rest rotations (same joint positions), and change the walk cycle so the figure walks as before. Where does the order in `local_transform()` matter now (T2)? What would a pose rotation "about x" mean for a bone whose x axis points backward?
- **E5 ★★ Footsteps from the phase.** Lesson 05 counts distance with its own `GaitClock` at 0.75 m per step (O5). Fire `/foot/step` from the walk phase instead: a left strike when φ crosses 0.25 and a right strike at 0.75, with the sub-tick fraction and time tag of Lesson 05. Compare the strike times of both clocks over 20 m.
- **E6 ★★★ Leaning into turns.** Tilt the body toward the center of a turn and forward when accelerating: compute the horizontal acceleration from the capsule's velocity, build a lean quaternion for `Hips`, and compose it with the walk cycle's yaw. Which order of composition gives a lean about the direction of travel, and which a lean about the world axes? Smooth the acceleration and justify the time constant.

## 7. Reflect

- **R1.** The skeleton is drawn, not simulated: physics still sees one capsule. Lesson 12 casts rays for the feet and Lesson 15 needs hand contacts with rock. Which body parts need collision shapes of their own, and which queries can stay as ray or shape casts from bone positions?
- **R2.** Lesson 13 computes a center of mass. With the capsule radii and lengths of `BodyProportions` and a density, each capsule has a mass and a centroid in its bone's frame. Which transforms of this lesson take each centroid to world space, and how often per second must they be evaluated?
- **R3.** The walk cycle is a function of the phase only. A person on uneven ground changes stride and timing step by step. Which inputs would the cycle need (ground height ahead, slope, balance margin), and which of them are already available in the code of Lessons 02, 05 and 07–10?
- **R4.** Each joint is a quaternion per tick. Which of those numbers would make interesting control data for SuperCollider (OSC, Lesson 04): the phase, the swing angle, the angular velocity of a joint? At what rate, and with which timing scheme of Lesson 05?

## 8. Answers

<details><summary>P1</summary>

(R₂, t₂)(R₁, t₁) x = R₂ (R₁ x + t₁) + t₂ = (R₂R₁) x + (R₂ t₁ + t₂), so the pair is (R₂R₁, R₂t₁ + t₂). The inverse solves y = R x + t for x: x = R⁻¹(y − t), the pair (R⁻¹, −R⁻¹t). R preserves lengths and angles, so its columns are orthonormal; RᵀR has entries (column i · column j) = δᵢⱼ, so Rᵀ = R⁻¹. A rigid transform in 3D has six degrees of freedom (three for the rotation, three for the translation). `Transform3D` stores twelve floats: a 3 × 3 `Basis` and a `Vector3` origin. The basis has six redundant numbers, bound by the orthonormality conditions, and rounding can make it drift from a rotation after many products (`Basis.orthonormalized()` repairs it).
</details>

<details><summary>P2</summary>

Hips: 0.44 + 0.42 + 0.08 = 0.94 m. Head top: 0.94 + 0.22 + 0.26 + 0.08 + 0.24 = 1.74 m (`standing_height()`; `test_11_forward_kinematics.gd` checks it on the skeleton). Left shoulder: x = −0.19, y = 0.94 + 0.22 + 0.26 − 0.04 = 1.38, z = 0. Wrist at rest: (−0.19, 1.38 − 0.29 − 0.27, 0) = (−0.19, 0.82, 0). After +90° at the shoulder the whole arm points along −z: the wrist is at (−0.19, 1.38, −0.56). After a further +90° at the elbow the forearm, whose rest direction (0, −1, 0) is now turned by 180° in total, points along +y: elbow (−0.19, 1.38, −0.29), wrist (−0.19, 1.65, −0.29). Measured with `Skeleton3D.get_bone_global_pose()`: (−0.19, 0.82, 0), (−0.19, 1.38, −0.56), (−0.19, 1.65, −0.29).
</details>

<details><summary>P3</summary>

R_x(90°) v = (0, 0, −1); then R_y(90°) (0, 0, −1) = (−1, 0, 0). In the other order R_y(90°) v = v (a vertical vector does not change under a rotation about the vertical), then R_x(90°) v = (0, 0, −1). Measured with Godot's `Basis`: (−1, 0, 0) and (0, 0, −1). Read right to left, R_y R_x v first swings the limb forward about the body's x axis and then turns the result about the body's y axis: both rotations about fixed axes. Read left to right, the same product is "turn the frame about y, then swing about the turned frame's x axis". A pose rotation is expressed in the bone's own rest frame, so it stands on the right of the rest basis: `rest_basis * Basis(q)`. The two orders agree when the rest basis and the pose rotation commute, in particular when the rest basis is the identity, as here (T2).
</details>

<details><summary>P4</summary>

q = (cos 45°, sin 45° (1, 0, 0)) = (0.7071; 0.7071, 0, 0); Godot prints `(0.707107, 0, 0, 0.707107)` (x, y, z, w). Expansion: with q = (w, u) and the quaternion product (a, p)(b, r) = (ab − p·r, a r + b p + p × r), the product q (0, v) q* simplifies, using ‖q‖ = 1, to v + 2w (u × v) + 2u × (u × v). For v = (0, −1, 0) and u = (s, 0, 0), s = w = 0.7071: u × v = (0, 0, −s), 2w (u × v) = (0, 0, −2s²) = (0, 0, −1); u × (u × v) = (0, s², 0), doubled (0, 1, 0). Sum: (0, −1, 0) + (0, 0, −1) + (0, 1, 0) = (0, 0, −1), as in P2. The formula is quadratic in q, so −q gives the same result: both signs of the half-angle form describe the same rotation (θ and θ + 360° about u). q₁ q₂ v (q₁ q₂)* = q₁ (q₂ v q₂*) q₁*: first q₂, then q₁, the same order as the matrix product Basis(q₁) Basis(q₂), which the test checks.
</details>

<details><summary>P5</summary>

The half turn about y is diag(−1, 1, −1). The average with I is diag(0, 1, 0): a projection onto the y axis, singular, not a rotation. The quaternions are (1; 0, 0, 0) and (0; 0, 1, 0). Their average (0.5; 0, 0.5, 0), normalized, is (0.7071; 0, 0.7071, 0): a rotation by 90° about +y, halfway. With −q for the half turn, (0; 0, −1, 0), the result is 90° about −y: also halfway, the other way round. Both are valid, since a half turn is reached equally by both directions. Godot's `slerp()` picks the sign itself: `Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP, PI), 0.5)` printed `(0, -0.707107, 0, 0.707107)`, 90° about −y. For rotations less than 180° apart, slerp chooses the sign with a positive dot product, which is the shorter way.
</details>

<details><summary>P6</summary>

One product per bone except the root: 14. The chain to the left wrist is Hips, Spine, Chest, UpperArm.L, LowerArm.L: five local transforms, the last applied to the wrist point (0, −0.27, 0). The hip yaw rotates every bone below `Hips` in the tree, which is every bone: the whole body turns about the vertical through the hip center. The left wrist at rest lies 0.19 m from that vertical, so 1° moves it by 0.19 × π / 180 = 3.3 mm.
</details>

<details><summary>P7</summary>

With a straight leg of length l = 0.86 m (hip to ankle) at angle θ from vertical, the ankle is l sin θ ahead of the hip. Over the stance θ goes from +24° to −24°: the ankle moves 2 l sin 24° = 0.700 m backward relative to the hips. The amplitude and the stride were chosen so that this equals half the stride, 0.70 m. The means agree, the instants do not: the hip angle is 24° sin(2πφ), so l sin θ is close to a sine of time, fast in the middle of the stance and at rest at its ends, while the body moves at a constant speed. The foot runs backward faster than the body moves forward in mid-stance and lags behind at the ends: it slides back and forth on the ground. Measured over a cycle at amount 1 and 3 m/s (`Skeleton3D` poses at 2000 phases): mean absolute slip 1.37 m/s, largest 2.99 m/s at the ends of the stance, where the foot moves with the body.
</details>

<details><summary>P8</summary>

l (1 − cos 24°) = 0.86 × 0.0865 = 0.074 m. The hips drop by 0.025 m at full spread (φ = 0.25, 0.75), so a foot at full spread is 0.074 − 0.025 = 0.049 m above where a vertical leg would put it; when the legs pass each other the hips are 0.025 m above rest and the stance sole is 0.025 m above the floor; the swing foot is higher by the knee bend. The analytic minimum of the stance sole, 0.025 cos 4πφ + 0.86 (1 − cos(24° sin 2πφ)), is 0.025 m at the passing instant. Measured over a cycle at amount 1, the lowest point of the left foot capsule never comes closer than 0.016 m to the floor. The 0.009 m difference is capsule geometry: the measurement takes the lowest point of the rounded foot capsule as the foot pitches, not the ankle-height reference point of the analytic formula. The body floats while it walks. A walker whose hips followed the legs exactly would drop by 0.074 m; Lesson 12 computes the hips from the feet instead.
</details>

<details><summary>P9</summary>

3 / 1.4 = 2.14 cycles per second, 4.29 steps per second, each 0.70 m. `FootstepReporter` fires 3 / 0.75 = 4.0 per second. The sounds fall behind the visible steps by 0.05 m per step; after about 7 steps the offset is half a step, and the two coincide again after about 14 (P9 assumes the two clocks start together; they do not, since `GaitClock` and the walk phase start at different values). E5 removes the second clock.
</details>

<details><summary>O1</summary>

The capsule has radius 0.35 m and height 1.8 m; the head top is at 1.74 m. The shoulders reach x = ±(0.19 + 0.045) = ±0.235 m, inside. The feet leave the capsule: measured over a cycle at amount 1, the left ankle's z relative to the rig ranges from −0.36 m (0.36 m ahead, at the front of the stride) to +0.45 m (behind, when the bent knee lifts the foot at the start of the swing). The toes reach 0.18 m beyond the ankle. The capsule's shoulders above the head and its sides at hip height are empty. The physics shape is a poor model of the feet and hands, which are the contacts that matter from Lesson 12 on.
</details>

<details><summary>O2</summary>

The phase advances by distance / 1.4 m, so the cadence is proportional to the speed: half speed, half cadence. The step length stays 0.70 m because the stride is fixed, but the drawn steps shrink: the angles scale with the amount. The figure at half speed swings its legs half as far at half the cadence, which a person does not do, and its feet slide (E1). The amount lags the speed by the blend time 1 / 6 s.
</details>

<details><summary>O3</summary>

At the spawn (0, 40), at rest: left sole 0.022 m below the terrain, right sole 0.015 m above it. After 2 s uphill and 2 s standing, at (−0.03, 34.34): left 0.066 m above, right 0.018 m below. The capsule's origin was 0.009 m and 0.041 m above `height_at()` below it: the rounded bottom of the capsule touches the slope off-center, so the origin floats by an amount that depends on the slope. The rig puts both soles at the capsule's origin height and ignores the slope across the body. Lesson 12 casts a ray per foot.
</details>

<details><summary>O4</summary>

The foot slides: forward at the ends of the stance, backward in its middle (P7). At 1 m/s the amount is 1/3: the swing is 8°, the ankle moves 2 × 0.86 × sin 8° = 0.24 m per stance while the body moves 0.70 m. The foot is dragged forward through most of the stance.
</details>

<details><summary>O5</summary>

They drift apart and meet again, as P9 predicts: 0.70 m visible steps against 0.75 m sounded steps. Count about 14 visible steps between coincidences at a steady walk.
</details>

<details><summary>O6</summary>

Measured headless, mean of 20 rebuilds: `rebuild()` 0.36 ms (15 bones, 15 attachments, 17 capsules). `WalkCycle.sample()` 5.1 µs and `apply_pose()` 8.5 µs (means of 1000 calls). Posing the body costs under 0.1 % of a 16.7 ms frame. The rebuild could run every frame without notice; the boulder pile's sampling takes about 1800 times as long.
</details>

<details><summary>T1</summary>

0.7 m: twice the cadence, so the legs swing twice as fast for the same distance; 2.8 m: half. The stance travel of the ankle stays 0.70 m (it depends on the angles only) while the body moves 0.35 m or 1.40 m per stance. Measured mean / largest slip at amount 1, 3 m/s: 3.78 / 6.98 m/s at 0.7 m, 1.37 / 2.99 m/s at 1.4 m, 1.46 / 3.00 m/s at 2.8 m. At amount 0.5 (1.5 m/s): 0.68, 0.71 and 1.11 m/s mean. The default 1.4 m minimizes the slip at full speed, but not at half speed, where the swing is smaller (E1).
</details>

<details><summary>T2</summary>

No change: every rest basis is the identity, and I · B = B · I. The order matters once rest rotations are not the identity (E4).
</details>

<details><summary>T3</summary>

The knee bends while the foot carries the body and straightens while the foot swings forward: the foot drags through the ground during the swing and the body sinks on the supporting leg. The swing is the phase where the derivative of the hip angle is positive.
</details>

<details><summary>T4</summary>

The foot keeps the pitch of the shin. At the front of the swing the toes point up by the hip angle (24°); at the back of the stance they point down into the ground, and during the swing the bent knee turns the toes down by up to the knee angle.
</details>

<details><summary>T5</summary>

No capsule changes. Godot 4.6 returns `(0, 0, -1, 0)` for `Quaternion(Vector3.UP, Vector3.DOWN)`: a half turn about −z. A half turn about x and a half turn about z both send +y to −y; a capsule is symmetric about its axis, so the two meshes coincide. The branch documents the choice; a mesh without that symmetry (a foot with a heel, for example) would show the difference.
</details>

<details><summary>T6</summary>

At 1 per second the amount needs about 1 s to reach 63 % of the speed: the figure glides off with stiff legs before it starts to swing them, and keeps swinging after the capsule stops. At 30 per second the legs reach their full swing within a few ticks: an abrupt start, and every small change of stick deflection shows in the stride at once.
</details>
