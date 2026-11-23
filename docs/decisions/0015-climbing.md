# 0015. Climbing: holds from field curvature, pelvis from reach spheres, a kinematic body

Status: accepted, 2026-11-22 (Lesson 15).

## Context

Phase 4 calls for a body that climbs a boulder face. Four questions needed an answer: where the holds come from, how four limbs and a pelvis are placed when each limb has a hold, which inverse kinematics turns the limbs, and what the physics capsule does while the body hangs on the rock. Lessons 07–09 supply rocks as signed distance fields with per-vertex normals and curvature; Lesson 12 supplies a two-bone solver; Lessons 13 and 14 supply the center of mass, the support polygon and the trigger inputs.

## Decision

1. **Holds are found on the mesh vertices and refined on the field.** `HoldFinder` tests the per-vertex mean curvature H and gradient normal n that `CurvatureMesher` (Lesson 09) already computes: 3 ≤ H ≤ 40 /m, n · up ≥ 0.3, n · face ≥ 0.2. Non-maximum suppression keeps one candidate per 0.2 m, best score H (n · up) first. Each survivor is moved onto the zero set by two Newton steps along ∇f and measured again with `ImplicitCurvature.sample()`; a hold whose |∇f| is below 0.5 (a crease of a union or intersection) is dropped. The principal curvatures classify a hold as a knob (k₂ ≥ 0.25 k₁) or an edge. The search runs after each rebuild and after any threshold change, without re-meshing.
2. **The rock is a `CurvatureMesher` subclass.** `ClimbableRock` adds the thresholds, the hold list in shape space and in world space, the top-out test (a sphere-traced ray down from behind the hold must land on a flat top within 0.25 m of its height) and the hold markers. The search runs in shape space; the world list leaves out holds less than 0.05 m above an optional `ground` (a `Terrain`), because the rock stands in a slope and part of its surface lies in the ground. One climbing face per rock, given by an exported outward normal.
3. **The pelvis is a point in an intersection of balls.** Each limb that holds, or travels to a hold, constrains the pelvis to a ball of radius 0.98 × limb length around (hold target − joint offset). A half-space keeps the pelvis in front of the face. `ReachSolver` finds a point of the intersection by cyclic projections, started at a preferred pelvis (hanging below the hands, standing above the feet, or drawn toward a reaching hand). The pelvis follows that point with a one-pole filter and is projected into the set once more, so every holding limb is in reach on every tick.
4. **Each limb is solved alone.** The legs use `TwoBoneIk` (Lesson 12) with a pole toward the face and outward. The arms use `TwoBoneIk` or `Fabrik` (an own implementation of Aristidou and Lasenby 2011, warm-started from the last pose), switchable at run time. The engine's `FABRIK3D` is not used: Lesson 12 found that `SkeletonModifier3D` results are visible only inside `skeleton_updated`, and the balance monitor reads the pose outside it.
5. **One limb moves at a time.** A trigger starts a hand's reach; the stick moves the hand at a set speed through a critically damped spring (Lesson 14); releasing the trigger grabs the hold nearest the hand within 0.3 m, or returns to the old hold. The feet move by themselves when no hand moves, to the highest hold that keeps all four balls intersecting.
6. **The capsule is kinematic while climbing.** `ClimbingPlayer` (a `BodyPlayer` subclass) skips walking, gravity and `move_and_slide()` while `climbing` is true; `ClimbController` sets its position under the pelvis. A mantle moves the capsule onto the top along two overlapping eased ramps; letting go moves it 0.45 m clear of the face and returns it to physics.
7. **Balance on the wall is a moment ratio.** `ClimbBalanceMonitor` (a `BalanceMonitor` subclass) builds the support polygon from all held contacts and reports F/W = d/h, the horizontal hand pull per body weight from the moments about the line of the feet.

## Consequences

- No Lesson 07–14 scene file changes. The Lesson 15 scene swaps the player scene and the balance monitor script and adds two nodes. The run/main_scene check moved from `test_14_stance_scene.gd` to `test_15_climb_scene.gd`.
- One Lesson 14 source line changed, with the input map: an earlier edit had rebound Lesson 02's `cycle_tick_rate` (T, D-pad up) to key 9 alone. `cycle_tick_rate` has T and D-pad up again, and the Lesson 14 tick-rate key 9 is its own action, `cycle_stance_tick_rate`, read by `analog_stances.gd` (the Lesson 14 README changed with it). D-pad up carries both `cycle_tick_rate` and `toggle_crouch`; no scene reads both.
- Holds exist only where the mesh has a vertex near a curvature peak; features smaller than the cell (0.08 m on the climbing face) are missed. The hold search costs about 12 ms; meshing and curvature of the face about 1.25 s at load.
- Sharp convex edges are not holds at the edge itself (H above 40 /m there) but can produce holds within one curvature step (0.01 m) of it, where the measured H falls through the allowed range.
- The capsule does not collide while climbing; nothing stops the body from passing through other geometry between the holds.
- The climb has no dynamics: no momentum, no fall from a lost grip, no grip force. The hand pull is reported, not enforced.
- The rock must stand upright (rotation about +y only, scale 1), because the hold tests compare shape-space normals with +y.
- A change of thresholds during a climb leaves the limbs on holds of the previous search.
