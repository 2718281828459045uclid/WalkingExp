class_name ListenerMath
extends RefCounted
## Listener-relative coordinates for spatial audio (Lesson 06).
## Static functions; spatial_audio_reporter.gd calls them every send.
##
## The listener is a Node3D (the camera, or the head). Its transform maps
## listener space to world space. Godot's convention for a camera:
##   -Z   ahead        +X   right        +Y   up
##
## A point is described by three numbers relative to the listener:
##
##             ahead (-Z)
##                 |   . point
##                 |  /
##                 |az/        azimuth   az: angle from "ahead", measured
##                 | /                   in the horizontal plane, positive
##   left ---------L--------- right (+X) to the right (clockwise seen from
##                 |                     above), in (-PI, PI]
##                 |           elevation el: angle above the horizontal
##               behind                  plane, in [-PI/2, PI/2]
##                                       distance: meters
##
## SuperCollider's PanAz and PanB use the same direction of rotation, so
## the azimuth goes to SuperCollider unchanged (divided by PI there).


## The point in the listener's own frame: x right, y up, -z ahead.
static func to_listener_space(listener: Transform3D, point: Vector3) -> Vector3:
	# Q: Why affine_inverse() and not inverse()?
	# A: inverse() assumes the basis is a pure rotation. affine_inverse()
	#    also undoes scale. A camera has no scale, but the listener may be
	#    any Node3D, and the cost of the general version is small.
	return listener.affine_inverse() * point


## Azimuth (radians), elevation (radians), distance (meters) of a point
## given in listener space. A point at the listener returns zeros.
static func spherical(local: Vector3) -> Vector3:
	var distance := local.length()
	if distance < 1e-6:
		return Vector3.ZERO
	# Q: Why atan2(x, -z) and not atan2(z, x) as in a math textbook?
	# A: atan2(a, b) is the angle of the vector (b, a) measured from the
	#    b axis toward the a axis. Here the reference direction is
	#    "ahead" (-z), and the angle grows toward "right" (+x). So -z
	#    takes the place of the textbook's x, and x the place of y.
	var azimuth := atan2(local.x, -local.z)
	var horizontal := Vector2(local.x, local.z).length()
	# Q: What is the azimuth of a point straight overhead?
	# A: Any value describes it, as the longitude of the North Pole does.
	#    atan2 still returns a number, and which number depends on the
	#    sign of a zero: atan2(0, -0) is PI. The function returns 0 so
	#    that the result does not depend on rounding.
	if horizontal < 1e-6:
		azimuth = 0.0
	# Q: Why atan2 for the elevation, when asin(y / distance) also works?
	# A: Both give the same angle. asin needs the division first, and
	#    y / distance can round to slightly above 1 for a point straight
	#    overhead, where asin returns NaN. atan2 has no such edge.
	var elevation := atan2(local.y, horizontal)
	return Vector3(azimuth, elevation, distance)


## Azimuth, elevation, distance of a world-space point as seen from the
## listener.
static func spherical_from(listener: Transform3D, point: Vector3) -> Vector3:
	return spherical(to_listener_space(listener, point))


## Azimuth of a world-space direction (not a point) as seen from the
## listener. Used for the wind, whose source is "far away in direction d".
static func direction_azimuth(listener: Transform3D, direction: Vector3) -> float:
	# Q: Why the basis only, and not the whole transform?
	# A: A direction has no position. Moving the listener does not change
	#    where the wind comes from; turning the listener does. The basis
	#    holds the turning, the origin holds the moving.
	var local := listener.basis.inverse() * direction
	return atan2(local.x, -local.z)


## Returns the angle equal to `angle` modulo 2 PI that lies closest to
## `previous`. A sequence of angles passed through this function never
## jumps by more than PI between neighbors.
static func unwrap_angle(previous: float, angle: float) -> float:
	# Q: What goes wrong without unwrapping?
	# A: A source passing behind the listener goes from +179 degrees to
	#    -179 degrees: 2 degrees of motion, but 358 degrees of change in
	#    the number. SuperCollider smooths the number with Lag, so the
	#    sound would sweep around the front of the listener. Unwrapped, the
	#    number goes from 179 to 181 degrees, and PanAz, whose position is
	#    periodic, places 181 degrees where -179 degrees is.
	return previous + wrapf(angle - previous, -PI, PI)
