class_name OnePoleFilter
extends RefCounted
## A one-pole low-pass filter on a Vector2 (Lesson 14).
##
## The continuous filter is the first-order equation
##   dy/dt = (x - y) / tau
## with time constant tau, in seconds. For an input x held constant over
## a tick of length dt, its exact solution is
##   y(t + dt) = x + (y(t) - x) exp(-dt / tau)
##             = y(t) + a (x - y(t)),   a = 1 - exp(-dt / tau)
## This is Lesson 02's blend_factor() with rate k = 1 / tau. In audio terms
## it is the one-pole low-pass (SuperCollider's OnePole, Lag): a step
## input reaches 63 % of its height after tau seconds, and the cutoff
## frequency is 1 / (2 pi tau).

## Time constant, in seconds. 0 passes the input through.
var time_constant := 0.12
var value := Vector2.ZERO


func _init(tau: float = 0.12) -> void:
	time_constant = tau


## The blend factor of one tick.
##
## Q: Why not dt / tau?
## A: dt / tau is one explicit Euler step of the equation. It depends on
##    the tick rate, and above dt = tau it overshoots (above 2 tau it
##    oscillates). 1 - exp(-dt / tau) stays in [0, 1) and gives the same
##    curve at 60 and at 120 ticks per second.
static func blend(delta: float, tau: float) -> float:
	if tau <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / tau)


## Advances the filter by delta seconds toward the input and returns the output.
func step(input: Vector2, delta: float) -> Vector2:
	value += (input - value) * blend(delta, time_constant)
	return value


func reset(to: Vector2 = Vector2.ZERO) -> void:
	value = to
