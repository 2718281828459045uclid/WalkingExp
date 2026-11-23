class_name CriticalSpring
extends RefCounted
## A critically damped spring on a Vector2 (Lesson 14).
##
## The value x follows a target x* like a mass on a spring with a damper:
##   x'' = -w^2 (x - x*) - 2 w x'
## With the damping 2 w (damping ratio 1) the spring is critically damped:
## the fastest approach that does not overshoot for a step of the target.
## w, in radians per second, sets the speed; the response to a step is
##   e(t) = e0 (1 + w t) exp(-w t),   e = x - x*,
## which has fallen to 5 % after about 4.74 / w seconds.
##
## Compared with OnePoleFilter: the one-pole output starts to move at full
## speed the instant the input steps; the spring starts with velocity 0
## and accelerates. The output of the spring has a continuous velocity,
## the output of the one-pole has a corner. A body moving its weight looks
## like the spring.

## Angular frequency w, in radians per second.
var frequency := 12.0
var value := Vector2.ZERO
var velocity := Vector2.ZERO


func _init(w: float = 12.0) -> void:
	frequency = w


## Advances by delta seconds with the exact solution and returns the value.
##
## Q: What is the exact solution over one tick, with the target held still?
## A: The equation for e = x - x* has the double root -w, so
##      e(t) = (c1 + c2 t) exp(-w t).
##    At t = 0, e = e0 gives c1 = e0, and e' = v0 gives c2 = v0 + w e0.
##    Differentiating:
##      v(t) = (v0 - w (v0 + w e0) t) exp(-w t).
##    Both lines are evaluated at t = delta. No step size enters except
##    through exp(), so the result does not depend on the tick rate.
func step(target: Vector2, delta: float) -> Vector2:
	var e0 := value - target
	var c2 := velocity + e0 * frequency
	var decay := exp(-frequency * delta)
	value = target + (e0 + c2 * delta) * decay
	velocity = (velocity - c2 * (frequency * delta)) * decay
	return value


## The same spring stepped with semi-implicit Euler (Lesson 13's method),
## for comparison. The result depends on delta.
func step_euler(target: Vector2, delta: float) -> Vector2:
	var acceleration := (target - value) * (frequency * frequency) - velocity * (2.0 * frequency)
	velocity += acceleration * delta
	value += velocity * delta
	return value


func reset(to: Vector2 = Vector2.ZERO) -> void:
	value = to
	velocity = Vector2.ZERO
