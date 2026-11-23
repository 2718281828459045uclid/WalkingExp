# 0014. Analog weight shift: triggers to rig offset through exact filters

Status: accepted, 2026-11-22 (Lesson 14).

## Context

Lesson 13 measured static balance and moved the body only by pushes. Phase 4 calls for balance that answers analog input. Four questions needed an answer: how the triggers are read, where the weight shift enters the body, how a stepped input (a key) becomes a plausible motion, and how to keep the result independent of the physics tick rate, which Lesson 02 already made switchable.

## Decision

1. **Triggers are input actions with deadzone 0.** `shift_weight_left` and `shift_weight_right` each hold a key (5, 6) and a trigger axis (`JOY_AXIS_TRIGGER_LEFT`, `JOY_AXIS_TRIGGER_RIGHT`). `StanceController` reads `Input.get_action_raw_strength()`. The InputMap does no shaping; a `TriggerResponse` resource (`data/input/trigger_response.tres`, with a `Curve`) does, as `StickResponse` does for the stick (decision 0004: values in `.tres` files).
2. **The shift moves the rig, after the sway.** A new node runs at the same priority as `BalanceMonitor` (−1) and later in the tree. The monitor sets `rig.position = rest + sway`; the controller adds the shift and the crouch. No Lesson 13 code changes. The planted feet stay in world space and the IK of Lesson 12 bends the legs, as for a push.
3. **Smoothing is solved exactly over a tick.** The one-pole filter uses a = 1 − e^(−dt/τ); the critically damped spring uses the closed form (c₁ + c₂ t) e^(−ωt). Both give the same values at 30, 60, 120 and 240 Hz. A semi-implicit Euler spring is kept as a selectable comparison (key 7).
4. **The crouch is a rig offset with the same smoothing.** It lowers the rig by `crouch_depth`; the trunk does not tilt.
5. **The axial deadzone is a subclass.** `AxialStickResponse` extends `StickResponse` and overrides `apply()`; the radial response of Lesson 02 is unchanged and remains the default.

## Consequences

- The capsule, the camera and the collision do not see the shift or the crouch.
- `StanceController` depends on the monitor resetting the rig each tick; without it the offsets accumulate.
- Lesson 13's `center_height` is measured in the rig's frame and rises when the rig lowers (0.961 → 1.041 m at full crouch); the HUD shows the height above the soles instead (0.924 → 0.755 m).
- The Euler spring becomes unstable above ω dt = 2(√2 − 1) = 0.828 (49.7 rad/s at 60 Hz, 99.4 rad/s at 120 Hz); the exact step has no limit.
- The crouch depth is bounded by `FootRig.ray_up` (0.6 m), not by the legs: deeper than about 0.5 m an unplanted foot's landing ray starts below uphill ground.
- One controller tick costs about 2.5 µs (read, shape, filter).
