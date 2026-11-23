@tool
class_name FootRig
extends BodyRig
## A BodyRig whose feet stand on the ground (Lesson 12).
##
## How the files relate:
##   BodyRig (body_rig.gd, Lesson 11)   builds the skeleton; this subclass
##                                      overrides advance() only
##   WalkCycle (walk_cycle.gd)          still decides the phase, the arms,
##                                      the torso and which foot swings
##   TwoBoneIk (two_bone_ik.gd)         hip, ankle target, pole -> knee
##   PlantFootstepReporter              listens to foot_planted and sends
##     (src/audio/plant_footstep_reporter.gd)   /foot/step to SuperCollider
##   scenes/grounded_player.tscn        sets this script on BodyMesh/Rig
##
## Every physics tick, advance():
##   1. moves the phase and the amount (as BodyRig does)
##   2. updates each foot: a stance foot stays where it was planted; a
##      swing foot travels from its lift-off point to a target a ray finds
##      on the ground ahead of the hip
##   3. lowers the pelvis until both ankle targets are within reach
##   4. solves each leg with TwoBoneIk (or lets TwoBoneIK3D do it)
##   5. writes the pose
##
## Positions are kept in world space while a foot is planted (the ground
## does not move with the body) and converted to the skeleton's frame for
## the solve. The skeleton's frame is this node's frame: the Skeleton3D
## child has the identity transform.

## A foot reached the ground at the end of a swing.
##   side            0 left, 1 right (FootstepReporter's foot numbers)
##   point, normal   ground contact under the sole, world space
##   tick_fraction   where in the tick the plant happened, in [0, 1]
signal foot_planted(side: int, point: Vector3, normal: Vector3, tick_fraction: float)

enum Solver {
	WALK_CYCLE,  ## Lesson 11: leg angles from the walk cycle, no ground.
	OWN,         ## TwoBoneIk, this lesson's solver.
	ENGINE,      ## Godot's TwoBoneIK3D modifier on the same targets.
}

const SIDE_NAMES: PackedStringArray = ["L", "R"]
## Phase at which each foot's swing ends: the heel strikes (WalkCycle).
const STRIKE_PHASE: PackedFloat32Array = [0.25, 0.75]

@export var solver := Solver.OWN:
	set(value):
		solver = value
		_update_engine_ik()
@export_group("Stepping")
## Height of the swing arc at full walking amount, in meters.
@export var step_height: float = 0.10
## Where a swing foot lands ahead of its hip, as a fraction of the stride.
## 0.25 lands it a quarter stride ahead.
@export var lead_fraction: float = 0.25
## A planted foot farther than this from its home point is moved there
## at once (after a turn on the spot or a teleport), in meters.
@export var replant_distance: float = 0.9
@export_group("Rays")
## Ray start above the rig origin, in meters. Must exceed the tallest step.
@export var ray_up: float = 0.6
## Ray end below the rig origin, in meters.
@export var ray_down: float = 0.6
## Physics layers the feet stand on.
@export_flags_3d_physics var ground_mask: int = 0xFFFFFFFF
@export_group("Pelvis and ankles")
## Fraction of the full leg length (thigh + shin) the pelvis allows.
@export_range(0.8, 1.0, 0.005) var reach_fraction: float = 0.98
## Largest drop of the pelvis below its rest height, in meters.
@export var max_pelvis_drop: float = 0.35
## Rate at which the pelvis follows its target height, in 1/seconds.
@export var pelvis_responsiveness: float = 15.0
## Largest tilt of a foot away from horizontal, in degrees.
@export var max_foot_tilt_degrees: float = 30.0
@export_group("")
## Draws the rays, the planted points and the swing targets.
@export var debug_draw := false:
	set(value):
		debug_draw = value
		if _debug_instance != null:
			_debug_instance.visible = value


## The state of one foot, all points in world space.
class FootState:
	var planted := false
	## Ankle position and ground normal while planted.
	var ankle := Vector3.ZERO
	var normal := Vector3.UP
	## Ground contact of the last plant (the sole point, not the ankle).
	var contact := Vector3.ZERO
	## Where the last swing started.
	var lift_ankle := Vector3.ZERO
	var lift_normal := Vector3.UP
	## Where the current swing will land, from this tick's ray.
	var target_ankle := Vector3.ZERO
	var target_normal := Vector3.UP
	var target_valid := false
	## Swing progress in [0, 1); 1 or more means stance.
	var swing := 1.0


