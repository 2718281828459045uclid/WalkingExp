class_name SwayPendulum
extends RefCounted
## A linearized inverted pendulum held upright by a spring and a damper
## (Lesson 13). It models the horizontal sway of the center of mass over
## the feet after a push.
##
## The body is a point mass at height L above the ankles. Leaning by a
## horizontal offset s, gravity pulls it farther over with acceleration
## (g / L) s (small angles: sin(theta) = s / L). The ankles and hips push
## back like a spring of stiffness kp and a damper kd (per unit mass):
##
##   s'' = (g / L) s - kp s - kd s'
##       = -(kp - g / L) s - kd s'
##
## With kp > g / L this is a damped oscillator with
##   natural frequency   w = sqrt(kp - g / L)
##   damping ratio       zeta = kd / (2 w)
## With kp < g / L the "spring" is negative and s grows without bound:
## the body falls.
##
## s is a Vector2 in the body's own ground frame: x to the right, y
## forward. A push adds to the velocity at once (an impulse).

var gravity := 9.81
## Height of the center of mass above the ankles, in meters.
var height := 1.0
## Stiffness of the restoring push, in 1/s^2.
var stiffness := 20.0
## Damping, in 1/s.
var damping := 4.0
## Largest offset, in meters. The state is clamped to it.
var max_offset := 0.3

var offset := Vector2.ZERO
var velocity := Vector2.ZERO


## Adds a velocity change, in m/s.
func push(delta_velocity: Vector2) -> void:
	velocity += delta_velocity


## Advances the state by delta seconds.
func step(delta: float) -> void:
	# Q: Why update the velocity first and then use the new velocity for
	#    the position (semi-implicit Euler)?
	# A: Plain Euler, which moves the position with the old velocity, adds
	#    energy to an oscillator every step: the sway would grow even with
	#    a little damping. Semi-implicit Euler keeps the energy of an
	#    undamped oscillator bounded, at the same cost.
	var acceleration := offset * (gravity / height - stiffness) - velocity * damping
	velocity += acceleration * delta
	offset += velocity * delta
	if offset.length() > max_offset:
		offset = offset.limit_length(max_offset)
		# At the limit, the motion away from the center stops.
		var outward := offset.normalized()
		var away := velocity.dot(outward)
		if away > 0.0:
			velocity -= outward * away


## sqrt(kp - g / L); 0 when the pendulum is unstable.
func natural_frequency() -> float:
	return sqrt(maxf(stiffness - gravity / height, 0.0))


## kd / (2 w); INF when the pendulum is unstable.
func damping_ratio() -> float:
	var w := natural_frequency()
	return damping / (2.0 * w) if w > 0.0 else INF
