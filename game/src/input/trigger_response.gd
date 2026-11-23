class_name TriggerResponse
extends Resource
## Turns a raw trigger value into a shaped one (Lesson 14).
##
## Relationships:
##   Input.get_action_raw_strength()   raw trigger, 0 to 1 (action deadzone 0)
##   TriggerResponse (this file)       shaped trigger, 0 to 1
##   StanceController (src/body/stance_controller.gd) turns the two shaped
##   triggers into a sideways weight shift
##
## A trigger is one axis that rests at 0, so the deadzone has one edge, not
## a circle: the 1D case of StickResponse (Lesson 02). The outer deadzone
## matters more here than on a stick: many triggers stop short of 1.0 at
## full travel, and without a saturation radius the full weight shift
## would be out of reach.
##
##   output
##   1 |                 ______
##     |              _-'
##     |          _-'          the Curve resource sets the shape between
##     |      _-'              the two edges
##   0 |_____'_______________|__  raw
##      0  inner           outer 1

## Raw values at or below this produce zero output.
@export_range(0.0, 0.5, 0.01) var inner_deadzone: float = 0.05
## Raw value at which the output reaches 1.
@export_range(0.5, 1.0, 0.01) var outer_deadzone: float = 0.95
## Maps the normalized value t in [0, 1] to the output in [0, 1].
## Empty: the output is t (linear).
@export var curve: Curve


## Output for a raw trigger value in [0, 1].
##
## Q: Why the same inverse_lerp as StickResponse.shape()?
## A: It maps [inner, outer] onto [0, 1], so the output leaves 0 at the
##    edge of the deadzone without a jump, and reaches 1 at the outer edge.
func apply(raw: float) -> float:
	if raw <= inner_deadzone:
		return 0.0
	var t := clampf(inverse_lerp(inner_deadzone, outer_deadzone, raw), 0.0, 1.0)
	if curve:
		return clampf(curve.sample(t), 0.0, 1.0)
	return t