## Per foot, left then right.
var feet: Array[FootState] = [FootState.new(), FootState.new()]
## Pelvis offset below the walk cycle's hips height, smoothed, meters (<= 0
## lowers the pelvis).
var pelvis_offset := 0.0
## Distance from each ankle to its target after the last pose, meters
## (measured on the skeleton; nonzero when out of reach).
var ankle_errors := PackedFloat32Array([0.0, 0.0])
## Time of the last foot update and solve, in milliseconds.
var ik_milliseconds := 0.0
## Rays cast so far.
var ray_count := 0

var _body: CollisionObject3D
var _grounded := false
var _engine_ik: TwoBoneIK3D
var _engine_targets: Array[Node3D] = []
var _engine_poles: Array[Node3D] = []
## Ankle targets of the last tick in the skeleton's frame, for the errors.
var _last_targets: Array = [[], []]
var _debug_instance: MeshInstance3D
var _debug_mesh: ImmediateMesh


func _ready() -> void:
	super()
	# Q: Why look for the body among the ancestors?
	# A: The rays start inside the player's own capsule. A ray that starts
	#    inside a shape does not hit it, but a ray that starts above the
	#    capsule's floor would hit its rounded bottom. Excluding the body
	#    removes the question.
	var node := get_parent()
	while node != null and not node is CollisionObject3D:
		node = node.get_parent()
	_body = node as CollisionObject3D


func rebuild() -> void:
	super()
	var skeleton := skeleton()
	if skeleton == null or skeleton.get_bone_count() == 0:
		return
	_engine_targets.clear()
	_engine_poles.clear()
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_engine_ik = TwoBoneIK3D.new()
	_engine_ik.name = "EngineIK"
	skeleton.add_child(_engine_ik, false, Node.INTERNAL_MODE_FRONT)
	_engine_ik.set_setting_count(2)
	for side in 2:
		var target := Node3D.new()
		target.name = "EngineTarget" + SIDE_NAMES[side]
		# The targets are placed in world space every tick.
		target.top_level = true
		add_child(target, false, Node.INTERNAL_MODE_FRONT)
		_engine_targets.append(target)
		var pole := Node3D.new()
		pole.name = "EnginePole" + SIDE_NAMES[side]
		pole.top_level = true
		add_child(pole, false, Node.INTERNAL_MODE_FRONT)
		_engine_poles.append(pole)
		var suffix := SIDE_NAMES[side]
		_engine_ik.set_root_bone_name(side, "UpperLeg." + suffix)
		_engine_ik.set_middle_bone_name(side, "LowerLeg." + suffix)
		_engine_ik.set_end_bone_name(side, "Foot." + suffix)
		_engine_ik.set_target_node(side, _engine_ik.get_path_to(target))
		# Q: Why a pole node, when FootRig's own solver takes a pole point?
		# A: The same pole point is handed to both solvers. A probe in Godot
		#    4.6.2 showed that TwoBoneIK3D without a pole node left a chain
		#    with a straight rest pose unchanged; with a pole node it reached
		#    the target.
		_engine_ik.set_pole_node(side, _engine_ik.get_path_to(pole))
	_update_engine_ik()

	if _debug_instance == null:
		_debug_mesh = ImmediateMesh.new()
		_debug_instance = MeshInstance3D.new()
		_debug_instance.name = "FootDebug"
		_debug_instance.mesh = _debug_mesh
		_debug_instance.top_level = true
		_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lines := StandardMaterial3D.new()
		lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lines.vertex_color_use_as_albedo = true
		lines.no_depth_test = true
		_debug_instance.material_override = lines
		add_child(_debug_instance, false, Node.INTERNAL_MODE_FRONT)
	_debug_instance.visible = debug_draw


func advance(distance: float, speed_fraction: float, delta: float) -> void:
	if walk_cycle == null or skeleton() == null:
		return
	var start := Time.get_ticks_usec()
	var previous_phase := phase
	var phase_step := distance / walk_cycle.stride_length
	phase = fposmod(phase + phase_step, 1.0)
	var blend := 1.0 - exp(-amount_responsiveness * delta)
	amount = lerpf(amount, clampf(speed_fraction, 0.0, 1.0), blend)
	var pose := walk_cycle.sample(phase, amount)

	if solver == Solver.WALK_CYCLE or not is_inside_tree():
		_grounded = false
		apply_pose(pose)
		return

	# Q: What do the feet do while the body is in the air?
	# A: Nothing holds them. They let go of the ground and take the walk
	#    cycle's angles; on the first tick back on the floor both are
	#    planted under the hips again.
	var on_floor := _body == null or not _body is CharacterBody3D or (_body as CharacterBody3D).is_on_floor()
	if not on_floor:
		_grounded = false
		for foot in feet:
			foot.planted = false
			foot.swing = 1.0
		pelvis_offset = 0.0
		apply_pose(pose)
		_update_engine_ik()
		_draw_debug()
		return
	if not _grounded:
		_grounded = true
		for side in 2:
			_plant_at_home(side)

	for side in 2:
		_update_foot(side, previous_phase, phase_step)

	_solve_and_pose(pose, delta)
	ik_milliseconds = (Time.get_ticks_usec() - start) / 1000.0
	_draw_debug()


