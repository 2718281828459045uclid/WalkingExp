class_name BalanceMonitor
extends Node3D
## Measures the balance of a FootRig body and sends it out (Lesson 13).
##
## How the files relate:
##   FootRig (foot_rig.gd, Lesson 12)    the feet: FootState.planted says
##                                       which feet carry the body
##   SegmentMasses (segment_masses.gd)   the mass table (a .tres the scene
##                                       assigns)
##   CenterOfMass (center_of_mass.gd)    segment table + pose -> c
##   SupportPolygon (support_polygon.gd) foot corners -> hull -> margin
##   SwayPendulum (sway_pendulum.gd)     the push response; its offset
##                                       moves the rig inside BodyMesh
##   OscSender ("Osc" autoload)          /body/balance, /body/balance/state
##   src/lessons/balance.gd              the scene root: keys 1, 2, 3, HUD
##
## Every physics tick, before the player moves (see _ready()):
##   1. the center of mass c from the pose the last tick produced
##   2. the sole corners of the planted feet -> convex hull
##   3. margin = signed distance from c's ground point to the hull
##   4. the state machine (stable, marginal, outside, no support)
##   5. OSC at send_rate_hz, and on every change of state
##   6. the pendulum steps; its offset moves the rig for this tick's pose

## Balance states. The names go out over OSC.
enum State {
	NO_SUPPORT,  ## No foot planted (in the air).
	STABLE,      ## Margin above marginal_margin.
	MARGINAL,    ## Inside, but close to an edge.
	OUTSIDE,     ## The center of mass projects outside the polygon.
}

const STATE_NAMES: PackedStringArray = ["none", "stable", "marginal", "outside"]
const STATE_COLORS: Array[Color] = [Color(0.6, 0.6, 0.6), Color(0.2, 0.9, 0.3), Color(1.0, 0.8, 0.1), Color(1.0, 0.2, 0.15)]

## The rig to measure. The scene assigns it.
@export var rig: FootRig
## Segment masses (data/body/winter_segment_masses.tres).
@export var masses: SegmentMasses
@export_group("States")
## Below this margin, in meters, the state is MARGINAL.
@export var marginal_margin: float = 0.015
## Width of the band in which a state is kept, in meters.
@export var hysteresis: float = 0.01
## A foot that is not planted counts as support when its sole is this
## close to the ground, in meters.
@export var contact_tolerance: float = 0.02
@export_group("Push response")
## Restoring stiffness kp, in 1/s^2 (SwayPendulum).
@export var stiffness: float = 20.0
## Damping kd, in 1/s.
@export var damping: float = 4.0
## Velocity change of one push, in m/s.
@export var push_speed: float = 0.4
## Largest sway of the rig, in meters.
@export var max_sway: float = 0.3
@export_group("Output")
## Rate of /body/balance in messages per second. 0 stops the stream.
@export_range(0.0, 240.0) var send_rate_hz: float = 30.0:
	set(value):
		send_rate_hz = value
		_clock.rate_hz = value
## Draws the polygon, the center of mass and the segment centers.
@export var debug_draw := true:
	set(value):
		debug_draw = value
		if _debug_instance != null:
			_debug_instance.visible = value
			if not value:
				_debug_mesh.clear_surfaces()

## World position of the center of mass.
var center_of_mass := Vector3.ZERO
## Segment centers of the last measurement, world space.
var segment_centers := PackedVector3Array()
## The support polygon, ground coordinates, counterclockwise.
var polygon := PackedVector2Array()
## Height at which the polygon is drawn: the mean height of its corners.
var polygon_height := 0.0
## Signed distance of the center of mass to the polygon, in meters.
var margin := -INF
var state := State.NO_SUPPORT
## Height of the center of mass above the rig's origin (the feet).
var center_height := 0.0
var pendulum := SwayPendulum.new()
## Time of the last measurement, in milliseconds.
var measure_milliseconds := 0.0
## Where messages go. Left empty, _ready() takes the "Osc" autoload.
var sender: OscSender
## Messages sent so far (both addresses).
var messages_sent := 0

var _segments: Array[Dictionary] = []
var _rest_position := Vector3.ZERO
var _clock := RateClock.new(30.0)
var _last_sent_state := -1
var _debug_instance: MeshInstance3D
var _debug_mesh: ImmediateMesh


