# Lesson 13. Balance

Lesson scene: `game/scenes/lessons/13_balance.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–12 are unchanged; the Lesson 12 scene has no balance measurement and no push keys.

## 1. Orientation

Lesson 12 ended with feet that stand on the ground and a pelvis placed from the feet. Nothing yet says whether the body could stand there. This lesson measures it. It answers four questions:

1. Where is the body's center of mass? (segment masses from a table, a weighted mean of points)
2. Which region of the ground carries the body? (the contact set, its convex hull)
3. How far is the center of mass from losing that support? (signed distance from a point to a convex polygon: the balance margin)
4. What does the body do after a push? (a linearized inverted pendulum with a spring and a damper)

The method: `BalanceMonitor`, a new node in the scene, reads the `FootRig` of Lesson 12 every physics tick. It computes the center of mass c from the bone poses and the mass table `SegmentMasses`, collects the sole corners of the feet in contact, builds their convex hull `SupportPolygon.convex_hull()`, and takes the signed distance from c's ground point to the hull. A small state machine turns the margin into four states (no support, stable, marginal, outside). The margin goes to the HUD and over OSC to SuperCollider. Keys 2 and 3 push the body; `SwayPendulum` moves the rig inside `BodyMesh` and the IK of Lesson 12 keeps the feet in place.

The measurement is static balance: c over the support polygon. Section 4 shows that walking is not statically balanced. Lesson 14 drives the weight shift from the stick and triggers; a step that answers a push is exercise E4.

Goal served (`plan.md`): "a humanoid player that can walk, crawl, climb, and balance"; "procedural soundscapes and music that respond to the player's movement".

Files:

| File | Role |
|---|---|
| `game/src/body/segment_masses.gd` | `SegmentMasses` (`@tool` Resource): Winter's mass fractions and center-of-mass ratios; `segments(proportions)`, `total_fraction()`. |
| `game/data/body/winter_segment_masses.tres` | The table's values (the script's defaults). |
| `game/src/body/center_of_mass.gd` | `CenterOfMass` (static): `segment_centers()`, `weighted_mean()`, `compute()`. |
| `game/src/body/support_polygon.gd` | `SupportPolygon` (static): `ground_point()`, `cross()`, `convex_hull()` (monotone chain), `distance_to_segment()`, `signed_distance()`, `area()`. |
| `game/src/body/sway_pendulum.gd` | `SwayPendulum` (RefCounted): s'' = (g/L − kp) s − kd s', semi-implicit Euler, `push()`. |
| `game/src/body/balance_monitor.gd` | `BalanceMonitor` (Node3D): measurement, contact test, state machine, OSC, sway, debug lines (`ImmediateMesh`). |
| `game/src/lessons/balance.gd` | Scene root. Extends `feet_on_the_ground.gd` (Lesson 12); keys 1, 2, 3; two lines in `HUD/RockLabel`. |
| `game/scenes/lessons/13_balance.tscn` | The Lesson 12 scene plus the node `BalanceMonitor`. |
| `game/project.godot` | Input actions `toggle_balance_debug` (1), `push_body_side` (2), `push_body_forward` (3); `run/main_scene`. |
| `audio/supercollider/13_balance.scd` | OSCdefs for `/body/balance` and `/body/balance/state`; a tone whose pitch follows the margin. |
| `game/tests/test_13_*.gd` | Hull and distance on random input; mass table, center of mass, pendulum, states; the scene, the keys, the OSC stream. |
| `docs/decisions/0013-static-balance.md` | Why the margin is static, why contact is planted-or-near, why the sway moves the rig. |

Keys 1, 2 and 3 are digit keys; every letter is bound (Lesson 12). Shift with 2 or 3 pushes the other way. None has a gamepad binding.

Reading:

- David A. Winter, *Biomechanics and Motor Control of Human Movement*, 4th ed., chapter 4 (anthropometry): Table 4.1, segment mass fractions and center-of-mass locations; the whole-body center of mass as a weighted sum.
- A. M. Andrew, "Another efficient algorithm for convex hulls in two dimensions", *Information Processing Letters* 9 (1979): the monotone chain. M. de Berg et al., *Computational Geometry: Algorithms and Applications*, 3rd ed., chapter 1 (convex hulls, the left-turn test, degenerate cases).
- Keenan Crane, *Discrete Differential Geometry: An Applied Introduction* (`discreteDifferentialGeometry.pdf`), section 5.1 "Vector Area", pp. 85–87: the signed area of a polygon, positive for counterclockwise vertices, and the area as ½ Σ pᵢ × pᵢ₊₁ (Exercise 5.1). `SupportPolygon.area()` is this formula; the tests use its sign to check the orientation of a hull.

## 2. Predict

Notation: the body faces −z, up is +y, x is to the right. The rig of Lesson 11 has hips 0.94 m above the soles, thigh 0.44 m, shin 0.42 m, ankle 0.08 m, spine 0.22 m, chest 0.26 m (shoulders 0.04 m below its top), neck 0.08 m, head 0.24 m, upper arm 0.29 m, forearm 0.27 m, feet 0.24 m long with heel 0.06 m behind the ankle. Total height 1.74 m.

The mass table (Winter, Table 4.1): fraction of body mass f and position of the segment's center from its proximal end r, as a fraction of its length.

| Segment | f | r | Rig endpoints |
|---|---|---|---|
| Trunk | 0.497 | 0.50 | Hips joint → shoulder midpoint |
| Head and neck | 0.081 | 1.00 | Neck joint → middle of the head |
| Upper arm (×2) | 0.028 | 0.436 | shoulder → elbow |
| Forearm and hand (×2) | 0.022 | 0.682 | elbow → wrist |
| Thigh (×2) | 0.100 | 0.433 | hip → knee |
| Shank (×2) | 0.0465 | 0.433 | knee → ankle |
| Foot (×2) | 0.0145 | 0.50 | ankle → sole point 0.12 m ahead |

- **P1.** Center of mass. Check that the fractions sum to 1. Compute the height of c for the rest pose (straight legs, arms down). Which segment contributes most to c's height? Express the result as a fraction of the body height.
- **P2.** Weighted mean. c = Σ fᵢ cᵢ / Σ fᵢ. What happens to c if every f is multiplied by the same number (a heavier body)? If only the trunk fraction is raised from 0.497 to 0.6, does c rise or fall, and why does the code still work although the fractions no longer sum to 1?
- **P3.** The support polygon. Two feet stand side by side, ankles 0.20 m apart; each sole is a rectangle 0.08 m wide from 0.06 m behind to 0.18 m ahead of its ankle. Draw the convex hull from above. How many corners has it, what is its area, and what is the margin of a point midway between the ankles? Which edge is nearest?
- **P4.** Left turns. Three points a, b, c in the plane. The sign of (b − a) × (c − a) tells which way the path a → b → c turns. Which sign is a left turn when x points right and y points up? The ground coordinates in the code are (x, −z). Seen from above, with x to the right, which way does −z point? Why does the code not use (x, z)?
- **P5.** Monotone chain. Sort the points by x, then walk left to right, keeping a list. Before each new point, remove the last kept point while the last two kept points and the new one do not make a left turn. Run it by hand on (0,0), (1,1), (2,0), (1,−1), (1,0). What is left after the lower and the upper pass? What is the cost for n points?
- **P6.** Signed distance. For a convex polygon with counterclockwise corners, write a test for "p is inside" using P4, and the distance from p to one edge. Why is the distance to the polygon from an outside point the minimum over the edges, and why is the distance from an inside point also that minimum? What should the margin be with one foot down, or with none?
- **P7.** The inverted pendulum. A point mass at height L over a pivot, leaning by a horizontal offset s (small). Derive s'' = (g/L) s. Add a restoring acceleration −kp s − kd s'. For which kp does the body come back? With L = 0.96 m, kp = 20 s⁻² and kd = 4 s⁻¹, compute the natural frequency ω = √(kp − g/L) and the damping ratio ζ = kd/(2ω). A push adds 0.4 m/s at once. Estimate the largest offset.
- **P8.** Walking. Lesson 12 keeps exactly one foot planted for most of each step (the swings of the two feet do not overlap). Where is c during a single-support phase, relative to the stance foot? Guess the fraction of walking ticks on which c lies over the support polygon.

## 3. Read

### 3.1 `segment_masses.gd`

Read the header: the source table and the meaning of fraction and ratio. Then `segments()`: each segment is a pair of points, each in some bone's frame. Read the comments that name the stand-ins: the rig has no greater trochanter and no ear canal, so the hip-joint midpoint and the middle of the head take their places. `total_fraction()` counts arms and legs twice.

The table's values live in the script's defaults and in `data/body/winter_segment_masses.tres`. The scene assigns the `.tres` (decision 0004); a different body type (a child, a heavy pack) is a second `.tres`.

### 3.2 `center_of_mass.gd`

Three functions. `segment_centers()` reads each endpoint from `Skeleton3D.get_bone_global_pose()` (the bone's transform in the skeleton's frame) and interpolates with the ratio. `weighted_mean()` is the formula of P2. Read its Q/A on the precision of the sums. `compute()` chains the two.

`get_bone_global_pose()` returns what the skeleton last computed. When the pose was set in the same frame, `force_update_all_bone_transforms()` must run first (Lesson 11). `BalanceMonitor` avoids the question by running before the player (3.5).

### 3.3 `support_polygon.gd`

Read the header and its diagram of the ground coordinates: P4. Then in order:

- `cross()`: the z component of the 2D cross product, formed in 64-bit floats from 32-bit inputs.
- `convex_hull()`: read the Q/A on `sort()`, the lower and upper chains, and the Q/A on dropping the last point of each chain: P5. Note the `<= 0.0` in the turn test: collinear points are removed, so a hull corner is always a true corner. Read the special cases at the end: fewer than three distinct points, and all points on a line.
- `distance_to_segment()`: the projection parameter t, clamped. Read its Q/A.
- `signed_distance()`: one loop over the edges computes both the nearest distance and the inside test. Read the Q/A: P6. Fewer than three corners give a negative distance; no corners give −∞.
- `area()`: the shoelace formula, DDG section 5.1.

`test_13_support_polygon.gd` checks the hull on a square with inner, repeated and collinear points, on 200 random sets (left turns only, every input point inside, corners from the input, area independent of input order) and the distance on 2000 random points against an independent test.

### 3.4 `sway_pendulum.gd`

Read the header: P7 in code. `step()` and its Q/A: the velocity is updated first, and the new velocity moves the position. At the limit `max_offset` the outward part of the velocity is removed. `natural_frequency()` and `damping_ratio()` return the two numbers of P7.

### 3.5 `balance_monitor.gd`

Read the header: the six steps of a tick. Then:

- `_ready()`: read the Q/A on `process_physics_priority = -1`. The monitor runs before `Player` and therefore reads the pose of the previous tick, which is the pose on the screen.
- `measure()`: the center of mass in the skeleton's frame, then in world space; `center_height` is its height above the rig's origin (the feet). The corners of the feet in contact go to the hull.
- `foot_in_contact()`: read its Q/A. A planted foot counts. A foot that is not planted counts when its lowest sole corner is within `contact_tolerance` (0.02 m) of the ground under it. Why the second rule: at rest, the phase stops where the walk left it, and at phase 0 the left foot is in mid-swing (Lesson 12, `test_12_foot_rig.gd`). With the walk amount at 0, that foot stands on the ground but is not planted.
- `sole_corners()`: the foot capsule of `BodyProportions.bone_specs()` seen from below, a rectangle 2 r wide from the heel to the toes.
- `next_state()`: the table in its comment, and the Q/A on hysteresis.
- `_send()` and `balance_arguments()`: the layout of the two messages (3.7).
- `_sway()`: the pendulum's height is the measured `center_height`. Read the Q/A on moving the rig and not the player.
- `_draw_debug()`: an `ImmediateMesh` rebuilt every tick with `PRIMITIVE_LINES`: the polygon's edges, c, its plumb line and its ground point, all in the state's color; the segment centers as small white crosses. The material is unshaded, takes the vertex color, and ignores depth, so the lines show through the body. `FootRig` draws its rays the same way (Lesson 12).

`test_13_balance.gd` drives a `FootRig` on a floor box by hand, as `test_12_foot_rig.gd` does, and calls `measure()` itself.

### 3.6 The scene

`13_balance.tscn` is the Lesson 12 scene with three changes: the root script (`balance.gd`), the root's name, and the node `BalanceMonitor` before `HUD`, whose `rig` points to `Player/BodyMesh/Rig` and whose `masses` is the Winter `.tres`. `balance.gd` reads Shift from the key event: Shift + 2 pushes left, Shift + 3 pushes backward.

### 3.7 OSC

```
/body/balance        margin state x z height   (f i f f f), send_rate_hz (30) per second
/body/balance/state  name                       (s), on every change of state
```

margin is −1000 when no foot touches the ground (−∞ is not portable over OSC). x and z are the ground point of c, height is c above the feet. `13_balance.scd` stores the values in `~balance`, prints each state change, and (blocks 2 and 3, with a server you boot) plays a tone that rises as the margin shrinks and beats when c is outside.

## 4. Run and observe

Start the lesson scene. The lines are on (key 1 toggles them): the support polygon on the ground, c as a cross in the body, its plumb line, and its ground point, green for stable, yellow for marginal, red for outside, gray for no support. The HUD at the top right shows the state, the margin, the height of c above the feet and the sway.

- **O1.** Stand still. Read the height of c and the margin. Compare with P1. Why is the height lower than your P1 answer, and why is the polygon not the rectangle of P3? Look at the feet from above (arrow keys).
- **O2.** Press 2 (push right), 3 (forward), Shift + 3 (backward). For each, watch the margin and the state. Which push comes closest to the edge? Press 2 twice in quick succession.
- **O3.** Walk at full stick and watch the colors. How often is c over the polygon? Compare with P8. Then walk at a third of the stick.
- **O4.** Press Q (Lesson 12) to switch the legs to the walk cycle, then stand still and walk. What happens to the polygon? Why does the margin still make sense?
- **O5.** Walk off the far end of the staircase (Lesson 12 O3), a drop of about 1.3 m. What does the monitor report in the air? Which message reaches SuperCollider on landing, and how long does that state last?
- **O6.** Start `audio/supercollider/13_balance.scd` (block 1) and walk. Count the state changes per second. Then boot the server yourself and run blocks 2 and 3; push the body with Shift + 3.
- **O7.** In a scratch script, time `SupportPolygon.convex_hull()` with `signed_distance()` on the eight corners of two feet, `CenterOfMass.compute()`, and `BalanceMonitor.measure()`.

## 5. Tweak

Make each change, run, observe, and revert. Most are exported properties of `BalanceMonitor`, editable in the Remote Inspector while the game runs.

- **T1.** Set `contact_tolerance` to 0. Stand still at the spawn. What does the polygon become, and what is the state? Which rule of `foot_in_contact()` no longer applies?
- **T2.** Set `stiffness` to 5, then to 10, then press 2. Compare with g/L on the HUD's height of c. What does the body do without a push?
- **T3.** Set `damping` to 0 and press 2. Does the amplitude change over ten seconds? Compare with v/ω. Then, in `SwayPendulum.step()`, swap the two update lines (position first, with the old velocity). What happens now?
- **T4.** Set `hysteresis` to 0 and walk for five seconds. Count the state changes (on the HUD, or in SuperCollider). Where would the band make a difference?
- **T5.** In `winter_segment_masses.tres`, set `trunk_fraction` to 0.6. How far does c move? Compare with P2.
- **T6.** Set `send_rate_hz` to 0. Which messages still go out?

## 6. Exercises

- **E1 ★ Hand check of the table.** Compute the center of mass of the rest pose by hand (P1) segment by segment, then with the rig in the walk cycle's pose at φ = 0.25 (left heel strike, amount 1). Print `CenterOfMass.segment_centers()` from a scratch script and find the segment where your number and the code's differ the most. Which stand-in point of `segments()` is the least faithful to Winter's landmark, and how much does it move c?
- **E2 ★ Nearest edge.** Return, besides the margin, the edge (or corner) that realizes it, and draw it in the debug lines in a second color. Show the direction in which c must move to gain margin fastest. Which edge is nearest at rest, and does it change after a push to the right?
- **E3 ★★ Margin on a slope.** The ground coordinates drop y. On a slope of 20°, c projects vertically, but the soles lie in a tilted plane. Compare the vertical projection with a projection along the ground normal, and with the polygon built from the corners' true 3D positions. Find the slope at which the two margins differ by 1 cm. Which projection is right for static balance, and why?
- **E4 ★★ A step that answers a push.** Lesson 12 R1 asked for a step trigger. When the state is OUTSIDE for longer than a threshold while the body stands still, make `FootRig` take a step with the foot on the side of the push, landing so that the new polygon contains c. You need a second step trigger in `FootRig`; complete Lesson 12 E2 first, or write a minimal one. Measure the largest push (in m/s) the body survives without, and with, the step.
- **E5 ★★ Capture point.** Static balance ignores velocity. For the linear inverted pendulum, the point ξ = s + s'/ω₀ with ω₀ = √(g/L) is where the body must step to come to rest over it. Compute ξ from c and its velocity (finite differences over two ticks), draw it, and send its signed distance to the polygon as a sixth argument of `/body/balance`. While walking, how often is ξ inside the polygon, compared with c? (Reading: Pratt et al., "Capture Point: A Step toward Humanoid Push Recovery", 2006.)
- **E6 ★★ Hearing the margin.** Replace the tone of `13_balance.scd` with a sound that belongs to the body: a creak or a breath whose density rises as the margin shrinks, and a short sound on each entry into OUTSIDE. Render it offline with `Score.recordNRT` from a recorded sequence of `/body/balance` values (log them in Godot to a file first).
- **E7 ★★★ Mass from geometry.** Replace the table by masses computed from the rig's capsules: volume of each capsule times a density. Compare the fractions with Winter's. Which segments disagree, and what does that say about the capsule radii of `BodyProportions`?

## 7. Reflect

- **R1.** The margin answers "could the body stand still here?". A walker almost never could (O3). Which quantity answers "is the walk under control?", and what does it need that the static margin does not (velocity, the next foothold)?
- **R2.** The sway moves the rig, not the capsule. Physics never learns that the body leaned. In Lesson 14 the stick and triggers move the weight. Should the weight shift move the capsule, the rig, or the camera, and what does each choice mean for collisions on a narrow ledge?
- **R3.** Climbing (Lesson 15) adds hands as contacts. A hand on a hold above the shoulders can pull. Is the convex hull of all contacts, projected onto the ground, still the right region? What replaces it when the contacts are not on one plane?
- **R4.** The state machine has four states and two thresholds. Which other body states (crouched, reaching, falling, recovering) will the music of later lessons need, and should each be a state of this machine or a separate machine that reads its output?

## 8. Answers

<details><summary>P1</summary>

Sum: 0.081 + 0.497 + 2 (0.028 + 0.022 + 0.100 + 0.0465 + 0.0145) = 0.578 + 2 × 0.211 = 1.000.

Heights in the rest pose: trunk center (0.94 + 1.38)/2 = 1.16 m; head and neck at the middle of the head, 1.62 m; upper arm 1.38 − 0.436 × 0.29 = 1.254 m; forearm 1.09 − 0.682 × 0.27 = 0.906 m; thigh 0.94 − 0.433 × 0.44 = 0.749 m; shank 0.50 − 0.433 × 0.42 = 0.318 m; foot 0.04 m. Weighted: 0.5765 + 0.1312 + 0.0702 + 0.0399 + 0.1499 + 0.0296 + 0.0012 = 0.998 m. The trunk contributes 0.577 m of it. `CenterOfMass.compute()` on the rig in its rest pose gives (0, 0.99844, −0.00174): 57.4 % of the 1.74 m height. The small −z offset comes from the feet, whose centers lie 0.06 m ahead of the ankles.
</details>

<details><summary>P2</summary>

A common factor cancels between numerator and denominator: c does not change. The body mass of `SegmentMasses` enters nowhere. With the trunk at 0.6 the sum is 1.103 and the division by Σ f renormalizes. The trunk's center (1.16 m) lies above c (0.998 m), so c rises: measured 1.0135 m, 0.015 m higher (T5).
</details>

<details><summary>P3</summary>

The hull is the rectangle around both soles: x from −0.14 to 0.14 m, from 0.06 m behind to 0.18 m ahead of the ankles. Four corners (the inner corners of the soles lie inside), area 0.28 × 0.24 = 0.0672 m². The midpoint between the ankles is 0.14 m from the side edges, 0.18 m from the front and 0.06 m from the back edge: margin 0.06 m, back edge nearest. A body stands closer to falling backward than forward.
</details>

<details><summary>P4</summary>

Positive is a left turn (counterclockwise) when x points right and y up. Seen from above, with x to the right, −z points up the page (the body faces −z, and "forward" is up on a map). In (x, z) the page's up direction would be −z's opposite: the picture would be mirrored, a counterclockwise turn on the screen would have a negative cross product, and every "left" in the comments would mean right. (x, −z) keeps the top view and the textbook's orientation the same. `test_13_support_polygon.gd` checks it: right, then forward gives positive area.
</details>

<details><summary>P5</summary>

Sorted: (0,0), (1,−1), (1,0), (1,1), (2,0). Lower pass: keep (0,0), (1,−1); (1,0): (0,0) → (1,−1) → (1,0) turns left, keep; (1,1): (1,−1) → (1,0) → (1,1) is straight, remove (1,0); (0,0) → (1,−1) → (1,1) turns left, keep; (2,0): (1,−1) → (1,1) → (2,0) turns right, remove (1,1); keep (2,0). Lower chain (0,0), (1,−1), (2,0). The upper pass from the right gives (2,0), (1,1), (0,0). Dropping each chain's last point and joining: (0,0), (1,−1), (2,0), (1,1), counterclockwise. The point (1,0) is inside. Sorting costs O(n log n); each point enters each chain once and leaves at most once, so the passes are O(n).
</details>

<details><summary>P6</summary>

Inside: (b − a) × (p − a) ≥ 0 for every edge a → b. The distance to an edge uses the clamped projection (`distance_to_segment()`). Outside: the nearest point of the polygon lies on its boundary, which is the union of the edges, so the distance is the minimum over the edges. Inside: the nearest point of the complement also lies on the boundary, so the same minimum is the distance to the outside. Convexity is needed only for the inside test. With one foot down the polygon is that foot's rectangle; with no foot there is no support and the margin is −∞ (−1000 over OSC).
</details>

<details><summary>P7</summary>

Gravity's torque about the pivot is m g L sin θ, the moment of inertia m L², so θ'' = (g/L) sin θ ≈ (g/L) θ; with s = L θ, s'' = (g/L) s. With the restoring terms, s'' = −(kp − g/L) s − kd s': the body returns when kp > g/L. With L = 0.961 m (the measured height at the spawn): g/L = 10.21 s⁻², ω = √9.79 = 3.129 s⁻¹, ζ = 4 / 6.258 = 0.639. The response to an impulse v is s(t) = (v/ω_d) e^(−ζωt) sin(ω_d t) with ω_d = ω √(1 − ζ²) = 2.407 s⁻¹; its maximum is at t = atan2(ω_d, ζω)/ω_d = 0.365 s and equals 0.0617 m. `SwayPendulum` at 60 Hz reaches 0.0580 m at 0.350 s: the first step removes kd Δt = 6.7 % of the velocity before the position moves. The offset stays below 1 mm after 2.27 s.
</details>

<details><summary>P8</summary>

In single support, c lies between the two hips, 0.10 m or more beside the stance foot's midline; the stance sole is 0.08 m wide. c is outside. A `FootRig` driven by hand on a flat floor at 3 m/s: in 480 ticks (after a 2 s start), 34 had both feet in contact and c over the polygon; 446 had one foot and c outside (93 %). The margin ranged from −0.236 to +0.065 m, median −0.086 m. Walking is not statically balanced.
</details>

<details><summary>O1</summary>

At the spawn: c 0.961 m above the feet, margin +0.030 m, state stable, a polygon of 6 corners and 0.081 m². On a flat floor (driven by hand) the same stance gives 0.969 m and +0.027 m. c is lower than the rest pose's 0.998 m because the legs are bent: Lesson 12 lowers the pelvis until both feet are in reach. The polygon is not a rectangle because the feet are staggered: at phase 0 the left foot stands where its interrupted swing left it, up to 0.36 m ahead of the rig's origin. The nearest edge is the diagonal at the back that joins the right heel to the left foot.
</details>

<details><summary>O2</summary>

Measured at the spawn with `push_speed` 0.4 m/s: the sway peaks at 0.058 m for each push. Right: smallest margin +0.028 m, stays stable; the nearest edge is the diagonal at the back, not a side edge, and a sideways sway barely changes the distance to it. Forward: +0.028 m, stable. Backward: −0.004 m; the state goes stable → marginal → outside and back. Two pushes to the right: sway 0.116 m, smallest margin +0.026 m, against the right edge. Every sway decays below 1 mm.
</details>

<details><summary>O3</summary>

In the scene, walking uphill from the spawn at full stick for 5 s: 248 of 300 ticks outside, 52 stable, none marginal. The state jumps between outside and stable at each change of support; the margin goes from about +0.06 to about −0.2 m within one tick, with no stop in the marginal band. At a third of the stick (1 m/s, driven by hand), 187 of 480 ticks were stable: the swing arc is lower at a small amount (`step_height` × amount = 0.033 m), and the swing foot spends more of its swing within `contact_tolerance` of the ground, where it counts as support.
</details>

<details><summary>O4</summary>

With the walk cycle, `FootRig` plants nothing, and `foot_in_contact()` decides by its ray test for both feet. Standing at the spawn after 1 s: both soles within 0.02 m of the ground, margin +0.062 m, stable (the walk cycle's rest stance is symmetric, not staggered). Walking 3 s at full stick: of 180 ticks, 4 had both feet in contact, 119 one foot, and 57 none; the states were 118 outside, 5 stable, 57 none. The sine cycle lifts both soles off the ground for a third of the time: the "none" ticks report a body in the air while the capsule walks on the floor. The margin is still the distance from c to the region of the soles that touch the ground; the contacts are what is wrong, not the measure.
</details>

<details><summary>O5</summary>

In the air no foot touches: the polygon is empty, the state is "none", the margin reads "none" on the HUD and −1000 over OSC, and the lines turn gray. Measured by raising the player 1.3 m in a scratch script (after 3 s of walking uphill): 30 ticks of "none", then "outside" with a margin of −0.060 m on the landing tick. On the next ticks both feet count again, but the staggered stance on the slope gives a margin of only +0.008 m. That is below the hysteresis band (0.01 m), so the state stays "outside" while the body stands still: the band of T4 at work, here against the reader's intuition.
</details>

<details><summary>O6</summary>

The state changes at each change of support: 39 changes in 5 s of walking at full stick in the scene, about 8 per second, twice per step (4.29 steps per second, Lesson 12 P8). The stream runs at 30 messages per second. Each `/body/balance` is 44 bytes (`test_13_balance_scene.gd`). Rendered offline (NRT), the tone peaks at 0.052 with a margin of 0.05 m and at 0.16 outside, where the second voice beats at 3 Hz.
</details>

<details><summary>O7</summary>

Headless, mean of 10 000 calls: hull and signed distance of eight points 9.8 µs. `CenterOfMass.compute()` 11.9 µs (mean of 1000). `measure()` 31 µs on the floor box (two feet, one ray for an unplanted foot); `measure_milliseconds` reads 0.06–0.12 ms in the scene. The contact test adds about one ray per tick while a foot is not planted: in the scene, `FootRig.ray_count` reached 742 after 6 s (1 s standing, 5 s walking), against about one ray per tick for `FootRig` alone (Lesson 12 P9).
</details>

<details><summary>T1</summary>

Only the planted foot counts. At the spawn the polygon is the right sole alone (4 corners) and c, between the hips, lies outside it: margin −0.061 m, state outside, while the body stands still. The rule that no longer applies is the second one, a foot near the ground counts. The first version of `BalanceMonitor` had only the first rule, and this is what it measured.
</details>

<details><summary>T2</summary>

g/L = 10.21 s⁻² at the spawn. kp = 5: the restoring push is weaker than gravity; after a 0.4 m/s push the sway reaches the 0.3 m limit after 1.52 s and stays there. kp = 10, just below g/L: the push is damped first and the sway then creeps outward; 0.25 m after 20 s. Without a push nothing moves: s = 0 is an equilibrium, an unstable one, and the simulation starts exactly on it.
</details>

<details><summary>T3</summary>

kd = 0: the amplitude is 0.1279 m in the first and in the last two of ten seconds; v/ω = 0.4 / 3.129 = 0.1278 m. Semi-implicit Euler keeps the energy of the undamped oscillator bounded. With the lines swapped (explicit Euler), the energy grows by a factor 5.10 in 10 s at 60 Hz (measured on the undamped equation): the sway grows until it hits the 0.3 m limit.
</details>

<details><summary>T4</summary>

No difference while walking: 39 changes in 5 s with h = 0.01 m and 39 with h = 0. The margin jumps across both thresholds within one tick (O3), so it never lingers in a band. The band matters for a slow motion through a threshold: a body that leans slowly to the edge, or (Lesson 14) a weight shift held by a trigger near the edge. It also keeps a state that is no longer true: O5.
</details>

<details><summary>T5</summary>

The sum becomes 1.103; c of the rest pose rises from 0.99844 to 1.01353 m, by 0.015 m. See P2.
</details>

<details><summary>T6</summary>

`/body/balance/state` still goes out on every change of state; the stream `/body/balance` stops. The same split as `/player/state` and `/player/ground` in Lesson 04.
</details>