## The point under the hip where a foot stands at rest, world space.
func home_point(side: int) -> Vector3:
	var x := (-1.0 if side == 0 else 1.0) * proportions.hip_half_width
	return global_transform * Vector3(x, 0.0, 0.0)


## Casts a vertical ray through a world point between ray_up above and
## ray_down below the rig origin. Returns {} on a miss, else the hit
## dictionary of PhysicsDirectSpaceState3D.intersect_ray().
func ground_ray(point: Vector3) -> Dictionary:
	var up := global_transform.basis.y.normalized()
	var level := global_position.dot(up)
	var through := point - (point.dot(up) - level) * up
	var query := PhysicsRayQueryParameters3D.create(through + up * ray_up, through - up * ray_down, ground_mask)
	if _body != null:
		query.exclude = [_body.get_rid()]
	ray_count += 1
	return get_world_3d().direct_space_state.intersect_ray(query)


## The swing progress u of a foot at phase phi: in [0, 1) during its
## swing, 1 or more during its stance.
##
## Q: Where does the swing interval come from?
## A: WalkCycle's convention: the left foot swings for phi in
##    (-0.25, 0.25) and the right foot for phi in (0.25, 0.75). Shifting
##    phi so each swing starts at 0 and dividing by its length 0.5 maps the
##    swing to [0, 1) and the stance to [1, 2).
static func swing_progress(side: int, phi: float) -> float:
	var start := STRIKE_PHASE[side] - 0.5
	return fposmod(phi - start, 1.0) / 0.5


## The ease used along the swing: s(0) = 0, s(1) = 1, s'(0) = s'(1) = 0.
##
## Q: Why u - sin(2 pi u) / (2 pi)?
## A: Its derivative is 1 - cos(2 pi u): zero at both ends and largest in
##    the middle. The foot leaves the ground and arrives on it with zero
##    horizontal speed relative to the ground, the property a planted foot
##    needs. It is the horizontal motion of a point on a rolling wheel (a
##    cycloid), scaled to one turn.
static func swing_ease(u: float) -> float:
	return u - sin(TAU * u) / TAU


func _plant_at_home(side: int) -> void:
	var foot := feet[side]
	var hit := ground_ray(home_point(side))
	foot.swing = 1.0
	if hit.is_empty():
		foot.planted = false
		return
	_set_plant(foot, hit.position, hit.normal)


func _set_plant(foot: FootState, contact: Vector3, normal: Vector3) -> void:
	var n := TwoBoneIk.limit_tilt(normal, max_foot_tilt_degrees)
	foot.planted = true
	foot.contact = contact
	foot.normal = n
	foot.ankle = contact + n * proportions.ankle_height


func _update_foot(side: int, previous_phase: float, phase_step: float) -> void:
	var foot := feet[side]
	var was_swing := foot.swing < 1.0
	var u := swing_progress(side, phase)

	# Q: How does the code notice the end of a swing within one tick?
	# A: The phase moved from previous_phase by phase_step. The strike lies
	#    in this tick if the distance from previous_phase forward to the
	#    strike phase is at most phase_step. That fraction of phase_step is
	#    also the fraction of the tick at which the foot landed.
	var to_strike := fposmod(STRIKE_PHASE[side] - previous_phase, 1.0)
	var strikes := was_swing and phase_step > 0.0 and to_strike <= phase_step

	if strikes or (was_swing and u >= 1.0):
		var fraction := clampf(to_strike / phase_step, 0.0, 1.0) if phase_step > 0.0 else 1.0
		# Q: The body has moved past the strike by the end of the tick. By how
		#    much?
		# A: By the rest of the tick, (1 - fraction) of the distance walked in
		#    it. The landing ray goes back by that much, so the plant lies
		#    where the target was at the moment of the strike.
		_update_target(side, (1.0 - fraction) * phase_step * walk_cycle.stride_length)
		foot.swing = 1.0
		if foot.target_valid:
			_set_plant(foot, foot.target_ankle - foot.target_normal * proportions.ankle_height, foot.target_normal)
			foot_planted.emit(side, foot.contact, foot.normal, fraction)
		else:
			foot.planted = false
		return

	if u < 1.0:
		if not was_swing:
			# Lift-off: the swing starts from the planted ankle.
			foot.lift_ankle = foot.ankle if foot.planted else _ankle_world(side)
			foot.lift_normal = foot.normal if foot.planted else Vector3.UP
			foot.planted = false
		foot.swing = u
		_update_target(side)
		return

	foot.swing = u
	# A stance foot keeps its plant unless the body has left it behind.
	if not foot.planted or foot.ankle.distance_to(home_point(side)) > replant_distance:
		_plant_at_home(side)