func _ready() -> void:
	# Q: Why must this node's tick run before the player's?
	# A: The sway moves the rig. Set before the player's tick, the rig's
	#    IK solves this tick's legs with the rig already in place, and the
	#    planted feet stay on the ground. Set after it, the whole skeleton,
	#    feet included, would be drawn shifted for one frame. Running first
	#    means the measurement reads the pose of the previous tick: the
	#    pose on the screen.
	process_physics_priority = -1
	_clock.rate_hz = send_rate_hz
	if sender == null:
		sender = get_node_or_null("/root/Osc") as OscSender
	if rig != null:
		_rest_position = rig.position
	if masses != null and rig != null and rig.proportions != null:
		_segments = masses.segments(rig.proportions)

	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "BalanceDebug"
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


func _physics_process(delta: float) -> void:
	if rig == null or _segments.is_empty() or rig.skeleton() == null:
		return
	measure()
	_send(delta)
	_sway(delta)
	_draw_debug()


## Steps 1-4: the center of mass, the polygon, the margin, the state.
func measure() -> void:
	var start := Time.get_ticks_usec()
	var skeleton := rig.skeleton()
	var to_world := skeleton.global_transform
	var local_centers := CenterOfMass.segment_centers(skeleton, _segments)
	var local_com := CenterOfMass.weighted_mean(local_centers, _segments)
	center_of_mass = to_world * local_com
	center_height = local_com.y
	segment_centers.resize(local_centers.size())
	for i in local_centers.size():
		segment_centers[i] = to_world * local_centers[i]

	var corners := PackedVector2Array()
	var height_sum := 0.0
	var corner_count := 0
	for side in 2:
		if not foot_in_contact(side):
			continue
		for corner in sole_corners(side):
			corners.append(SupportPolygon.ground_point(corner))
			height_sum += corner.y
			corner_count += 1
	polygon = SupportPolygon.convex_hull(corners)
	polygon_height = height_sum / corner_count if corner_count > 0 else center_of_mass.y - center_height
	margin = SupportPolygon.signed_distance(polygon, SupportPolygon.ground_point(center_of_mass))
	state = next_state(state, margin, not polygon.is_empty(), marginal_margin, hysteresis)
	measure_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


## Whether a foot carries weight.
##
## Q: Which feet carry the body?
## A: A planted foot does: FootRig plants a foot at the strike and holds it
##    until lift-off. A foot that is not planted may still stand on the
##    ground. At rest the phase stops wherever the walk left it, often in
##    the middle of one foot's swing; with the walk amount at 0 the swing
##    arc is flat and that foot rests on the ground without being
##    planted. So an unplanted foot counts when its lowest sole corner is
##    within contact_tolerance of the ground under its ankle (one ray).
##    With the WALK_CYCLE solver FootRig plants nothing, and the ray test
##    decides for both feet.
func foot_in_contact(side: int) -> bool:
	var foot := rig.feet[side]
	if foot.planted and rig.solver != FootRig.Solver.WALK_CYCLE:
		return true
	var corners := sole_corners(side)
	var lowest := INF
	var center := Vector3.ZERO
	for corner in corners:
		lowest = minf(lowest, corner.y)
		center += corner / corners.size()
	var hit := rig.ground_ray(center)
	if hit.is_empty():
		return false
	return lowest - (hit.position as Vector3).y <= contact_tolerance


## The four corners of a sole, world space: heel and toe, each at the
## inner and outer edge of the foot capsule.
func sole_corners(side: int) -> PackedVector3Array:
	var p := rig.proportions
	var skeleton := rig.skeleton()
	var index := skeleton.find_bone("Foot." + FootRig.SIDE_NAMES[side])
	var foot := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	# The foot capsule (BodyProportions.bone_specs()) runs from the heel at
	# z = +0.25 L to the toes at z = -0.75 L, with radius r. Its outline on
	# the sole plane y = -ankle_height is a rectangle of width 2 r.
	var heel := 0.25 * p.foot_length
	var toe := -0.75 * p.foot_length
	var r := p.foot_radius
	var y := -p.ankle_height
	return PackedVector3Array([
		foot * Vector3(-r, y, heel),
		foot * Vector3(r, y, heel),
		foot * Vector3(r, y, toe),
		foot * Vector3(-r, y, toe),
	])


