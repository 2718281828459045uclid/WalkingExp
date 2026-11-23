# 0002. Character model: kinematic body, procedural pose, explicit balance state

Status: accepted, 2026-11-22.

## Context

`plan.md` calls for walking, crawling, climbing, and balancing, with analog control finer than the trigger input of the reference game, and with balance as the main activity of play.

Three architectures were considered.

**A. Keyframed animation with IK correction.** Authored or motion-captured clips drive the skeleton. IK adjusts feet and hands to the terrain. Standard in commercial titles. Requires a library of authored animation.

**B. Physics-driven body (active ragdoll).** The skeleton is a chain of rigid bodies joined by motors. A controller computes joint torques to keep the body upright. Reactions to terrain emerge from the simulation. Difficult to tune and debug; the common failure is the body falling over.

**C. Kinematic body, procedural pose, explicit balance model.** A capsule (`CharacterBody3D`) handles collision with the world. The pose is computed each frame: raycasts find foot targets on the ground, a two-bone IK solver bends each leg, and the pelvis is placed relative to the supporting feet. Balance is a quantity computed from geometry: the center of mass, projected onto the ground, compared with the support polygon (the convex hull of the contact points). Analog input shifts the center of mass; slope, step height, and speed disturb it.

## Decision

Architecture C, built in stages:

1. Capsule walker (present in the sandbox).
2. Skeleton assembled in code from bones and capsule meshes. No modeled character is required.
3. Foot placement by raycast and two-bone IK. A hand-written solver (law of cosines) comes first; `TwoBoneIK3D` replaces it once the math is understood.
4. Balance model: support polygon, projected center of mass, and a damped inverted pendulum for disturbances. Balance margin = signed distance from the projected center of mass to the polygon boundary.
5. Stances: standing, crouched, crawling (four contacts), climbing (hands and feet on holds). Each stance changes the contact set and therefore the support polygon.
6. Climbing holds found by geometric queries on terrain and SDF rocks: surface normal, curvature, local concavity.

Architecture B remains available as a contained experiment, for example arms that reach with physical springs.

## Consequences

- No dependency on authored animation. Motion quality depends on the procedural rules and their tuning.
- Balance becomes a number the game can display, send to SuperCollider, and use for failure states (stumble, fall).
- The required math (IK, convex hulls, point-to-polygon distance, pendulum dynamics) maps onto Phase 4 lessons.
- The physics tick rate may need to rise from 60 Hz to 120 Hz for fine analog response. To be measured in Lesson 14.