## Casts the landing ray of a swing foot. back_distance moves the ray
## backward along the heading (used at the strike).
func _update_target(side: int, back_distance: float = 0.0) -> void:
	var foot := feet[side]
	# Q: Why a fixed lead, not one that grows with the speed?
	# A: The phase moves by distance / stride_length, so the body always
	#    travels half a stride during one stance, at any speed. A foot that
	#    lands a quarter stride ahead ends the stance a quarter stride
	#    behind: the hip passes over the middle of the planted interval.
	var lead := lead_fraction * walk_cycle.stride_length
	var ahead := home_point(side) - global_transform.basis.z.normalized() * (lead - back_distance)
	var hit := ground_ray(ahead)
	foot.target_valid = not hit.is_empty()
	if foot.target_valid:
		var n := TwoBoneIk.limit_tilt(hit.normal, max_foot_tilt_degrees)
		foot.target_normal = n
		foot.target_ankle = hit.position + n * proportions.ankle_height


## The world-space ankle target of a foot and the normal its sole follows
## this tick. Returns [] when the foot has no target.
func ankle_target(side: int) -> Array:
	var foot := feet[side]
	if foot.swing >= 1.0:
		if not foot.planted:
			return []
		return [foot.ankle, foot.normal]
	if not foot.target_valid:
		return []
	var s := swing_ease(foot.swing)
	var point := foot.lift_ankle.lerp(foot.target_ankle, s)
	# Q: How high does the arc rise?
	# A: step_height at full amount, sin(pi u) along the swing, plus half
	#    the height difference between lift-off and landing so that a foot
	#    stepping up clears the edge it steps onto.
	var rise := absf(foot.target_ankle.y - foot.lift_ankle.y)
	point += Vector3.UP * (step_height * amount + 0.5 * rise) * sin(PI * foot.swing)
	var normal := foot.lift_normal.slerp(foot.target_normal, s).normalized()
	return [point, normal]


