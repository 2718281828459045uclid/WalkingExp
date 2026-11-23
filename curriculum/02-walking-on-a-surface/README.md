# Lesson 02. Walking on a surface

Lesson scene: `game/scenes/lessons/02_walking_on_a_surface.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). `game/scenes/sandbox.tscn` is unchanged and still runs as Lessons 00–01 describe.

## 1. Orientation

The capsule from Lesson 00 moves, but it knows little about what it stands on. This lesson answers four questions about walking on a surface:

1. How much stick produces how much speed? (response curve)
2. How does the velocity follow the stick from one physics tick to the next? (exponential smoothing)
3. Which contacts count as ground, and what happens on the others? (walkable angle, steps, snapping, sliding)
4. How steep is the ground in the direction the player looks? (directional derivative, used by the camera)

Goal served (`plan.md`): "a humanoid player that can walk ... with sensitive analog control"; "the way the character realistically traverses over complex geometry."

Files:

| File | Role |
|---|---|
| `game/src/input/stick_response.gd` | `StickResponse` Resource: radial deadzone, saturation, response curve. Math only. |
| `game/src/player/player.gd` | `Player`. New exported options (groups marked "Lesson 02"), ground states, sliding, camera look-ahead. Defaults keep Lesson 00 behavior. |
| `game/src/world/box_course.gd` | `BoxCourse`: base class for test geometry built from boxes. |
| `game/src/world/ramp_tower.gd` | `RampTower`: a platform with four ramps at 44°, 30°, 46°, 55°. |
| `game/src/world/step_row.gd` | `StepRow`: single steps of 5, 9, 12, 25 cm. |
| `game/src/lessons/walking_on_a_surface.gd` | Scene root. Extends `src/sandbox.gd`; adds the T and B keys and HUD lines. |
| `game/scenes/lessons/02_walking_on_a_surface.tscn` | Lesson scene: steep hill, ramp tower, step row, and a Player with the Lesson 02 options on. |
| `game/project.godot` | `run/main_scene` pointed to this scene while it was the newest lesson scene. New input actions `cycle_tick_rate` (T, D-pad up) and `toggle_blend_rule` (B, D-pad down). |
| `game/data/input/walk_stick_response.tres` | Deadzones and exponent used by the lesson scene. |
| `game/data/input/walk_stick_curve.tres` | An S-shaped `Curve` (slope 0 at both ends), unassigned, for Tweak T1. |
| `game/data/terrain/steep_height_field.tres` | A `HeightField` with one hill steeper than 45° and a flat plain. |
| `game/tests/test_02_*.gd` | Tests for the stick response, the blend factor, and ground contact. |

Reading: DDG §3.2.2 (directional derivatives as the pushforward of a vector) and §4.6.3 (df(u) = u · ∇f). Godot class reference, `CharacterBody3D` (the `floor_*` properties). Glenn Fiedler, "Fix Your Timestep!" (physics ticks). Robert Nystrom, *Game Programming Patterns*, chapter "Game Loop" (fixed and variable time steps). Josh Sutphin, "Doing Thumbstick Dead Zones Right" (radial deadzones). Full entries: `docs/references.md`.

Two Lesson 01 exercises remain open and this lesson's code does not solve them: E3 (slope readout on the HUD) and E4 (walking speed scaled by the directional derivative). The HUD in this lesson shows the ground state, not the slope angle.

## 2. Predict

Work these on paper before reading the code. Lesson 01 P3–P4 give the normal of a graph surface: n = (−h_x, 1, −h_z) / √(1 + ‖∇h‖²), and tan θ = ‖∇h‖.

- **P1.** At a point of the terrain, ∇h = (0.3, −0.4) (components along world x and world z). Compute the directional derivative D_u h = ∇h · u for u = (1, 0), u = (0.6, −0.8), u = (0.8, 0.6), and u = (−0.6, 0.8). Convert each to a slope angle along that direction. Which u gives the largest value, and which gives zero? State the general rule in terms of the angle between u and ∇h.
- **P2.** Godot treats a contact as floor when its normal lies within `floor_max_angle` (45°) of up. Write that condition in terms of ‖∇h‖. Does it depend on the direction the player walks? Can the walker traverse a 50° slope along a contour line, where D_u h = 0?
- **P3.** The lesson terrain is h(r) = 18 · exp(−r² / 200), with r the distance from the hill's center (A = 18 m, σ = 10 m). What is the steepest slope angle, and where? Between which two radii is the slope steeper than 45°? A walker approaches the center from outside. Where does it stop?
- **P4.** The lower end of the capsule is a hemisphere of radius r = 0.35 m. The capsule walks into a step of height s with a sharp edge. Find the angle between up and the contact normal (the line from the edge to the sphere's center) as a function of s. What is the tallest step whose contact still counts as floor at 45°?
- **P5.** Solve dv/dt = k (T − v) with v(0) = v₀ and constant target T. Show that one tick of length Δt maps v₀ to lerp(v₀, T, 1 − e^(−kΔt)). An explicit Euler step instead uses the blend factor kΔt. For k = 8 s⁻¹, what fraction of the gap to the target remains after 1/6 s with each rule, at 30 Hz and at 144 Hz? For which values of kΔt does the Euler rule overshoot the target, oscillate without settling, or diverge?
- **P6.** The lesson's stick response uses an inner deadzone of 0.12, an outer deadzone of 0.95, and exponent 1.6: the output magnitude is t^1.6 with t = (m − 0.12) / (0.95 − 0.12), clamped to [0, 1]. What output does a raw magnitude m = 0.5 give? Which raw magnitude gives half speed? Answer the same two questions for Lesson 00's mapping (inner 0.15, outer 1.0, exponent 1).
- **P7.** A body slides without friction from rest down a plane inclined at angle α, through a height drop h. What is its acceleration along the plane? Its speed at the bottom? Does the speed at the bottom depend on α?
- **P8.** The walker pushes with a horizontal velocity of v = 3 m/s straight up a ramp of angle α. `move_and_slide()` removes the part of the motion that points into the ramp and keeps the part along it. What speed along the surface and what horizontal speed result? Evaluate for α = 30°.

## 3. Read

### 3.1 `stick_response.gd`

Read the diagram in the header comment, then `apply()` and `shape()`. The mapping acts on the magnitude of the stick vector and leaves its direction alone. Why is a radial deadzone (a circle) better than one deadzone per axis (a square)? Consider a stick pushed a little off the forward direction.

`shape()` first rescales [inner, outer] to [0, 1] with `inverse_lerp`, then applies either the power law or a `Curve`. The header claims that the default values reproduce Lesson 00. Find the test that checks the claim, and read how it feeds stick positions to `Input` without a gamepad.

### 3.2 `player.gd`

The Lesson 00 code is still present. Lesson 02 added exported properties in groups marked "Lesson 02", and six functions: `blend_factor()`, `get_ground_state()`, `_read_stick()`, `_update_ground_state()`, `_update_look_ahead()`, `_ground_height_below()`. Walk through `_physics_process()` in order:

1. `_read_stick()` reads the raw stick with `Input.get_vector(..., 0.0)` (deadzone off). With `stick_response` empty it falls back to the Lesson 00 call; otherwise the resource shapes the raw vector. Both vectors are stored for the HUD.
2. `blend_factor()` is the line from Lesson 00, `1 - exp(-k * dt)`, moved into a static function so that a test can call it, with the `LINEAR` rule beside it for comparison.
3. The `sliding` flag skips the blend on steep ground. Read the Q/A comment above it.
4. `move_and_slide()`, then `_update_ground_state()`, which sorts the contact into `FLOOR`, `STEEP`, or `AIR`. What is the role of `STEEP_NORMAL_MIN_Y`?
5. On steep ground, `velocity.slide(n)` keeps the tangential part of the velocity: v − (v · n) n. Compare with P7.
6. `_update_look_ahead()` casts two rays down (at the player and `look_ahead_distance` ahead along the camera's direction), forms the secant (h(p + L u) − h(p)) / L, and tilts the spring arm by `look_ahead_gain · atan(secant)`. Compare the secant with D_u h from P1. Which quantity does the secant approach as L shrinks? Lesson 01 O4 met the same trade-off for the finite-difference step.

### 3.3 The `floor_*` properties of `CharacterBody3D`

`move_and_slide()` reads these properties. Select **Player** in the lesson scene and find them in the Inspector under **Floor**; `max_slides` sits at the top level of the `CharacterBody3D` section, `safe_margin` under **Collision**. Engine defaults, printed from a `CharacterBody3D.new()` in Godot 4.6.2:

| Property | Default | Meaning |
|---|---|---|
| `floor_max_angle` | 45° | Steepest contact that counts as floor |
| `floor_snap_length` | 0.1 m (`player.tscn` sets 0.4 m) | How far down the body may be pulled to stay on the floor |
| `floor_stop_on_slope` | true | No sliding down walkable slopes when standing still |
| `floor_constant_speed` | false | Speed along the surface follows the slope (P8) |
| `floor_block_on_wall` | true | Steep contacts cannot be walked up |
| `max_slides` | 6 | Collisions resolved per `move_and_slide()` call |
| `safe_margin` | 0.001 m | Gap kept between the capsule and other shapes |

### 3.4 `box_course.gd`, `ramp_tower.gd`, `step_row.gd`

`BoxCourse` follows the pattern of `terrain.gd`: generated nodes are internal children and never saved; collision exists in the running game alone. `RampTower._add_ramp()` builds a ramp on the +z side and rotates it into place. Check the claim in its Q/A comment that `Basis(Vector3.RIGHT, a)` sends the box's local +y to n = (0, cos a, sin a).

### 3.5 `walking_on_a_surface.gd` and the scene

The scene has the same node names as `sandbox.tscn`, so the script can extend `src/sandbox.gd` and reuse its spawn placement, debug keys, and HUD. It overrides `_update_hud()` and calls `super()` first. The HUD label is anchored to the bottom-left corner of the window (`sandbox.tscn` keeps it at the top left), so that the longer text stays clear of the ramp and step labels in the starting view. The scene's **Player** node overrides three properties of `player.tscn`: **Stick Response**, **Steep Slide**, **Look Ahead Distance**. Find them in the `.tscn` file.

## 4. Run and observe

Open `scenes/lessons/02_walking_on_a_surface.tscn` and press F6. The hill is ahead; the ramp tower is to the front left, the step row to the front right. The HUD shows the ground state, the speed, and the stick before and after shaping. **T** (D-pad up) cycles the physics tick rate through 30, 60, and 144 Hz. **B** (D-pad down) switches the blend rule. Tab and N work as in the sandbox. Several experiments change **Player** properties while the game runs: in the Scene dock choose **Remote**, select `WalkingOnASurface/Player`, and edit in the Inspector (Lesson 00 O3).

- **O1.** Push the left stick from center to the rim with a light hand. Read `stick: raw -> shaped`. At which raw value does the shaped value first read above zero? At which raw value does it reach 1? Then clear **Stick Response** in the Remote Inspector and repeat. Which mapping makes a speed of 0.3 m/s easier to hold? Compare with P6.
- **O2.** Press T until the HUD shows 30 Hz. Press B for the linear rule. In the Remote Inspector set **Responsiveness** to 45, then 60, then 70, and push the stick forward each time. Describe the speed readout and the capsule's motion for each value. Compare with P5. (At 70 the capsule leaves; stop and restart the scene.)
- **O3.** Walk up the 30° ramp and the 44° ramp. Then walk into the 46° and 55° ramps. Press Tab twice for the slope view. What does the 45° limit look like in that view, and why do the 44° and 46° ramps look alike there?
- **O4.** From the platform, walk off the 55° side at full stick. Watch the ground state. Climb back and walk off the same side with a touch of the stick; release the stick when the ground state reads `steep`. What differs? Note the speed readout when the capsule reaches the ground, and compare it with P7 (the platform is 3 m high).
- **O5.** Walk across the step row. Which steps can the capsule climb? Compare with P4.
- **O6.** Walk straight at the top of the hill. Where do you stop? Compare with P3. Then try to walk around the hill on the steep band.
- **O7.** In the Remote Inspector set **Floor → Snap Length** to 0 and walk from the platform down the 30° ramp, watching the ground state. Set it back to 0.4 and repeat. Then step down from the 25 cm step with snapping on. Does the ground state ever read `air`?
- **O8.** Walk up the 30° ramp and read the speed, then walk down it. Compare with P8. Then enable **Floor → Constant Speed** and repeat.
- **O9.** Walk toward the 30° ramp from a distance and watch the camera. When does it start to tilt? How far does it tilt on the ramp, and what does it do near the top and on the platform?

## 5. Tweak

Restore each change after the observation.

- **T1.** Open `data/input/walk_stick_response.tres`. Set **Exponent** to 1, then to 3, and run each. Which value makes 0.3 m/s easiest to hold, and what does it cost at the other end of the stick? Then assign `data/input/walk_stick_curve.tres` to **Curve**. Open the curve in the Inspector's curve editor; what does the S shape do near the rim compared with the power law?
- **T2.** Set the scene Player's **Responsiveness** to 2 and repeat the slow walk-off from O4. Release the stick when the ground state reads `steep`. Predict the run-out distance on the ground from the horizontal speed at the bottom of the ramp and the decay rate k. (The integral of v e^(−kt) over t ≥ 0.)
- **T3.** Set the scene Player's **Floor → Max Angle** to 50°. Which ramps and which steps are climbable now? Recompute P4 for 50°.
- **T4.** Turn off **Steep Slide** in the Remote Inspector and repeat the slow walk-off from O4, releasing the stick when the ground state reads `steep`. Does the capsule still slide? What does the speed readout show at the bottom, and what happens to the speed on landing? Read the Q/A comments in `_physics_process()` again.
- **T5.** Set **Look Ahead Distance** to 0.5, then to 12, and walk up the hill and over the ramp tower. Which setting reacts to the ramp edges, and which anticipates the hill?

## 6. Exercises

- **E1 ★ Implicit Euler.** Add a third rule to `BlendRule`: the backward Euler step v₁ = v₀ + kΔt (T − v₁), solved for v₁. Write its blend factor. Show on paper that it never overshoots for any kΔt > 0. Is it frame-rate independent? Answer with a measurement in a SceneTree script of your own, kept in the lesson folder beside `notes.md` and run with `-s` and its absolute path (`tools/render_check.sh` runs `tools/godot/capture.gd` the same way); `test_02_smoothing.gd` shows the structure. `game/tests/` holds tests of the starter code, not exercise solutions.
- **E2 ★ Rest noise.** Log `stick_raw.length()` for 10 s with the left stick released, then for 10 s while holding it as still as you can at a light deflection. Report the largest magnitude at rest and the spread while held. Choose `inner_deadzone` from the data and justify the number.
- **E3 ★ Steering while sliding.** On steep ground the stick has no effect. Let it steer across the slope and downhill, never uphill. Decompose the shaped wish vector into the downhill direction within the surface (the tangential part of gravity, normalized) and the direction perpendicular to it in the surface, and discard a negative downhill component. Pick an acceleration and justify it.
- **E4 ★★ Step-up.** The capsule climbs steps up to about 12 cm (O5). Write a step-up rule that lets it climb 25 cm steps and nothing taller: when a move is blocked by a steep contact, test a move up by the step height, then forward, then down (`test_move()` or `move_and_collide(..., true)`). Report which steps of the step row it climbs and what happens at the foot of the 46° ramp.
- **E5 ★★ Stepping down.** O7 shows an airborne phase when the capsule steps off the 25 cm step, even with snapping on. Find out why the snap does not catch it (watch the contact normal at the step edge on the last ticks of `FLOOR`). Then remove the airborne phase, for example with a downward shape cast after leaving the floor. Count airborne ticks before and after.
- **E6 ★★★ Direction-dependent walkability.** People cross slopes along contour lines that they cannot climb straight up (P2). Replace the single walkable angle with a rule that depends on the slope along the direction of travel, D_u h, and on the cross slope. You will need your own floor classification, since `floor_max_angle` is one number. Recover ∇h from the contact normal and derive the slope along and across the direction of travel. Describe the rule as a region in the plane of (along-slope, cross-slope) before coding it.
- **E7 ★★★ Tick-rate study.** Repeat the slow walk-off from O4 at 30, 60, and 144 Hz (T key) with a scripted input, and record the speed at the bottom and the time on the ramp. Does gravity integrate the same way at every rate? Identify the integration scheme `player.gd` uses for gravity and estimate its error per tick for a body on a 55° incline.

## 7. Reflect

- **R1.** The blend y ← y + b (x − y) is a one-pole low-pass filter, the same structure as `OnePole` in SuperCollider. With b = 1 − e^(−kΔt), what is its cutoff frequency for k = 8 s⁻¹? What does the walker do with a stick wiggled at 0.5 Hz and at 5 Hz? Lesson 14 builds on one-pole filters and critically damped springs for stance control.
- **R2.** The capsule climbs small steps because its lower end is round. In Lesson 12, feet find the ground with raycasts and legs bend with IK. Which parts of this lesson's ground logic belong to the capsule, and which will belong to the feet?
- **R3.** Lesson 05 sends footstep events to SuperCollider. Which ground-state transitions (`FLOOR` → `AIR`, `AIR` → `FLOOR`, `FLOOR` → `STEEP`) are sound events, and which numbers would you send with each?
- **R4.** `_ground_height_below()` casts rays from above. Phase 3 adds boulders that overhang. What does the look-ahead camera report under an overhang, and how would you fix it?
- **R5.** One angle separates walking from sliding here. Lessons 15 and 16 add climbing and scrambling on steep faces. Where should the decision between walking, scrambling, and climbing live, and which surface quantities should it read?

## 8. Answers

<details><summary>P1</summary>

‖∇h‖ = 0.5.

| u | D_u h | Slope angle |
|---|---|---|
| (1, 0) | 0.3 | 16.7° uphill |
| (0.6, −0.8) | 0.18 + 0.32 = 0.5 | 26.6° uphill |
| (0.8, 0.6) | 0.24 − 0.24 = 0 | 0° |
| (−0.6, 0.8) | −0.5 | 26.6° downhill |

D_u h = ‖∇h‖ cos φ, with φ the angle between u and ∇h. The largest value, ‖∇h‖, is along ∇h (u = ∇h / ‖∇h‖); zero is along the contour lines (φ = 90°); the most negative is along −∇h, the direction of steepest descent. DDG §4.6.3 writes this as df(u) = u · ∇f.
</details>

<details><summary>P2</summary>

cos θ = n · up = 1 / √(1 + ‖∇h‖²) ≥ cos 45°, which is ‖∇h‖ ≤ tan 45° = 1. The condition involves ∇h alone, not the direction of travel: the normal belongs to the point, not to the walker. On a 50° slope ‖∇h‖ = tan 50° ≈ 1.19 > 1 everywhere, so Godot treats it as a wall along every direction, contour lines included. Hikers cross such slopes along contour lines, and switchbacks exist because a path in direction u has grade D_u h = ‖∇h‖ cos φ, which the path's direction controls. E6 builds that rule.
</details>

<details><summary>P3</summary>

h′(r) = −(A r / σ²) exp(−r² / 2σ²), steepest at r = σ = 10 m (Lesson 01 P6), with slope (A / σ) e^(−1/2) = 1.8 × 0.607 = 1.09, so 47.5°.

Steeper than 45° where (A / σ)(r / σ) exp(−r² / 2σ²) > 1, that is (r/σ) exp(−(r/σ)² / 2) > 0.556. Solved by bisection: 7.2 m < r < 13.1 m. The summit plateau (r < 7.2 m) is walkable but enclosed by the steep band.

The walker stops at the outer edge of the band. Measured: its origin (the feet) stops at r = 13.25 m, height 7.63 m. The capsule touches the hill uphill of its origin, by about 0.35 sin 45° ≈ 0.25 m, so the contact sits near r = 13.0 m, where the slope is 45.2°. Godot accepts floor normals up to 0.01 rad (0.57°) beyond `floor_max_angle`: on plane ramps the capsule climbs 45.5° and is stopped at 45.6° (measured).
</details>

<details><summary>P4</summary>

The sphere's center is at height r above the ground. Touching the edge at height s, the vector from the edge to the center has vertical component r − s and length r, so cos φ = (r − s) / r. The contact is floor while φ ≤ 45°: s ≤ r (1 − cos 45°) = 0.35 × 0.293 = 0.1025 m.

The measured limit is higher. With the step row's boxes the capsule climbs 0.118 m and is stopped at 0.119 m. Two effects add up:

1. Jolt rounds the edges of box shapes by a convex radius of up to `Shape3D.margin` (0.04 m by default). The capsule then touches a cylinder of radius ρ instead of a sharp edge, which acts like a sphere of radius r + ρ against a sharp edge. Measured with the margin set to 0: limit between 0.1064 and 0.1065 m; with the default margin: 0.118 m.
2. The angular tolerance from P3 and the contact offsets of the solver. With margin 0 the measured limit corresponds to a contact angle of 45.9°, not 45°.

Measured limits at other angles (default margin): 0.055 m at 30°, 0.198 m at 60°.
</details>

<details><summary>P5</summary>

Separate variables: d(T − v) / (T − v) = −k dt, so T − v(t) = (T − v₀) e^(−kt) and v(t) = T + (v₀ − T) e^(−kt). After one tick,

v₁ = T + (v₀ − T) e^(−kΔt) = v₀ + (T − v₀)(1 − e^(−kΔt)) = lerp(v₀, T, 1 − e^(−kΔt)).

After n ticks the remaining gap is e^(−k n Δt) = e^(−kt), whatever Δt is. The Euler rule leaves (1 − kΔt)^n.

Remaining fraction after 1/6 s, k = 8 (measured with `Player.blend_factor()`):

| Tick rate | Exponential | Linear (Euler) |
|---|---|---|
| exact solution | 0.2636 | — |
| 30 Hz | 0.2636 | 0.2121 |
| 60 Hz | 0.2636 | 0.2391 |
| 144 Hz | 0.2636 | 0.2537 |
| 240 Hz | 0.2636 | 0.2577 |

The Euler rule approaches faster at low tick rates: its effective decay rate is −ln(1 − kΔt) / Δt, 9.30 s⁻¹ at 30 Hz and 8.23 s⁻¹ at 144 Hz instead of 8.

The factor (1 − kΔt) is negative for kΔt > 1 (overshoot with alternating sign), equal to −1 at kΔt = 2 (oscillation without decay), and below −1 for kΔt > 2 (divergence). At 30 Hz these thresholds are k = 30, 60, and above 60.
</details>

<details><summary>P6</summary>

Walk response: t = (0.5 − 0.12) / 0.83 = 0.458, t^1.6 = 0.287, so 0.86 m/s. Half speed: t = 0.5^(1/1.6) = 0.648, m = 0.12 + 0.83 × 0.648 = 0.658.

Lesson 00: (0.5 − 0.15) / 0.85 = 0.412, so 1.24 m/s. Half speed at m = 0.15 + 0.85 × 0.5 = 0.575.

The exponent spends more of the stick's travel on low speeds. The slope of output against raw magnitude is d(t^1.6)/dm = 1.6 t^0.6 / 0.83 for the walk response: 0 at the deadzone edge (t = 0), 0.17 at m = 0.135, 1.86 at m = 0.9. Lesson 00's slope is 1 / 0.85 = 1.18 everywhere. Finite differences of `StickResponse.shape()` give the same values.
</details>

<details><summary>P7</summary>

Gravity g = (0, −g, 0) splits into a part along the normal and a tangential part of magnitude g sin α, so the acceleration along the plane is g sin α. Energy conservation gives the speed at the bottom: ½ v² = g h, v = √(2 g h), independent of α. The angle changes how long the slide takes, not the final speed.

For the ramp tower (platform 3 m): the capsule enters the steep state about 0.2 m below the platform, at y = 2.77 to 2.80 m in measured runs (the value depends on where the ticks fall at the edge). √(2 g h) gives 7.36 to 7.40 m/s for these heights. Measured speed at the bottom: 7.38 m/s.
</details>

<details><summary>P8</summary>

With the ramp rising toward −z, n = (0, cos α, sin α) and the pushed velocity is (0, 0, −v). v · n = −v sin α, and the tangential part is (0, v sin α cos α, −v cos² α). Speed along the surface: v cos α; horizontal speed: v cos² α. For α = 30°: 2.60 m/s along the surface, 2.25 m/s horizontal. Measured: 2.598 and 2.250.
</details>

<details><summary>O1</summary>

The deadzone of the walk response ends at a raw magnitude of 0.12, but the HUD first shows a shaped value above zero at about 0.127. The output t^1.6 starts with zero slope (P6) and stays below 0.0005, half the display step of 0.001 and the smallest value that three decimals round up to 0.001, until t = 0.0005^(1/1.6) = 0.0087, that is m = 0.12 + 0.83 × 0.0087 = 0.127. The shaped value reaches 1.000 at raw 0.950. With **Stick Response** cleared (Lesson 00 mapping) the shaped value leaves zero at 0.150 and reaches 1.000 at 1.000, along a straight line. A readout with a fixed number of decimals does not show where a power-law response leaves zero; the derivation in P6 locates the deadzone edge. Table measured with `StickResponse.shape()`:

| Raw | Lesson 00 | Walk response | `walk_stick_curve.tres` |
|---|---|---|---|
| 0.2 | 0.059 | 0.024 | 0.011 |
| 0.3 | 0.176 | 0.087 | 0.056 |
| 0.5 | 0.412 | 0.287 | 0.252 |
| 0.7 | 0.647 | 0.564 | 0.631 |
| 0.9 | 0.882 | 0.905 | 0.980 |

0.3 m/s is an output of 0.1. Lesson 00 reaches it at raw 0.235, the walk response at 0.32 (0.12 + 0.83 × 0.1^(1/1.6)). Between zero and 0.3 m/s the walk response uses 0.20 of the stick's travel, Lesson 00 uses 0.085.
</details>

<details><summary>O2</summary>

Measured in the game at 30 Hz with the linear rule (horizontal speed on successive ticks, target 3 m/s):

| Responsiveness | kΔt | Speeds on ticks 1–6 (m/s) | Behavior |
|---|---|---|---|
| 45 | 1.5 | 4.50, 2.25, 3.38, 2.81, 3.09, 2.95 | Overshoots, then settles with alternating sign |
| 60 | 2.0 | 6.00, 0.00, 6.00, 0.00, 6.00, 0.00 | Oscillates without decay; the capsule stutters |
| 70 | 2.33 | 7.00, 2.33, 10.1, 6.48, 15.6, 13.9 | Diverges; after 1 s the speed is about 17,000 m/s |

With the exponential rule all three settle without overshoot, since 1 − e^(−kΔt) < 1 for every k. In normal use (k = 8) the two rules differ by a few percent (P5), too little to see on the HUD; measured speed after 1/6 s from rest: 2.21 m/s at 30, 60, and 144 Hz with the exponential rule; 2.36, 2.28, and 2.24 m/s with the linear rule.
</details>

<details><summary>O3</summary>

The 30° and 44° ramps lead to the platform; the capsule stops at the foot of the 46° and 55° ramps (measured). The slope view maps 0° to blue and 45° to red, and clamps above 45°. A 44° ramp is at 98 % of the scale, so both ramps look red. The limit is ‖∇h‖ = 1 (P2), and the view shows ‖∇h‖ through the slope angle.
</details>

<details><summary>O4</summary>

At full stick (3 m/s) the capsule leaves the platform edge and flies: the ground state reads `air`, and it lands on the flat ground beyond the foot of the 55° ramp without touching it. A ballistic path from the edge falls ½ g t² while the ramp falls 3 tan 55° · t; the parabola stays above the ramp until t ≈ 0.87 s, by which time the capsule has passed the ramp's foot. Off the 46° side at full stick the capsule first touches the ramp 0.8 to 0.9 m above the ground (measured from several start points on the platform; the value depends on where the last tick on the platform falls).

With a light touch (0.5 m/s) the capsule rolls over the edge onto the ramp. The state goes from `floor` to `air` while the capsule drops about 0.1 m off the edge, then to `steep` about 0.2 m below the platform top, and the capsule slides. Measured: 0.75 s on the ramp, 7.38 m/s at the bottom, close to √(2 g h) for the drop of about 2.8 m (P7). With the stick released, the horizontal part of the velocity, 4.23 m/s, carries the capsule 0.49 m across the ground before the smoothing stops it. With the stick held, the smoothing pulls the horizontal speed toward the stick target of 0.5 m/s instead of zero, and the capsule keeps walking.
</details>

<details><summary>O5</summary>

The 5 cm and 9 cm steps are climbed; the 12 cm and 25 cm steps stop the capsule. P4 predicts 10.25 cm for a sharp edge; the measured limit is 11.8 cm (see the P4 answer for the cause).
</details>

<details><summary>O6</summary>

The capsule stops with its feet at r = 13.25 m, 7.63 m up the hill, against the predicted 45° radius of 13.1 m (P3). Along the steep band the capsule cannot stand at all: every contact there is steeper than 45°, whatever the direction of travel (P2).
</details>

<details><summary>O7</summary>

Measured over a 3 s run at 3 m/s from the platform center down the 30° ramp:

| Snap length | Ticks not on the floor (of 180) |
|---|---|
| 0 | 104 |
| 0.1 m | 0 |
| 0.4 m | 0 |

Without snapping the capsule hops: each landing sets the vertical velocity to zero, the next horizontal step carries it off the descending surface, and gravity needs several ticks to bring it back. Snapping pulls it down onto the floor at the end of each move.

Stepping down from the 25 cm step, the state reads `air` for 11 ticks (0.18 s) with any snap length from 0.1 to 0.4 m, and for 14 ticks with 0. The capsule falls the last 0.17 m. Snapping does not prevent it; E5 asks why and how to fix it.
</details>

<details><summary>O8</summary>

Measured on the 30° ramp at full stick:

| | Along the surface | Horizontal | Vertical |
|---|---|---|---|
| Up, constant speed off | 2.60 m/s | 2.25 m/s | 1.30 m/s |
| Down, constant speed off | 3.47 m/s | 3.00 m/s | −1.73 m/s |
| Up, constant speed on | 3.00 m/s | 2.60 m/s | 1.50 m/s |
| Down, constant speed on | 3.00 m/s | 2.60 m/s | −1.50 m/s |

Uphill matches P8. Downhill the horizontal velocity points away from the surface, so nothing is removed: the capsule moves at 3 m/s in the horizontal plane and the snap pulls it down, giving v / cos α = 3.46 m/s along the surface. With **Constant Speed** on, Godot rescales the motion to 3 m/s along the surface in both directions.
</details>

<details><summary>O9</summary>

The camera starts to tilt when the point 4 m ahead reaches the foot of the ramp, while the capsule is still on flat ground (measured: 3.85 m before the foot).

The target pitch is `look_ahead_gain` × atan(secant). The secant equals tan 30° only while both samples lie on the ramp, and then the target is 0.5 × 30° = 15°. The ramp's horizontal run is 3 / tan 30° = 5.20 m, so with L = 4 m both samples lie on it for the first 1.20 m of horizontal travel past the foot. After that the far sample lies on the platform and the secant shrinks. The camera follows the target at `look_ahead_responsiveness` = 3 s⁻¹ (time constant 1/3 s) and lags behind it.

Measured in the lesson scene: the pitch peaks at 14.4° about 1.3 m past the foot (0.8 m above the ground), falls to 3.3° at the top edge, and turns negative on the platform, where the far sample lands on the 55° ramp beyond (−10.6° at the platform center). On a ramp longer than L, walked long enough, the pitch settles at 15°.
</details>

<details><summary>T1</summary>

The output for a raw magnitude m inside [inner, outer] is t^p. A larger exponent p flattens the start (more travel for low speeds) and steepens the end: the slope at the rim is p / (outer − inner). With p = 3 the walk response reaches 0.1 at t = 0.46 and has a slope of 3.6 near the rim, so the last part of the stick's travel changes the speed fast. The S curve in `walk_stick_curve.tres` has slope 0 at both ends: it is 1.2 t² on [0, 0.5], and its tangent at t = 1 is 0. Its steepest point, slope 1.88 in t, lies near t = 0.69. Near the rim it changes the speed little: 0.946 at t = 0.9 and 0.986 at t = 0.95, where t^1.6 gives 0.845 and 0.921 with slope 1.5 to 1.6. A stick held near the rim then gives close to full speed even when the deflection varies by a few percent; the change of speed is concentrated in the middle of the travel (measured with `Curve.sample()`).
</details>

<details><summary>T2</summary>

After landing, the horizontal velocity decays as v₀ e^(−kt), and the distance covered is ∫ v₀ e^(−kt) dt = v₀ / k. Measured with a horizontal speed of 4.23 m/s at the bottom: 0.49 m at k = 8 (v₀ / k = 0.53 m) and 2.08 m at k = 2 (v₀ / k = 2.12 m). The discrete sum differs from the integral by part of one tick's motion.
</details>

<details><summary>T3</summary>

At 50° the 46° ramp is climbed and the 55° ramp is not (measured). For steps, P4 with 50° gives r (1 − cos 50°) = 0.125 m for a sharp edge. Measured with the step boxes at 50°: 12 cm and 13 cm steps are climbed, the 25 cm step is not. In the step row, the 12 cm step becomes climbable.
</details>

<details><summary>T4</summary>

The capsule still slides, at the same rate along the surface. Without the `velocity.slide(n)` line, gravity keeps adding vertical velocity and `move_and_slide()` moves the capsule by the tangential part of that motion, but the stored velocity stays vertical. Measured at the bottom: the HUD reads 8.98 m/s with 0 m/s horizontal, while the speed along the surface is 8.98 × sin 55° = 7.36 m/s. On landing the vertical velocity is removed and the capsule stops dead; there is no run-out. Without `steep_slide`, the smoothing also pulls any horizontal velocity toward the stick target on steep ground: with the stick held at 0.5 m/s the measured values are 8.67 m/s at the bottom with 0.50 m/s horizontal, and the capsule keeps walking after landing.
</details>

<details><summary>T5</summary>

With 0.5 m the secant is close to the local derivative. The target pitch stays at zero until the capsule is half a meter from the foot of the ramp and then rises to 15° within half a meter of travel; the camera follows that step at the rate set by `look_ahead_responsiveness`. The same happens in reverse at the top edge.

With 12 m the baseline is longer than the ramp tower's features: the 30° ramp has a horizontal run of 5.20 m and the platform is 4 m wide, so the two samples never lie on the ramp together and the target never reaches 15°. The target starts to rise when the far sample reaches the foot, 12 m before the ramp. Its largest value, 0.5 × atan(3/12) = 7.0°, holds while the far sample is on the platform. Once the far sample has passed the platform and the 55° ramp beyond it, it reads the ground on the far side, and the secant turns negative while the capsule climbs: the target falls from zero at the foot to −7.0° at the top edge and stays there on the platform, and the camera tilts down.

Measured in the lesson scene, walking at full stick toward the 30° ramp as in O9 ("leaves zero" is the first reading above 0.05°):

| Look Ahead Distance | Pitch leaves zero | Largest pitch before the top edge | Pitch at the platform center |
|---|---|---|---|
| 0.5 m | 0.45 m before the foot | 15.0°, 0.5 m before the top edge | 1.5° |
| 12 m | 11.7 m before the foot | 7.0°, 2.8 m before the foot | −6.9° |

With 12 m the pitch passes zero 0.8 m past the foot, on the lower part of the ramp.

On the hill the slope changes over tens of meters, and both settings follow it; the long baseline leads. Walking from the spawn point toward the hill, at z = 30 m (0.2 m above the plain) the pitch is 6.8° with 12 m and 1.5° with 0.5 m. Where the capsule stops (r = 13.25 m, O6) the pitch settles at 22.5° with 0.5 m, half of the local 45° slope, and at 20.4° with 12 m, where the secant spans the steeper band and the flatter top. The baseline plays the role of the finite-difference step in Lesson 01 O4: a long one averages, a short one follows detail.
</details>
