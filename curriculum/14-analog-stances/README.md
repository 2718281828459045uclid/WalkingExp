# Lesson 14. Analog stances

Lesson scene: `game/scenes/lessons/14_analog_stances.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–13 are unchanged; the Lesson 13 scene has no weight shift, no crouch, and its player has no `StickResponse`.

## 1. Orientation

Lesson 13 measured whether the body could stand where it stands, and moved it only when a key pushed it. This lesson gives the player control of the body's weight through analog input. It answers four questions:

1. What does a controller report, before any processing? (raw axes, the trigger axes `JOY_AXIS_TRIGGER_LEFT` and `JOY_AXIS_TRIGGER_RIGHT`, the action deadzone)
2. How does a raw value become a useful one? (radial and axial deadzones, saturation, response curves stored as `Curve` resources)
3. How does a stepped input become motion a body could make? (a one-pole low-pass filter, a critically damped spring, each solved exactly over one tick)
4. Does the answer depend on the tick rate? (60 against 120 physics ticks per second; explicit Euler against the exact step)

The method: a new node, `StanceController`, reads the two triggers, shapes each with a `TriggerResponse` (a deadzone, a saturation value and a `Curve`), and turns their difference into a sideways shift of the rig. The shaped left stick of Lesson 02 adds a small forward lean. Key 4 (gamepad: D-pad up) toggles a crouched stance that lowers the rig by 0.25 m. Both targets pass through one of four smoothing rules before they reach the rig. The node runs between `BalanceMonitor` and `Player` in each tick: the monitor sets the rig to its rest position plus the push sway of Lesson 13, this node adds the shift and the crouch, and the IK of Lesson 12 bends the legs so that the planted feet stay where they are. The balance lines of Lesson 13 show the result: the center of mass moves over the support polygon, and a full shift to one side leaves it. Keys 5 and 6 are the keyboard fallback for the triggers. Key 8 swaps the walk stick's deadzone between radial (Lesson 02) and axial. Key 9 switches the physics between 60 and 120 ticks per second.

Goal served (`plan.md`): "embodied movement" and "a humanoid player that can walk, crawl, climb, and balance". The weight shift is the first input that moves the body without moving the capsule. Lesson 15 (climbing) can reuse the filters for reaching hands.

Files:

| File | Role |
|---|---|
| `game/src/input/trigger_response.gd` | `TriggerResponse` Resource: inner deadzone, outer deadzone, optional `Curve`; `apply(raw)`. |
| `game/src/input/axial_stick_response.gd` | `AxialStickResponse` (extends `StickResponse`, Lesson 02): one deadzone per axis; `apply()` only. |
| `game/src/input/one_pole_filter.gd` | `OnePoleFilter` (RefCounted): y += (1 − e^(−dt/τ)) (x − y) on a `Vector2`. |
| `game/src/input/critical_spring.gd` | `CriticalSpring` (RefCounted): exact critically damped step, and `step_euler()` for comparison. |
| `game/src/body/stance_controller.gd` | `StanceController` (Node, priority −1): triggers and stick → weight shift; stance; smoothing; adds both to the rig's position. |
| `game/data/input/trigger_curve.tres` | A `Curve` from (0, 0) to (1, 1), slope 0.5 at the start and 1.5 at the end. |
| `game/data/input/trigger_response.tres` | `TriggerResponse`: inner 0.05, outer 0.95, `trigger_curve.tres`. |
| `game/data/input/walk_stick_axial.tres` | `AxialStickResponse` with the numbers of `walk_stick_response.tres` (0.12, 0.95, exponent 1.6). |
| `game/src/lessons/analog_stances.gd` | Scene root. Extends `balance.gd` (Lesson 13); keys 4–9; five lines in `HUD/RockLabel`. |
| `game/scenes/lessons/14_analog_stances.tscn` | The Lesson 13 scene plus the node `Stance`; the player has `walk_stick_response.tres` again. |
| `game/project.godot` | Input actions `toggle_crouch` (4, D-pad up), `shift_weight_left` (5, left trigger), `shift_weight_right` (6, right trigger), `cycle_stance_smoothing` (7), `toggle_axial_deadzone` (8), `cycle_stance_tick_rate` (9); `run/main_scene`. |
| `game/tests/test_14_*.gd` | Trigger and stick shaping, both filters at four tick rates, the Euler stability limit; the scene, the order of nodes, the keys. |
| `docs/decisions/0014-analog-weight-shift.md` | Why the shift moves the rig, why the spring is solved exactly, why the triggers are actions with deadzone 0. |

Only the trigger actions and `toggle_crouch` have gamepad bindings. Every other gamepad button is bound to an earlier lesson, except Start and Guide. D-pad up belongs to Lesson 02's `cycle_tick_rate` (T), which only the Lesson 02 scene reads; this lesson binds D-pad up to `toggle_crouch` as well, and no scene reads both actions. Key 9 is a separate action, `cycle_stance_tick_rate`, so that T and D-pad up do not change the tick rate in this scene.

Reading:

- Josh Sutphin, "Doing Thumbstick Dead Zones Right" (radial against axial deadzones; Lesson 02 cited it for the radial one).
- Godot documentation, "Controllers, gamepads, and joysticks" (tutorials/inputs/controllers_gamepads_joysticks): action deadzones, `Input.get_action_raw_strength()`, trigger axes. Class reference `Curve` (`sample()`, point tangents).
- Glenn Fiedler, "Fix Your Timestep!" (Lesson 02): the fixed tick and why its rate should not change a simulation's result.
- Julius O. Smith III, *Introduction to Digital Filters with Audio Applications*, chapter "Elementary Filter Sections", the one-pole section. The same filter is `OnePole` and `Lag` in SuperCollider.
- Keenan Crane, *Discrete Differential Geometry: An Applied Introduction* (`discreteDifferentialGeometry.pdf`), section 6.6 "Implicit Mean Curvature Flow", pp. 114–116: the time derivative replaced by a difference over a step h, forward Euler (evaluated from the known state, "not numerically stable", small h only) against backward Euler (a linear system, stable). The text applies it to a surface; section 2 below applies the same comparison to a spring.

## 2. Predict

Notation: the stick vector has x to the right and y forward (Godot's `Input.get_vector()` returns forward as −y; the lesson writes forward as +y where no code is involved). The walk response of Lesson 02: inner deadzone 0.12, outer 0.95, exponent 1.6, so a raw magnitude m gives t^1.6 with t = (m − 0.12)/0.83 clamped to [0, 1].

- **P1.** Radial against axial. A stick is held at magnitude 0.5, 10° to the right of forward. The radial deadzone shapes the magnitude and keeps the direction. The axial deadzone shapes x and y separately with the same function. Compute both outputs. Within which angle of the forward axis does the axial deadzone return straight forward, at magnitude 0.5 and at 1.0?
- **P2.** The diagonal. The stick is pushed fully into the 45° direction (raw (0.707, 0.707)). What length does the axial response return? What length does the radial one return? Which of the two walks slower on the diagonal, and by how much?
- **P3.** The trigger curve. `trigger_curve.tres` has two points, (0, 0) with right tangent 0.5 and (1, 1) with left tangent 1.5. A Godot `Curve` between two points is a cubic with these end values and end slopes (cubic Hermite). Write the cubic, and compute the shaped output for a raw trigger of 0.5 with inner 0.05 and outer 0.95. What does the curve do to the first quarter of the trigger's travel?
- **P4.** One pole. The filter dy/dt = (x − y)/τ starts at y = 0 and receives a step x = 1. Solve it. With τ = 0.12 s, what is y after 0.1 s? Over one tick dt, show that the exact update is y ← y + a (x − y) with a = 1 − e^(−dt/τ). At 60 Hz, compare a with dt/τ. Which of the two gives y(0.1 s) independent of the tick rate?
- **P5.** The critically damped spring. x'' = −ω² (x − x*) − 2ω x'. Find the roots of the characteristic polynomial, then the solution for e = x − x* with e(0) = e₀ and e'(0) = v₀. For a step of the target (e₀ = −1, v₀ = 0), how long until e is within 5 % of the step, with ω = 12 rad/s? Does x ever pass x*?
- **P6.** Euler. Step the same spring with semi-implicit Euler (velocity first, then position) with step h = ω dt. Write the update as a 2 × 2 matrix acting on (e, v dt). Find its trace and determinant, and the largest h for which both eigenvalues lie inside the unit circle. At 60 Hz, what is the largest ω the Euler spring survives? At 120 Hz?
- **P7.** Weight shift. The rig moves 0.10 m to the right inside `BodyMesh`. The planted feet stay; the legs bend. Does the center of mass move by more or less than 0.10 m? Which segments of Lesson 13's table move less than the rig?
- **P8.** Crouch. The rig lowers by 0.25 m. The upper body (trunk, head, arms) is 0.678 of the mass. Estimate how far the center of mass drops. Lesson 12's pelvis was 0.050 m below the walk cycle's height at the spawn. What happens to that offset when the rig lowers?

## 3. Read

### 3.1 `trigger_response.gd`

A trigger is one axis that rests at 0. Read the header and compare `apply()` with `StickResponse.shape()` (Lesson 02): the same `inverse_lerp` from [inner, outer] to [0, 1], the same optional `Curve`. The outer deadzone matters on a trigger: a trigger that stops at 0.97 of its travel never reaches 1.0 without it. Open `data/input/trigger_curve.tres` in the Inspector and look at the curve editor: P3.

### 3.2 `axial_stick_response.gd`

A subclass of `StickResponse` that overrides `apply()` and inherits `shape()`. Read the diagram in the header: the shaded cross is where one component reads zero. Read the Q/A on `limit_length()`: two keys pressed together give a raw vector of length 1 after `Input.get_vector()`, but two separately shaped components can each reach 1.

### 3.3 `one_pole_filter.gd` and `critical_spring.gd`

Read the header of `OnePoleFilter`, then `blend()` and its Q/A: P4. This is Lesson 02's `blend_factor()` with k = 1/τ, now on a `Vector2` and with its state kept in an object.

In `CriticalSpring`, read the header (the equation, the 5 % time 4.74/ω), then `step()` and its Q/A, which carries out P5 for an arbitrary starting velocity. The update uses `delta` only inside `exp()` and in products with it; there is no step error. `step_euler()` is the method of Lesson 13's `SwayPendulum.step()` applied to this spring: P6.

### 3.4 `stance_controller.gd`

Read the header: the files around the node and the order of one tick. Then:

- `_ready()`: the Q/A on the priority. `BalanceMonitor` writes `rig.position = rest + sway` (Lesson 13 `_sway()`); this node then adds to it. Equal priorities run in tree order, and the scene places `Stance` after `BalanceMonitor`. Lesson 13's code is unchanged.
- `read_input()`: `Input.get_action_raw_strength()` on two actions whose deadzone is 0. Each action holds a key and a trigger axis; the strength is the larger of the two. A key gives 0 or 1, a trigger anything between. The difference right − left times `side_range` (0.10 m) is the sideways target; the length of the player's shaped stick times `forward_lean` (0.04 m) is the forward target.
- `update()`: the four smoothing rules. The crouch target goes through the same rule as the shift, packed into the x component of a `Vector2`.
- The setter of `smoothing` and its Q/A: switching the rule copies the current output into the new filter.
- `apply_to_rig()`: −z is forward in `BodyMesh`, as in Lesson 13.

### 3.5 The scene and the root

`14_analog_stances.tscn` is the Lesson 13 scene with these changes: the root script (`analog_stances.gd`) and name; three new external resources (the controller script, the trigger response, the axial stick response); `stick_response = walk_stick_response.tres` on `Player` (the scenes of Lessons 03–13 have none and use Godot's built-in deadzone); the node `Stance` between `BalanceMonitor` and `HUD`; a taller `RockLabel`.

`analog_stances.gd` keeps the radial response that the scene assigned and swaps it with `axial_stick_response` on key 8. Key 9 writes `Engine.physics_ticks_per_second`. The last HUD line, "CoM over soles", is the height of the center of mass above the mean height of the polygon's corners. Lesson 13's "above feet" is measured in the rig's frame, which the crouch moves down together with the body.

`test_14_stance_scene.gd` checks the order of the three nodes and that the rig's position equals rest + sway + shift − crouch after a tick.

## 4. Run and observe

Start the lesson scene. The HUD at the top right adds five lines: the stance, the tick rate, the smoothing, the raw and shaped triggers, the applied shift and crouch, the deadzone shape, and the height of the center of mass above the soles. Key 1 shows the balance lines of Lesson 13 (they are on at the start).

- **O1. Raw and shaped triggers.** With a gamepad, squeeze the left trigger slowly. Read the two numbers after "triggers L": raw, then shaped. Where does the shaped value leave 0, and where does it reach 1.00? Release the trigger. Does the raw value return to exactly 0.00?
- **O2. A key is a step.** Without a gamepad, hold 6. The raw value jumps to 1.00. Watch "shift": how long until it stops changing? Press 7 until the smoothing reads "none" and repeat. Then "one-pole". Describe the start of the motion in each case: at what speed does the rig begin to move?
- **O3. Off the polygon.** Hold 5 (left). Watch the balance state and the margin. Then hold 6. Is the margin the same on both sides? Look at the polygon from above (key 1 lines, camera pitched down) and find the reason.
- **O4. Crouch.** Press 4. Watch "CoM over soles" and the Lesson 13 line "CoM ... above feet". Which one changes? How far does the rig move down, and how far does the center of mass move down?
- **O5. Tick rate.** Set the smoothing to "spring (Euler)", hold 6 and read the shift at intervals (pause with the editor's pause button, or record the HUD with a screen capture). Press 9 for 120 Hz and repeat. Then do the same with "critical spring".
- **O6. Axial walking.** Press 8 ("stick axial"). With a gamepad, walk forward and push the stick slowly toward the right. When does the body start to turn? Press 8 again and repeat. Then, with the keyboard, walk with W and D together in both modes and compare the speed on the HUD's left side.

## 5. Tweak

- **T1.** In `data/input/trigger_response.tres`, clear **Curve**. The response becomes linear. Hold the trigger at a light pressure: what is the smallest shift you can hold steady, with and without the curve?
- **T2.** In the scene, select `Stance` and set **Side Range** to 0.15. Which full-trigger shift now leaves the polygon, and which one only comes close? At which side range does the right side reach "marginal"?
- **T3.** Set **Spring Frequency** to 4, then to 30. Which value reads as a person shifting weight, and which as a machine? Set the smoothing to "spring (Euler)" and **Spring Frequency** to 60, run at 60 Hz, and hold 6. Then press 9.
- **T4.** Set **Time Constant** to 0.4 and compare the one-pole filter with the spring at **Spring Frequency** 12. Both reach their target in about the same time. Which one looks heavier?
- **T5.** Set **Crouch Depth** to 0.45, then to 0.55, and run from the spawn without walking. Watch the knees and the ankle errors on the Lesson 12 HUD line. What limits the depth?

## 6. Exercises

- **E1 ★ Trigger travel.** Log `trigger_raw` for 10 s with both triggers released, then while squeezing each trigger fully five times. Report the rest value, the largest value at rest, and the largest value at full squeeze. Choose `inner_deadzone` and `outer_deadzone` from the data and justify the numbers. Do the two triggers of your controller agree?
- **E2 ★ A scaled radial deadzone with a hint of axial.** Sutphin's article ends with a hybrid: a radial deadzone followed by a small axial snap near the axes. Write `HybridStickResponse` (a third subclass), give it a snap angle in degrees, and choose the angle from P1. Measure the angle at which the body turns in O6 with each of the three responses.
- **E3 ★★ Velocity limit.** A body cannot move its weight faster than some speed. Add a maximum speed to `CriticalSpring` (clamp the velocity) and plot the response to a step of 0.10 m with ω = 30 rad/s and a limit of 0.3 m/s. Does the clamped spring still reach its target without overshoot? Is the result still independent of the tick rate? Measure it at 60 and 120 Hz.
- **E4 ★★ Lean from the stick, both ways.** The forward lean uses only the length of the stick. Rotate the stick into the body's frame (the body turns toward the travel direction, so most of it is forward) and lean sideways by its x component as well. On a slope, lean uphill when standing still: use the ground normal under the feet. Show where the center of mass stands relative to the polygon on the spawn slope, with and without the uphill lean.
- **E5 ★★ Hip hinge.** The crouch lowers the rig straight down; the trunk stays vertical and the knees go forward (O4). Real crouching bends the hips: the trunk tilts forward and the pelvis moves back, which keeps the center of mass over the feet. Add a hip-pitch rotation to the `Spine` bone that grows with the crouch depth, and move the rig back by an amount you derive from the table of Lesson 13 so that the ground point of the center of mass does not move. Compare the margin with the plain crouch.
- **E6 ★★ The weight shift in sound.** Send `/body/stance` with the shift, the crouch and the stance at 30 Hz, using `RateClock` and `BalanceMonitor.sender` as models. In SuperCollider, make the shift pan a sustained sound and the crouch darken it (a low-pass cutoff). Render a recorded sequence offline with `Score.recordNRT`. Smooth the values on the SuperCollider side with `Lag` and compare with the filter in Godot: which side should smooth, and why not both?
- **E7 ★★★ Capture-point stepping from the triggers.** Complete Lesson 13 E5 (capture point) first. A shift that would take the capture point out of the polygon makes the body step sideways instead. Decide which foot steps, where it lands, and how `FootRig` is told; then show that the full trigger in either direction never leaves the body in the "outside" state for more than half a second.

## 7. Reflect

- **R1.** The weight shift moves the rig and not the capsule. On a ledge 0.3 m wide, the body can lean over the edge with the capsule safe on the ledge. Which later lesson needs the capsule to know about the lean, and how would it learn it?
- **R2.** The one-pole filter and the spring are the two filters a synthesist reaches for: `Lag` and a two-pole resonant low-pass at the edge of resonance. Which other parameter changes of the game (camera, sound, foot placement) are steps that need one of the two, and which one?
- **R3.** Key 9 changes the tick rate while the game runs. The exact filters do not notice. List the systems of Lessons 02–13 that would notice, and for each, whether the difference is an error or the intended behavior.
- **R4.** The crouch is a stance: a state with a smooth transition. Climbing (Lesson 15) will add reaching, hanging and pulling up. Should those be values of the `Stance` enum, or a separate state machine that reads this one, as Lesson 13 R4 asked for the balance states?

## 8. Answers

<details><summary>P1</summary>

Raw: (sin 10°, cos 10°) × 0.5 = (0.087, 0.492).

Radial: the magnitude 0.5 gives t = 0.38/0.83 = 0.458 and t^1.6 = 0.287. The direction is kept: (0.050, 0.282). The body walks 10° to the right.

Axial: x = 0.087 lies inside the deadzone 0.12 and gives 0. y = 0.492 gives t = 0.449, output 0.277. Result (0, 0.277): straight forward, at 97 % of the radial speed.

The axial response returns straight forward while |x| = m sin θ ≤ 0.12, that is θ ≤ arcsin(0.12/m): 13.9° at m = 0.5, 6.9° at m = 1.0, 23.6° at m = 0.3. A light push snaps to the axis over a wide cone; `AxialStickResponse.apply()` gives exactly these values (measured).
</details>

<details><summary>P2</summary>

Axial: each component 0.707 gives t = (0.707 − 0.12)/0.83 = 0.707 and 0.707^1.6 = 0.575. The vector (0.575, 0.575) has length 0.813. Radial: the magnitude 1.0 is above the outer deadzone, output 1.0. The axial response walks 19 % slower on the diagonal at full deflection (measured: 0.813 and 1.000). At half deflection on the diagonal the axial length is 0.186 against 0.287 radial, 35 % slower. The axial deadzone treats the axes as preferred directions; a stick has none.
</details>

<details><summary>P3</summary>

Cubic Hermite on [0, 1] with end values p₀ = 0, p₁ = 1 and end slopes m₀ = 0.5, m₁ = 1.5:

c(t) = (t³ − 2t² + t) · 0.5 + (−2t³ + 3t²) · 1 + (t³ − t²) · 1.5 = 0 · t³ + 0.5 t² + 0.5 t.

The cubic term cancels: c(t) = 0.5 t (1 + t), with c(0) = 0, c(1) = 1, c'(0) = 0.5, c'(1) = 1.5. Godot's `Curve` places Bézier handles at one third of the interval along each tangent, which is the same cubic. Raw 0.5 gives t = (0.5 − 0.05)/0.9 = 0.5 and c = 0.375. The first quarter of the travel (t ≤ 0.25) gives outputs up to 0.156: a quarter of the travel for a sixth of the range, with half the linear slope at the start. Measured with `TriggerResponse.apply()`: raw 0.10 → 0.029, 0.25 → 0.136, 0.50 → 0.375, 0.75 → 0.691, 0.90 → 0.918, 0.95 and above → 1.000; each value equals 0.5 t (1 + t).
</details>

<details><summary>P4</summary>

y(t) = 1 − e^(−t/τ). After 0.1 s: 1 − e^(−0.833) = 0.565. Over a tick with x held: y(t + dt) − x = (y(t) − x) e^(−dt/τ), which rearranges to y + (1 − e^(−dt/τ))(x − y). At 60 Hz, a = 1 − e^(−0.1389) = 0.1297, against dt/τ = 0.1389. The exact a gives y(0.1 s) = 0.5654 at 60, 120 and 240 Hz (measured to four decimals). The linear blend dt/τ gives 0.5923 at 60 Hz, 0.5784 at 120 Hz and 0.5718 at 240 Hz: it approaches 0.5654 as dt shrinks, from above. A one-pole filter that steps faster than its exact solution is an Euler step (P6).
</details>

<details><summary>P5</summary>

The characteristic polynomial r² + 2ωr + ω² = (r + ω)² has the double root −ω. The general solution is e(t) = (c₁ + c₂ t) e^(−ωt); e(0) = e₀ gives c₁ = e₀, and e'(0) = −ω c₁ + c₂ = v₀ gives c₂ = v₀ + ω e₀. This is `CriticalSpring.step()`.

For e₀ = −1, v₀ = 0: e(t) = −(1 + ωt) e^(−ωt). The value x = 1 + e never passes 1, since (1 + ωt) e^(−ωt) > 0 for all t. The 5 % time solves (1 + u) e^(−u) = 0.05: u = 4.744, so t = 4.744/12 = 0.395 s. Measured: the first tick at or above 0.95 is at 0.400 s at 60 and 120 Hz (the next tick after 0.395 s). Values at 0.05, 0.1, 0.2, 0.4 s: 0.1219, 0.3374, 0.6916, 0.9523, identical at 60, 120 and 240 Hz.

Compared with the one-pole filter at τ = 0.12 s (0.3408, 0.5654, 0.8111, 0.9643): the spring starts slower and arrives at a similar time.
</details>

<details><summary>P6</summary>

With h = ω dt and u = v dt: u ← (1 − 2h) u − h² e, then e ← e + u. As a matrix on (e, u):

M = [[1 − h², 1 − 2h], [−h², 1 − 2h]], trace 2 − 2h − h², determinant (1 − h²)(1 − 2h) + h²(1 − 2h) = 1 − 2h.

For a real 2 × 2 matrix both eigenvalues lie inside the unit circle when |det| < 1 and |trace| < 1 + det. |1 − 2h| < 1 holds for 0 < h < 1. The trace condition fails first, on the negative side: −(2 − 2h − h²) < 2 − 2h gives h² + 4h − 4 < 0, h < 2(√2 − 1) = 0.828. At 60 Hz the Euler spring survives up to ω = 0.828 × 60 = 49.7 rad/s; at 120 Hz up to 99.4 rad/s. Measured by stepping from e = 1: at h = 0.82 the peak is 1.14 and the response decays; at h = 0.83 it grows to 9327 within 2000 steps. The discriminant trace² − 4 det = 4h³ + h⁴ is never negative, so both eigenvalues are real. For h > 0.5 the determinant 1 − 2h is negative, so one eigenvalue is negative and its component alternates in sign. In a step from rest that component starts small; the overshoot becomes visible near h = 0.75 and reaches up to 14 % before h = 0.828. With ω = 12 (h = 0.2 at 60 Hz) Euler does not overshoot but is faster than the exact spring: 0.4013 at 0.1 s at 60 Hz, 0.3689 at 120 Hz, 0.3530 at 240 Hz, against 0.3374. DDG section 6.6 makes the same observation for forward Euler on the heat equation; backward Euler would be stable for every h at the price of a linear solve. The exact step needs neither.
</details>

<details><summary>P7</summary>

Less. The feet do not move (2 × 0.0145 of the mass). The shanks hang between a fixed ankle and a knee that moves, and the thigh's lower end moves less than the hip. Everything above the hips moves with the rig. Measured at the spawn with the smoothing off, shifting from −0.15 to +0.15 m: the ground point of the center of mass moves by 0.905 of the rig's shift (from −0.134 to +0.137 m in the body frame).
</details>

<details><summary>P8</summary>

The upper body alone gives 0.678 × 0.25 = 0.17 m; the thighs and shanks add a part of their drop. Measured: the center of mass drops by 0.170 m (0.924 → 0.755 m above the soles), and the upper-body segments drop by 0.200 m, not 0.25 m. The difference is Lesson 12's pelvis offset: standing, the pelvis is held 0.050 m below the walk cycle's height so that both feet are in reach. Crouched, every target is in reach and the offset rises back to 0 (pelvis line on the HUD). Of the legs, the thighs drop 0.14–0.16 m and the shanks 0.03–0.06 m; their centers move forward by 0.05–0.11 m because the knees bend forward. The ground point of the center of mass moves forward by 0.022 m.
</details>

<details><summary>O1</summary>

The shaped value stays 0.00 up to a raw value of 0.05 and reaches 1.00 at 0.95. Between them it follows the curve: 0.10 → 0.03, 0.25 → 0.14, 0.50 → 0.38, 0.75 → 0.69, 0.90 → 0.92 (measured with `TriggerResponse.apply()`). The rest value depends on the controller (E1). A raw rest value of a few hundredths, below the inner deadzone, gives a shaped 0.00.
</details>

<details><summary>O2</summary>

With "critical spring" (the default) the shift reaches 95 % of 0.100 m at 0.40 s, starting at zero speed: 0.034 m at 0.1 s, 0.069 at 0.2 s, 0.095 at 0.4 s. With "none" the rig jumps 0.10 m in one tick and the legs follow in that tick. With "one-pole" the motion starts at its highest speed, 0.10/0.12 = 0.83 m/s: 0.057 m at 0.1 s, 0.081 at 0.2 s, 0.096 at 0.4 s. The one-pole output has a corner at the start; the spring's has none (measured in the scene with the trigger action pressed at strength 1).
</details>

<details><summary>O3</summary>

No. At the spawn (standing, measured with the smoothing off), a full left shift of 0.10 m gives margin −0.011 m (outside), a full right shift +0.049 m (stable). With no shift the margin is +0.030 m. The margin peaks at +0.069 m near a right shift of 0.075 m and falls on either side of it. The polygon is not centered under the body: at rest the walk left one foot ahead of the other (Lesson 13, staggered six-corner polygon), and the right foot's ankle stands 0.11 m right of the body's midline, the left one 0.09 m left. The nearest edge on the left side is a diagonal between the two soles.
</details>

<details><summary>O4</summary>

"CoM over soles" goes from 0.924 to 0.755 m. Lesson 13's "CoM ... above feet" goes the other way, from 0.961 to 1.041 m: it is the height in the skeleton's frame, whose origin moves down with the rig while the soles stay on the ground, so the soles end up below that origin. The rig moves 0.25 m; the upper body 0.20 m (P8); the center of mass 0.17 m. Both ankle errors stay 0.000 m. The margin grows from +0.030 to +0.046 m because the center of mass moves forward by 0.022 m, toward the middle of the staggered polygon (measured at the spawn).
</details>

<details><summary>O5</summary>

Spring (Euler), shift at 0.1, 0.2, 0.4 s after pressing 6: 0.0401, 0.0720, 0.0945 m at 60 Hz; 0.0369, 0.0707, 0.0949 m at 120 Hz. Critical spring: 0.0337, 0.0692, 0.0952 m at both rates. One-pole: 0.0565, 0.0811, 0.0964 m at both rates (measured in the scene). At ω = 12 the Euler difference is a few millimeters and invisible; it grows with ω dt (P6, T3).
</details>

<details><summary>O6</summary>

With the radial response the body turns as soon as the stick leaves the forward axis. With the axial response it walks straight until the stick is about 14° off at half deflection and 7° off at full deflection (P1), then turns at once to a direction between the axes. With W and D together, `Input.get_vector()` returns (0.707, −0.707). Radial: 3.0 m/s. Axial: 0.813 × 3.0 = 2.4 m/s (P2).
</details>

<details><summary>T1</summary>

Without the curve the response is t on [0.05, 0.95]: a trigger held at a raw 0.10 gives 0.056 instead of 0.029, and a tremor of ±0.02 in the raw value moves the shift by ±0.0022 m instead of about ±0.0012 m near that point (the curve's slope at t = 0 is half the linear one). The curve gives the first quarter of the trigger's travel to small shifts.
</details>

<details><summary>T2</summary>

With a side range of 0.15 m, the full left shift gives margin −0.027 m (outside) and the full right shift +0.004 m (marginal). The right side reaches "marginal" (margin below 0.015 m) between 0.125 m (+0.026) and 0.15 m (+0.004): about 0.14 m. These values come from the sweep at the spawn with the smoothing off.
</details>

<details><summary>T3</summary>

ω = 4 rad/s takes 4.74/4 = 1.2 s to settle: a slow, deliberate shift. ω = 30 takes 0.16 s: a snap. ω = 60 with Euler at 60 Hz gives h = 1.0, above the limit 0.828: the shift alternates in sign and grows without bound within a fraction of a second. At 120 Hz, h = 0.5 and the same spring settles. The exact `step()` settles at both rates for any ω.
</details>

<details><summary>T4</summary>

The one-pole filter with τ = 0.4 s needs 3τ = 1.2 s to reach 95 %; the spring with ω = 12 needs 0.40 s. To match the 95 % times the one-pole needs τ = 0.40/3 = 0.13 s. At matched settling time the spring reads as heavier: it starts from rest and accelerates, as a mass does, where the one-pole starts at full speed.
</details>

<details><summary>T5</summary>

At 0.45 m the left thigh is 3.5° from horizontal, the knee's inner angle is 52°, and both ankle errors are 0.000 m: the IK of Lesson 12 has no joint limits besides the ankle tilt, so the legs fold as far as asked. At 0.55 m the left leg snaps straight. At the spawn the left foot is not planted (the walk stopped in its swing, Lesson 13), so it follows the landing target that `FootRig._update_target()` finds with a ray a quarter stride ahead, uphill. The ray starts `ray_up` = 0.6 m above the lowered rig, which is now below the uphill ground: the ray misses, the foot has no target, and the leg takes the walk cycle's pose. At 0.60 m the ray under the home point misses as well. The limit is the ray's reach, not the leg (measured at depths 0.35, 0.45, 0.50, 0.55, 0.60).
</details>