func _solve_and_pose(pose: WalkCycle.Pose, delta: float) -> void:
	var to_local := global_transform.affine_inverse()
	var hips_rotation: Quaternion = pose.rotations.get(&"Hips", Quaternion.IDENTITY)
	var hips_basis := Basis(hips_rotation)
	var hips_origin := Vector3(0.0, proportions.hip_height(), 0.0) + pose.hips_offset
	var a := proportions.thigh_length
	var b := proportions.shin_length

	# Targets in the skeleton's frame.
	var targets: Array = []
	for side in 2:
		var world := ankle_target(side)
		if world.is_empty():
			targets.append([])
		else:
			targets.append([to_local * (world[0] as Vector3), (to_local.basis * (world[1] as Vector3)).normalized()])

	# Q: How low must the pelvis go?
	# A: A hip joint at horizontal distance h from its ankle target reaches
	#    it when the vertical distance is at most sqrt(R^2 - h^2), with
	#    R = reach_fraction (a + b). So the hip may sit at most
	#    target.y + sqrt(R^2 - h^2). The pelvis takes the lower of the two
	#    limits and never rises above the walk cycle's height.
	var reach := reach_fraction * (a + b)
	var wanted := 0.0
	for side in 2:
		if (targets[side] as Array).is_empty():
			continue
		var target: Vector3 = targets[side][0]
		var hip := hips_origin + hips_basis * _hip_offset(side)
		var h := Vector2(target.x - hip.x, target.z - hip.z).length()
		var highest := target.y + sqrt(maxf(reach * reach - h * h, 0.0))
		wanted = minf(wanted, highest - hip.y)
	wanted = maxf(wanted, -max_pelvis_drop)
	# Lower at once, rise smoothly: a foot must never be out of reach
	# because the pelvis lagged behind, but a rising pelvis may ease.
	if wanted < pelvis_offset:
		pelvis_offset = wanted
	else:
		pelvis_offset = lerpf(pelvis_offset, wanted, 1.0 - exp(-pelvis_responsiveness * delta))
	pose.hips_offset.y += pelvis_offset
	hips_origin.y += pelvis_offset

	var heading := hips_basis * Vector3.FORWARD
	for side in 2:
		if (targets[side] as Array).is_empty():
			continue
		var suffix := SIDE_NAMES[side]
		var target: Vector3 = targets[side][0]
		var normal: Vector3 = targets[side][1]
		var hip := hips_origin + hips_basis * _hip_offset(side)
		# The knee points along the body's heading: the pole lies one meter
		# ahead of the knee's rest position.
		var pole := hip + Vector3(0.0, -a, 0.0) + heading
		var foot_global := TwoBoneIk.foot_basis(normal, heading)
		if solver == Solver.OWN:
			var solution := TwoBoneIk.solve(hip, target, pole, a, b)
			var bases := TwoBoneIk.leg_bases(solution, pole)
			# Q: How does a global basis become a pose rotation?
			# A: Global = parent global * local (Lesson 11, P1). With identity
			#    rest bases, local = parent global^-1 * global; for a rotation
			#    the inverse is the transpose.
			pose.rotations[StringName("UpperLeg." + suffix)] = (hips_basis.transposed() * bases[0]).get_rotation_quaternion()
			pose.rotations[StringName("LowerLeg." + suffix)] = (bases[0].transposed() * bases[1]).get_rotation_quaternion()
			pose.rotations[StringName("Foot." + suffix)] = (bases[1].transposed() * foot_global).get_rotation_quaternion()
		else:
			# TwoBoneIK3D turns the thigh and shin after this pose is set.
			# The foot keeps the walk cycle's local angle.
			_engine_targets[side].global_transform = Transform3D(global_transform.basis * foot_global, global_transform * target)
			_engine_poles[side].global_position = global_transform * pole

	_update_engine_ik()
	apply_pose(pose)
	_measure_errors(targets)


func _hip_offset(side: int) -> Vector3:
	return Vector3((-1.0 if side == 0 else 1.0) * proportions.hip_half_width, 0.0, 0.0)


func _ankle_world(side: int) -> Vector3:
	var skeleton := skeleton()
	var index := skeleton.find_bone("Foot." + SIDE_NAMES[side])
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _measure_errors(targets: Array) -> void:
	_last_targets = targets
	# Q: Why only for the own solver here?
	# A: TwoBoneIK3D writes the bones during the skeleton's update, which
	#    runs later in the frame, and the skeleton restores the unmodified
	#    pose afterward. Its result is visible only inside the
	#    skeleton_updated signal (_on_skeleton_updated()).
	if solver != Solver.OWN:
		return
	skeleton().force_update_all_bone_transforms()
	_read_errors()


func _on_skeleton_updated() -> void:
	if solver == Solver.ENGINE and _grounded:
		_read_errors()


func _read_errors() -> void:
	var skeleton := skeleton()
	for side in 2:
		if (_last_targets[side] as Array).is_empty():
			ankle_errors[side] = 0.0
			continue
		var index := skeleton.find_bone("Foot." + SIDE_NAMES[side])
		ankle_errors[side] = skeleton.get_bone_global_pose(index).origin.distance_to(_last_targets[side][0])


func _update_engine_ik() -> void:
	if _engine_ik != null:
		_engine_ik.active = solver == Solver.ENGINE and _grounded


func _draw_debug() -> void:
	if _debug_mesh == null or not debug_draw:
		return
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for side in 2:
		var foot := feet[side]
		var home := home_point(side)
		# Ray through the home point (gray).
		_line(home + Vector3.UP * ray_up, home - Vector3.UP * ray_down, Color(0.6, 0.6, 0.6))
		if foot.planted:
			_cross(foot.contact, Color(0.2, 0.9, 0.3))
		if foot.swing < 1.0 and foot.target_valid:
			_cross(foot.target_ankle - foot.target_normal * proportions.ankle_height, Color(1.0, 0.6, 0.1))
			_line(foot.lift_ankle, foot.target_ankle, Color(1.0, 0.6, 0.1))
	_debug_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(a)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(b)


func _cross(p: Vector3, color: Color) -> void:
	var r := 0.08
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, color)
	_line(p - Vector3.BACK * r, p + Vector3.BACK * r, color)
	_line(p, p + Vector3.UP * r, color)
