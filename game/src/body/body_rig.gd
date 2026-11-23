@tool
class_name BodyRig
extends Node3D
## A procedural body: a Skeleton3D built in code, drawn with capsules
## (Lesson 11; decision 0002, stage 2).
##
## How the files relate:
##   proportions  BodyProportions (data/body/default_proportions.tres):
##                the bone list with lengths and radii
##   walk_cycle   WalkCycle (data/body/placeholder_walk.tres): joint angles
##                as functions of a phase
##   material     the body material (data/body/body_material.tres)
##   BodyPlayer   (src/body/body_player.gd) owns this node as
##                BodyMesh/Rig and calls advance() every physics tick
##
## Internal children, rebuilt at load and never written into a .tscn:
##   Skeleton3D
##     BoneAttachment3D (one per bone that has segments)
##       MeshInstance3D (one CapsuleMesh per segment)
##
## The rig's origin is the point between the soles, as the Player's
## origin is the bottom of its capsule.

@export var proportions: BodyProportions:
	set(value):
		if proportions != null and proportions.changed.is_connected(_queue_rebuild):
			proportions.changed.disconnect(_queue_rebuild)
		proportions = value
		if proportions != null:
			proportions.changed.connect(_queue_rebuild)
		_queue_rebuild()
@export var walk_cycle: WalkCycle
@export var material: Material:
	set(value):
		material = value
		_queue_rebuild()
## Rate at which the walk amount follows the speed, in 1/seconds.
@export var amount_responsiveness: float = 6.0

## Phase of the walk cycle in [0, 1).
var phase := 0.0
## Scale of the walk angles: 0 standing, 1 at walk_speed.
var amount := 0.0
## Duration of the last rebuild() and of the last apply_pose(), in ms.
var build_milliseconds := 0.0
var pose_milliseconds := 0.0

var _skeleton: Skeleton3D
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


func skeleton() -> Skeleton3D:
	return _skeleton


## Removes the old skeleton and builds bones and capsules from proportions.
func rebuild() -> void:
	_rebuild_queued = false
	if _skeleton != null:
		_skeleton.queue_free()
		_skeleton = null
	if proportions == null:
		return
	var start := Time.get_ticks_usec()

	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton, false, Node.INTERNAL_MODE_FRONT)

	var specs := proportions.bone_specs()
	for spec in specs:
		var index := _skeleton.add_bone(spec.name)
		if spec.parent >= 0:
			_skeleton.set_bone_parent(index, spec.parent)
		_skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, spec.offset))
	# Q: Why reset the poses after setting the rests?
	# A: A bone's pose, not its rest, decides where it is drawn. In Godot 4
	#    the pose is the whole local transform (it replaces the rest; it is
	#    not added to it). New bones start with an identity pose, which
	#    would put every joint at its parent's origin.
	_skeleton.reset_bone_poses()

	for i in specs.size():
		var segments: Array = specs[i].segments
		if segments.is_empty():
			continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = specs[i].name
		_skeleton.add_child(attachment, false, Node.INTERNAL_MODE_FRONT)
		for segment in segments:
			attachment.add_child(_capsule(segment[0], segment[1], segment[2]), false, Node.INTERNAL_MODE_FRONT)

	apply_pose(null)
	build_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


## Moves the phase by the distance walked and poses the skeleton.
## speed_fraction is the horizontal speed divided by the walk speed.
func advance(distance: float, speed_fraction: float, delta: float) -> void:
	if walk_cycle == null:
		return
	phase = fposmod(phase + distance / walk_cycle.stride_length, 1.0)
	# The same exponential blend as Player.blend_factor() (Lesson 02).
	var blend := 1.0 - exp(-amount_responsiveness * delta)
	amount = lerpf(amount, clampf(speed_fraction, 0.0, 1.0), blend)
	apply_pose(walk_cycle.sample(phase, amount))


## Writes a pose into the skeleton. null puts every bone at rest.
func apply_pose(pose: WalkCycle.Pose) -> void:
	if _skeleton == null:
		return
	var start := Time.get_ticks_usec()
	for i in _skeleton.get_bone_count():
		var rest := _skeleton.get_bone_rest(i)
		var rotation := Quaternion.IDENTITY
		var offset := Vector3.ZERO
		if pose != null:
			rotation = pose.rotations.get(_skeleton.get_bone_name(i), Quaternion.IDENTITY)
			if _skeleton.get_bone_parent(i) < 0:
				offset = pose.hips_offset
		var local := ForwardKinematics.local_transform(rest, rotation, offset)
		_skeleton.set_bone_pose_position(i, local.origin)
		_skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	pose_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


## A capsule from a to b with the given radius, in the bone's frame.
##
## Q: CapsuleMesh lies along its own y axis, centered at its origin. How is
##    it turned to lie along b - a?
## A: The transform's origin is the midpoint (a + b) / 2. Its basis must
##    send +y to the unit direction d = (b - a) / |b - a|. The quaternion
##    of the shortest arc from +y to d does that: Quaternion(UP, d).
## Q: Why the special case for d close to -y?
## A: Opposite vectors have infinitely many shortest arcs: a half turn
##    about any axis perpendicular to them. The textbook formula builds
##    the axis from the cross product, which is zero there. Godot 4.6
##    picks an axis itself (a half turn about z); the branch states the
##    choice instead of relying on it. Every leg and arm segment points
##    along -y, so the case occurs on most segments. A segment shorter
##    than 1 mm keeps the identity basis and is drawn as a sphere.
func _capsule(a: Vector3, b: Vector3, radius: float) -> MeshInstance3D:
	var length := a.distance_to(b)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length + 2.0 * radius
	mesh.radial_segments = 16
	mesh.rings = 4

	var basis := Basis.IDENTITY
	if length > 0.001:
		var d := (b - a) / length
		if d.dot(Vector3.UP) < -0.9999:
			basis = Basis(Vector3.RIGHT, PI)
		else:
			basis = Basis(Quaternion(Vector3.UP, d))

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(basis, 0.5 * (a + b))
	return instance


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()
