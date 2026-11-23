# 0013. Static balance: a margin from the center of mass and the support polygon

Status: accepted, 2026-11-22 (Lesson 13).

## Context

Lesson 12 placed the feet on the ground and the pelvis above them. Phase 4 calls for a body that balances, and the audio side needs a continuous quantity that says how close the body is to falling. Three questions needed an answer: what the measure of balance is, which feet count as support, and how a disturbance enters the body without a physics simulation of the skeleton.

## Decision

1. **The measure is static.** The balance margin is the signed distance from the vertical projection of the whole-body center of mass to the convex hull of the soles in contact, positive inside. The center of mass comes from Winter's segment table (Table 4.1), kept in a `SegmentMasses` resource (`data/body/winter_segment_masses.tres`) and evaluated on the bone poses. The hull is Andrew's monotone chain on ground coordinates (x, −z). Velocity enters nowhere; a dynamic measure (the capture point) is left to Lesson 13 E5 (and Lesson 14 E7, which builds on it).
2. **Contact is planted or near.** A foot counts when `FootRig` holds it planted, or when its lowest sole corner lies within 0.02 m of the ground under it (one ray). Planted alone would report a standing body as falling: at rest the phase stops wherever the walk left it, often in one foot's swing, and that foot stands on the ground without being planted.
3. **A separate node, before the player.** `BalanceMonitor` reads the `FootRig` of the player; no earlier class changes. It runs with `process_physics_priority = -1`, so it measures the pose of the previous tick (the pose on the screen) and sets the sway before the rig solves this tick's legs.
4. **Pushes move the rig, not the capsule.** A damped, linearized inverted pendulum (`SwayPendulum`: s'' = (g/L − kp) s − kd s') turns a push into a horizontal offset of the rig inside `BodyMesh`. The planted feet stay in world space and the IK of Lesson 12 bends the legs. The capsule and the physics do not see the lean.
5. **A state machine with hysteresis.** Four states (none, stable, marginal, outside), thresholds at 0 and 0.015 m, a band of 0.01 m. OSC: `/body/balance margin state x z height` at 30 Hz and `/body/balance/state name` on change.

## Consequences

- While walking, the center of mass lies outside the support polygon on 93 % of the ticks (3 m/s, flat floor, driven by hand): the margin describes standing, not walking.
- The contact tolerance counts a low swing foot as support: at 1 m/s, 39 % of the walking ticks are reported stable, against 7 % at 3 m/s.
- The contact test adds about one ray per tick while a foot is unplanted.
- With the `TwoBoneIK3D` solver the monitor reads the pose before the modifier (decision 0012), so the leg segments use the walk cycle's angles; with the walk-cycle solver nothing is planted and the ray test decides alone.
- A push never causes a step, and a sway past the edge never causes a fall; both are exercises (E4) and later lessons.
- Hysteresis can keep a state that the margin no longer supports (a landing at +0.008 m stays "outside").
