class_name StickResponse
extends Resource
## Turns a raw stick vector into a shaped stick vector: a radial deadzone,
## an outer saturation radius, and a response curve for the magnitude.
##
## Relationships:
##   Input.get_vector(..., 0.0)  -> raw stick, length 0 to 1, no deadzone
##   StickResponse (this file)   -> shaped stick, length 0 to 1
##   Player (src/player/player.gd) multiplies the shaped stick by walk_speed
##
## The values live in a .tres file under game/data/input/, so the feel of
## the stick can be tuned in the Inspector without editing code.
##
## The mapping acts on the magnitude m = |raw| alone and keeps the
## direction raw / |raw|:
##
##   output magnitude
##   1 |                    ________
##     |                 _-'
##     |              _-'           exponent > 1: slow start, fine control
##     |          _--'              near the center of the stick
##     |   ___---'
##   0 |__|___________________|_____  m (raw magnitude)
##      0  inner              outer  1
##
## Lesson 00 used Godot's built-in mapping: inner = 0.15 (the action
## deadzone), outer = 1.0, exponent = 1.0. With those values this resource
## reproduces it; game/tests/test_02_stick_response.gd checks that claim.

## Raw magnitudes at or below this value produce zero output.
@export_range(0.0, 0.5, 0.01) var inner_deadzone: float = 0.15
## Raw magnitude at which the output reaches 1. Values above it saturate.
@export_range(0.5, 1.0, 0.01) var outer_deadzone: float = 1.0
## Power applied to the normalized magnitude. 1 is linear.
@export_range(0.25, 4.0, 0.05) var exponent: float = 1.0
## Optional. When set, replaces the power law: the curve maps the
## normalized magnitude t in [0, 1] to the output magnitude in [0, 1].
@export var curve: Curve


func apply(raw: Vector2) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= inner_deadzone:
		return Vector2.ZERO
	return raw / magnitude * shape(magnitude)


## Output magnitude for a raw magnitude m, both in [0, 1].
##
## Q: Why rescale with inverse_lerp before applying the curve?
## A: Without it the output would jump from 0 to inner_deadzone ^ exponent
##    at the edge of the deadzone. Rescaling maps [inner, outer] onto
##    [0, 1], so the output starts at 0 where the deadzone ends.
func shape(magnitude: float) -> float:
	if magnitude <= inner_deadzone:
		return 0.0
	var t := clampf(inverse_lerp(inner_deadzone, outer_deadzone, magnitude), 0.0, 1.0)
	if curve:
		return clampf(curve.sample(t), 0.0, 1.0)
	return pow(t, exponent)
