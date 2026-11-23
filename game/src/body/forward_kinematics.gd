class_name ForwardKinematics
extends RefCounted
## Forward kinematics by hand (Lesson 11): the global transform of every
## bone from the local transforms along its chain.
##
## Skeleton3D computes the same transforms internally
## (get_bone_global_pose()). This class exists so that the computation is
## visible and testable; test_11_forward_kinematics.gd compares the two.
##
## Notation (README section 2):
##   L_i = (R_i, t_i)    local transform of bone i in its parent's frame:
##                       rotation R_i, translation t_i
##   G_i = G_p(i) L_i    global transform; p(i) is the parent of bone i
##   G_i x = R_p ... (R_i x + t_i) ... + t_root


## Local transform of one bone: the rest translation, and the rest rotation
## followed by the pose rotation.
##
## Q: Why rest_basis * Basis(rotation), and not Basis(rotation) * rest_basis?
## A: The pose rotation is expressed in the bone's rest frame: "swing about
##    the bone's own x axis". A rotation in a frame F is applied on the
##    right of the matrix that maps F to the parent: M_F * R. On the left it
##    would act about the parent's axes instead. With identity rest bases
##    (BodyProportions) the two orders agree; Exercise E4 shows where they
##    differ.
static func local_transform(rest: Transform3D, rotation: Quaternion, translation_offset := Vector3.ZERO) -> Transform3D:
	return Transform3D(rest.basis * Basis(rotation), rest.origin + translation_offset)


## Global transforms of all bones. parents[i] < i must hold (parents first).
static func global_transforms(parents: PackedInt32Array, locals: Array[Transform3D]) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(locals.size())
	for i in locals.size():
		# Q: Why can one pass from the first bone to the last compute all of them?
		# A: Each bone's global transform needs only its parent's, and the
		#    parent comes earlier in the list. The loop visits the tree in an
		#    order where every parent is finished before its children.
		if parents[i] < 0:
			globals[i] = locals[i]
		else:
			globals[i] = globals[parents[i]] * locals[i]
	return globals


## Rotation by a unit quaternion, written out: v' = q v q*.
##
## Q: Why write this when Quaternion * Vector3 exists?
## A: To see the formula once. With q = (w, u) (scalar w, vector u), the
##    product q (0, v) q* expands to
##      v' = v + 2w (u x v) + 2 u x (u x v).
##    test_11_forward_kinematics.gd checks it against Godot's operator.
static func rotate(q: Quaternion, v: Vector3) -> Vector3:
	var u := Vector3(q.x, q.y, q.z)
	var uv := u.cross(v)
	return v + 2.0 * q.w * uv + 2.0 * u.cross(uv)
