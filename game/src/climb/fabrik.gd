class_name Fabrik
extends RefCounted
## FABRIK, Forward And Backward Reaching Inverse Kinematics (Aristidou and
## Lasenby 2011), for one chain of any length (Lesson 15). Static
## functions only.
##
## How the files relate:
##   TwoBoneIk (Lesson 12)   closed-form solution for two bones and a pole
##   this file               iterative solution for n bones, no pole
##   ClimbController         solves the arms with either one (arm_solver)
##   ReachSolver             the same idea one level up: projections onto
##                           spheres, for the pelvis instead of a joint
##
## The chain is a list of joint positions p0 (root) ... pn (end). Bone i
## joins p_i and p_(i+1) and keeps its length d_i. One iteration:
##   backward  put pn on the target; for i = n-1 down to 0, put p_i on the
##             sphere of radius d_i around p_(i+1), on the line to the old
##             p_i
##   forward   put p0 back on the root; for i = 1 up to n, put p_i on the
##             sphere of radius d_(i-1) around p_(i-1)
## Each "put on the sphere" is the projection of ReachSolver.project_to_ball()
## onto the sphere's surface instead of the ball. README section 3.4.


## The outcome of one solve.
class Result:
	var joints := PackedVector3Array()
	## Distance from the end joint to the target after the last iteration.
	var error := 0.0
	var iterations := 0
	## False when the target lies beyond the chain's length.
	var reachable := true


## The point at distance `length` from `center` on the ray toward `p`.
## When p sits on the center, the direction is undefined; the joint goes
## in the direction `fallback` (down unless the caller passes another).
static func place_on_sphere(p: Vector3, center: Vector3, length: float, fallback: Vector3 = Vector3.DOWN) -> Vector3:
	var offset := p - center
	var distance := offset.length()
	if distance < 1e-9:
		return center + fallback.normalized() * length
	return center + offset * (length / distance)


## Bone lengths of a chain.
static func lengths(joints: PackedVector3Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in joints.size() - 1:
		result.append(joints[i].distance_to(joints[i + 1]))
	return result


## Solves the chain for the target, starting from `joints` (a warm start:
## the previous tick's pose). The root joints[0] stays where it is.
##   bone_lengths  from lengths(); passed so that drift cannot change them
static func solve(joints: PackedVector3Array, bone_lengths: PackedFloat32Array, target: Vector3,
		tolerance: float = 1e-4, max_iterations: int = 10) -> Result:
	var result := Result.new()
	var p := joints.duplicate()
	var n := p.size() - 1
	var root := p[0]
	var total := 0.0
	for d in bone_lengths:
		total += d

	# Q: What if the target is farther than the chain is long?
	# A: No pose reaches it. The closest one is the straight chain pointing
	#    at the target: every joint on the line from the root to the target.
	if root.distance_to(target) >= total:
		result.reachable = false
		var direction := (target - root).normalized()
		for i in n:
			p[i + 1] = p[i] + direction * bone_lengths[i]
		result.joints = p
		result.error = p[n].distance_to(target)
		return result

	for iteration in max_iterations:
		if p[n].distance_to(target) <= tolerance:
			break
		result.iterations = iteration + 1
		# Backward: from the end to the root.
		p[n] = target
		for i in range(n - 1, -1, -1):
			p[i] = place_on_sphere(p[i], p[i + 1], bone_lengths[i])
		# Forward: from the root to the end.
		p[0] = root
		for i in range(1, n + 1):
			p[i] = place_on_sphere(p[i], p[i - 1], bone_lengths[i - 1])
	result.joints = p
	result.error = p[n].distance_to(target)
	return result