## The state machine. m = marginal, h = hysteresis.
##
##   from \ margin    < 0       [0, m)      [m, m + h]   > m + h
##   STABLE           OUTSIDE   MARGINAL    STABLE       STABLE
##   MARGINAL         OUTSIDE   MARGINAL    MARGINAL     STABLE
##   OUTSIDE          OUTSIDE   MARGINAL*   MARGINAL     STABLE
##
##   * only above h; at or below h the state stays OUTSIDE.
##
## A state is left only when the margin has crossed its threshold by the
## band h. Losing all support goes to NO_SUPPORT from any state;
## regaining it follows the OUTSIDE row.
static func next_state(current: State, value: float, has_support: bool, marginal: float, band: float) -> State:
	if not has_support:
		return State.NO_SUPPORT
	# Q: Why not decide from the margin alone, with fixed thresholds?
	# A: A margin that wobbles around a threshold by a millimeter would
	#    switch the state every tick, and every switch is an OSC message
	#    and, in SuperCollider, a sound. The band makes a state "sticky":
	#    to go back, the margin must move past the threshold by h.
	match current:
		State.STABLE:
			if value < 0.0:
				return State.OUTSIDE
			if value < marginal:
				return State.MARGINAL
			return State.STABLE
		State.MARGINAL:
			if value < 0.0:
				return State.OUTSIDE
			if value > marginal + band:
				return State.STABLE
			return State.MARGINAL
		_:
			# OUTSIDE or NO_SUPPORT.
			if value > marginal + band:
				return State.STABLE
			if value > band:
				return State.MARGINAL
			return State.OUTSIDE


## Pushes the body: direction in its ground frame (x right, y forward).
func push(direction: Vector2) -> void:
	pendulum.push(direction.normalized() * push_speed)


## The sway offset of the rig inside BodyMesh, in meters (x right, y forward).
func sway() -> Vector2:
	return pendulum.offset


func _send(delta: float) -> void:
	if sender == null:
		return
	if state != _last_sent_state:
		_last_sent_state = state
		sender.send("/body/balance/state", [STATE_NAMES[state]])
		messages_sent += 1
	if _clock.tick(delta):
		sender.send("/body/balance", balance_arguments())
		messages_sent += 1



## The arguments of one /body/balance message:
##   margin   float, meters (-1000 when there is no support)
##   state    int (State)
##   x z      float, the center of mass's ground point
##   height   float, the center of mass above the feet
func balance_arguments() -> Array:
	# OSC floats cannot carry -INF to every receiver; a large finite
	# number keeps the stream readable.
	var value := margin if is_finite(margin) else -1000.0
	return [float(value), int(state), float(center_of_mass.x), float(center_of_mass.z), float(center_height)]


func _sway(delta: float) -> void:
	pendulum.height = maxf(center_height, 0.3)
	pendulum.stiffness = stiffness
	pendulum.damping = damping
	pendulum.max_offset = max_sway
	pendulum.step(delta)
	# Q: Why move the rig and not the player?
	# A: The player is the capsule that physics moves (Lesson 00). The rig
	#    is drawing only. Moving it inside BodyMesh shifts the hips and the
	#    upper body; the planted feet stay where they are, because FootRig
	#    holds them in world space and solves the legs to reach them.
	#    BodyMesh's frame has -z forward, so the forward sway y goes to -z.
	var s := pendulum.offset
	rig.position = _rest_position + Vector3(s.x, 0.0, -s.y)


func _draw_debug() -> void:
	if not debug_draw:
		return
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var color: Color = STATE_COLORS[state]
	var lift := 0.01
	# The polygon's edges, drawn slightly above its mean height.
	var n := polygon.size()
	if n == 1:
		_cross(SupportPolygon.world_point(polygon[0], polygon_height + lift), 0.05, color)
	for i in n:
		if n == 2 and i == 1:
			break
		var a := SupportPolygon.world_point(polygon[i], polygon_height + lift)
		var b := SupportPolygon.world_point(polygon[(i + 1) % n], polygon_height + lift)
		_line(a, b, color)
	# The center of mass, its ground point and the plumb line between them.
	var ground := Vector3(center_of_mass.x, polygon_height + lift, center_of_mass.z)
	_cross(center_of_mass, 0.08, color)
	_line(center_of_mass, ground, color)
	_cross(ground, 0.04, color)
	# Segment centers, small and white.
	for c in segment_centers:
		_cross(c, 0.02, Color(1.0, 1.0, 1.0))
	_debug_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(a)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, color: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, color)
	_line(p - Vector3.BACK * r, p + Vector3.BACK * r, color)
	_line(p - Vector3.UP * r, p + Vector3.UP * r, color)
