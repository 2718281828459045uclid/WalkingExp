# 0012. Foot placement: phase-timed steps, raycast targets, hand-written IK by default

Status: accepted, 2026-11-22 (Lesson 12).

## Context

Decision 0002, stage 3, calls for foot placement by raycast and two-bone IK, a hand-written solver first and `TwoBoneIK3D` later. Lesson 11 left a body whose legs follow a sine cycle: the stance foot slides (mean 1.37 m/s at 3 m/s walking) and the soles ignore the ground. Lesson 05 sends footsteps from a distance clock (`GaitClock`, 0.75 m) that does not agree with the visible steps (0.70 m).

Three questions needed an answer: what decides when a foot steps, where the IK runs, and where footstep events come from.

## Decision

1. **Steps are timed by the walk phase.** `FootRig` (a subclass of `BodyRig`) keeps Lesson 11's phase, advanced by distance. The left foot swings for φ ∈ (−0.25, 0.25), the right for (0.25, 0.75), as in `WalkCycle`. A swing foot travels to a target found by one vertical ray a quarter stride ahead of its hip; at the heel-strike phase it is planted in world space and stays there through the stance. The alternative, steps triggered when a foot strays too far from its home point, handles turning on the spot but needs its own timing rules; it is left to exercises.
2. **The pelvis follows the feet.** After the targets are known, the hips are lowered until every target lies within 0.98 of the leg length; the pelvis never rises above the walk cycle's height and drops at most 0.35 m.
3. **The hand-written solver is the default.** `TwoBoneIk` (static) solves each leg and returns joint positions; `FootRig` converts them to local quaternions and orients the foot to the ground normal. `TwoBoneIK3D` is kept as a switchable alternative on the same targets and poles. It writes the thigh and shin during the skeleton's update and leaves the foot's local rotation; its result is visible only inside `Skeleton3D.skeleton_updated`, after which the skeleton restores the unmodified pose.
4. **Footsteps come from plants.** `FootRig` emits `foot_planted(side, point, normal, tick_fraction)`. `PlantFootstepReporter` (a subclass of `FootstepReporter`) sends the Lesson 05 message from it, with the surface and slope at the contact and the sub-tick strike time. The message format and the SuperCollider patch are unchanged.

## Consequences

- Stance feet stand still on the ground (measured drift below 2e-5 m/s), and sound and picture share one clock.
- A body that turns without moving does not step; a body that stops mid-swing leaves one foot where the interpolation stood.
- Code that reads bone poses outside `skeleton_updated` sees the pose `FootRig` wrote, not the pose `TwoBoneIK3D` produced. The HUD's ankle error for `TwoBoneIK3D` is therefore read inside that callback.
- One ray per swinging foot per tick: the cost is about 0.12 ms per tick for the whole update in a headless run.
- Lesson 13 can read the plants (`FootRig.feet`) as the contact set of the support polygon.
