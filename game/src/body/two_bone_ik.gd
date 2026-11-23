class_name TwoBoneIk
extends RefCounted
## A two-bone inverse kinematics solver written out by hand (Lesson 12).
##
## How the files relate:
##   FootRig (src/body/foot_rig.gd) calls solve() once per leg per tick,
##   then leg_bases() and foot_basis() to turn the joint positions into
##   bone rotations. Godot's TwoBoneIK3D solves the same problem; FootRig
##   can switch to it for comparison (Lesson 12, section 3.4).
##
## The problem: a chain root -> middle -> end with bone lengths a (root to
## middle) and b (middle to end). Given the root position and a target for
## the end, find the middle joint. For a leg: hip, knee, ankle.
##
##            root (hip)
##             |\
##           a |α\ d
##             |  \
##      middle o   \
##      (knee)  \   \
##             b \   \
##                \   \
##                 end = target (ankle)
##
## Three lengths a, b, d fix the triangle (law of cosines). The triangle
## may still turn about the line root -> target; the pole picks the
## turn: the middle joint lies in the half plane that contains the pole.

## The result of one solve. All points in the caller's frame.
class Solution:
	var root := Vector3.ZERO
	var middle := Vector3.ZERO
	## Where the end joint lands. Equal to the target when reached.
	var end := Vector3.ZERO
	## False when the target was out of reach (too far or too close).
	var reached := true
	## Angle at the root between the bone a and the line to the end, radians.
	var root_angle := 0.0
	## Interior angle at the middle joint, radians. PI is a straight chain.
	var middle_angle := PI


## Smallest margin kept from a fully straight or fully folded chain, m.
const STRAIGHT_MARGIN := 1e-4


## Solves the chain root -> middle -> end for the given target and pole.
static func solve(root: Vector3, target: Vector3, pole: Vector3, a: float, b: float) -> Solution:
	var solution := Solution.new()
	solution.root = root
	var to_target := target - root
	var distance := to_target.length()

	# Q: Which distances can the end joint reach?
	# A: The triangle inequality: |a - b| <= d <= a + b. Outside that
	#    interval no triangle with sides a, b, d exists. The solver clamps d
	#    and points the chain at the target as far as it goes.
	var d := clampf(distance, absf(a - b) + STRAIGHT_MARGIN, a + b - STRAIGHT_MARGIN)
	solution.reached = absf(d - distance) < 2.0 * STRAIGHT_MARGIN

	# Q: What if the target sits on the root?
	# A: There is no direction to the target. Any direction would do; the
	#    solver hangs the chain straight down, as a leg at rest.
	var u := Vector3.DOWN
	if distance > 1e-6:
		u = to_target / distance

	# Q: Where does the pole enter?
	# A: Only through its component perpendicular to u. The knee leaves the
	#    line hip -> ankle in that direction. Subtracting the projection on
	#    u is one step of Gram-Schmidt.
	var v := (pole - root) - (pole - root).dot(u) * u
	if v.length() < 1e-6:
		# The pole lies on the line: the bend plane is undefined. Any
		# perpendicular works; this one is stable for u near vertical.
		v = u.cross(Vector3.RIGHT)
		if v.length() < 1e-6:
			v = u.cross(Vector3.FORWARD)
	v = v.normalized()

	# Q: Which formula gives the angle at the root?
	# A: The law of cosines for the side b, opposite the root:
	#      b^2 = a^2 + d^2 - 2 a d cos(alpha)
	#    so cos(alpha) = (a^2 + d^2 - b^2) / (2 a d).
	#    The same law for the side d gives the interior knee angle:
	#      cos(beta) = (a^2 + b^2 - d^2) / (2 a b).
	var cos_alpha := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var cos_beta := clampf((a * a + b * b - d * d) / (2.0 * a * b), -1.0, 1.0)
	solution.root_angle = acos(cos_alpha)
	solution.middle_angle = acos(cos_beta)

	# The middle joint: a along u, turned by alpha toward v.
	solution.middle = root + a * (cos_alpha * u + sqrt(1.0 - cos_alpha * cos_alpha) * v)
	solution.end = root + d * u
	return solution


## Bases of the two bones for a chain whose bones point along -y at rest
## (the convention of BodyProportions), in the frame of the solution.
## Returns [upper, lower].
##
## Q: Which axes does each basis need?
## A: The bone's +y axis points from its child joint back to its own joint
##    (a leg hangs along -y). Its +x axis is the hinge: the normal of the
##    plane that holds root, middle and pole. A rotation about +x keeps
##    the bone in that plane. +z completes a right-handed frame: z = x × y.
## Q: Why u × v for the hinge, and not v × u?
## A: At rest u = (0, -1, 0) (down) and v = (0, 0, -1) (the knee points
##    forward). u × v = (1, 0, 0), the body's +x, which is the axis of
##    WalkCycle.pitch(). The rest pose then has identity bases.
static func leg_bases(solution: Solution, pole: Vector3) -> Array[Basis]:
	var upper_y := (solution.root - solution.middle).normalized()
	var lower_y := (solution.middle - solution.end).normalized()
	var u := (solution.end - solution.root).normalized()
	var v := (pole - solution.root) - (pole - solution.root).dot(u) * u
	var hinge := u.cross(v)
	if hinge.length() < 1e-6:
		hinge = Vector3.RIGHT
	hinge = hinge.normalized()
	var upper := Basis(hinge, upper_y, hinge.cross(upper_y))
	var lower := Basis(hinge, lower_y, hinge.cross(lower_y))
	return [upper.orthonormalized(), lower.orthonormalized()]


## Basis of a foot standing on ground with the given normal, its toes
## along the heading (a horizontal forward direction).
##
## Q: How does a foot frame follow the ground?
## A: Its +y is the ground normal n. Its toes point along -z, so -z is the
##    heading with its component along n removed (projected onto the
##    ground plane). +x = y × z completes the frame. On flat ground with
##    heading (0, 0, -1) the result is the identity.
static func foot_basis(normal: Vector3, heading: Vector3) -> Basis:
	var y := normal.normalized()
	var toes := heading - heading.dot(y) * y
	if toes.length() < 1e-6:
		toes = Vector3.FORWARD
	var z := -toes.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()


## The normal tilted toward up so that its angle from up is at most
## max_degrees. Ankles do not turn without limit.
static func limit_tilt(normal: Vector3, max_degrees: float) -> Vector3:
	var n := normal.normalized()
	var angle := n.angle_to(Vector3.UP)
	var limit := deg_to_rad(max_degrees)
	if angle <= limit or angle < 1e-6:
		return n
	# Slerp from up toward n by the fraction limit / angle.
	return Vector3.UP.slerp(n, limit / angle).normalized()
