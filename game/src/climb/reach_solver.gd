class_name ReachSolver
extends RefCounted
## Places the root of a body (the pelvis) so that every holding limb can
## reach its hold (Lesson 15). Static functions only.
##
## The problem: limb i is attached to the root at the offset o_i (a
## shoulder or a hip joint, world space, the torso's turn already
## applied) and holds the point h_i. It can reach h_i when
##     |p + o_i - h_i| <= R_i,
## that is, when the root p lies in the ball of radius R_i around
## c_i = h_i - o_i. Every holding limb adds one ball; the wall adds a
## half-space (the pelvis stays at least `clearance` in front of it).
## The root must lie in the intersection of all of them.
##
## The method: alternating projections. Start at a preferred point and
## project it onto each set in turn, again and again. For convex sets
## with a common point the sequence converges to a point of the
## intersection (von Neumann for two subspaces; Bregman 1965 for convex
## sets). README section 2, P5 and P6.


## The outcome of one solve.
class Result:
	var position := Vector3.ZERO
	## Largest distance by which p lies outside one of the sets, meters.
	## 0 means every limb reaches.
	var residual := 0.0
	## Sweeps made (one sweep projects onto every set once).
	var sweeps := 0


## Nearest point of a ball to p.
##
## Q: What is the projection onto a ball?
## A: Inside, p itself. Outside, the point of the sphere on the segment
##    from the center to p: c + R (p - c) / |p - c|.
static func project_to_ball(p: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := p - center
	var distance := offset.length()
	if distance <= radius:
		return p
	return center + offset * (radius / distance)


## Nearest point of the half-space { q : (q - point) . normal >= 0 }.
static func project_to_half_space(p: Vector3, point: Vector3, normal: Vector3) -> Vector3:
	var depth := (p - point).dot(normal)
	if depth >= 0.0:
		return p
	return p - normal * depth


## Solves for the root.
##   start              the preferred position
##   centers, radii     one ball per holding limb (c_i = h_i - o_i, R_i)
##   plane_point/normal the half-space; normal of length 1
##   tolerance          stop when no projection moves p by more, meters
static func solve(start: Vector3, centers: PackedVector3Array, radii: PackedFloat32Array,
		plane_point: Vector3, plane_normal: Vector3, max_sweeps: int = 32,
		tolerance: float = 1e-4) -> Result:
	var result := Result.new()
	var p := start
	for sweep in max_sweeps:
		result.sweeps = sweep + 1
		var largest_move := 0.0
		for i in centers.size():
			var q := project_to_ball(p, centers[i], radii[i])
			largest_move = maxf(largest_move, q.distance_to(p))
			p = q
		var q := project_to_half_space(p, plane_point, plane_normal)
		largest_move = maxf(largest_move, q.distance_to(p))
		p = q
		if largest_move < tolerance:
			break
	result.position = p
	result.residual = residual(p, centers, radii, plane_point, plane_normal)
	return result


## Largest violation of any set at p, meters.
static func residual(p: Vector3, centers: PackedVector3Array, radii: PackedFloat32Array,
		plane_point: Vector3, plane_normal: Vector3) -> float:
	var worst := maxf(-(p - plane_point).dot(plane_normal), 0.0)
	for i in centers.size():
		worst = maxf(worst, p.distance_to(centers[i]) - radii[i])
	return worst
