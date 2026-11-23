class_name GaitClock
extends RefCounted
## Turns distance walked into footstep events (Lesson 05).
##
## The capsule has no legs, so it has no real foot contacts. This clock
## invents them: a gait phase that grows by one for every step length the
## body travels on the ground. Each time the phase passes a whole number,
## one foot strikes the ground. Feet alternate: left, right, left, ...
##
##   phase   0.0        1.0        2.0        3.0
##           |----------|----------|----------|---->  distance / step_length
##                      L          R          L       foot strikes
##
## src/audio/footstep_reporter.gd calls advance() once per physics tick.
## tests/test_05_gait_clock.gd checks the counts and the timing.

## Meters covered by one step (one foot to the other).
var step_length: float = 0.75

## Phase in steps. The fractional part is the progress of the current step.
var phase: float = 0.0

## Foot of the next strike: 0 left, 1 right.
var next_foot: int = 0

## Set by advance(): fraction of the tick, from 0 (start) to 1 (end), at
## which the strike happened. Only meaningful when advance() returned true.
var strike_fraction: float = 1.0


func _init(meters_per_step: float = 0.75) -> void:
	step_length = meters_per_step


## Advances the phase by a distance in meters. Returns true if a foot
## struck during this advance; strike_fraction then tells when.
##
## At most one strike per call: a tick of 1/30 s at 3 m/s covers 0.1 m,
## far less than one step. A larger jump (teleport) gives one strike and
## drops the rest, as RateClock (Lesson 04) drops a backlog.
func advance(distance: float) -> bool:
	if distance <= 0.0 or step_length <= 0.0:
		return false
	var before := phase
	var after := phase + distance / step_length
	phase = after
	# Q: Did the phase pass a whole number during this advance?
	# A: Compare the integer parts. floor(0.9) = 0 and floor(1.05) = 1
	#    differ, so a strike happened somewhere in between.
	var boundary := floorf(after)
	if boundary <= floorf(before):
		return false

	# Q: Where inside the tick did the phase reach the boundary?
	# A: The phase grows linearly during the tick, from "before" to
	#    "after". Solve before + f * (after - before) = boundary for f:
	#      f = (boundary - before) / (after - before)
	#    f = 0 means at the start of the tick, f = 1 at its end. This is
	#    linear interpolation run backwards (an inverse lerp).
	strike_fraction = clampf((boundary - before) / (after - before), 0.0, 1.0)
	if after - boundary >= 1.0:
		phase = boundary + fmod(after - boundary, 1.0)
	next_foot = 1 - next_foot
	return true


## The foot that struck on the last true advance(): 0 left, 1 right.
func last_foot() -> int:
	return 1 - next_foot
