class_name CrawlController
extends Node3D
## Four-point locomotion (Lesson 16): a crawl on hands and knees and a
## scramble on hands and feet, with a static gait that keeps the center of
## mass over the limbs on the ground.
##
## How the files relate:
##   CrawlingPlayer (crawling_player.gd)  moves the capsule; this node reads
##                                        its position, facing and floor, and
##                                        sets its speed_scale
##   PostureController                    posture_changed: start a pose blend
##     (posture_controller.gd)            and plant the limbs anew; its
##                                        Lesson 14 trigger shift is added to
##                                        the body's sideways shift
##   BalanceMonitor (Lesson 13)           the center of mass of the last pose,
##                                        for the lift test
##   CrawlBalanceMonitor                  reads contact_points() and builds
##     (crawl_balance_monitor.gd)         the support polygon from them
##   TwoBoneIk (Lesson 12)                solves the arms and the scrambling
##                                        legs
##   SupportPolygon (Lesson 13)           hull and signed distance for the
##                                        lift test
##   CriticalSpring (Lesson 14)           smooths the sideways shift
##
## The gait (README section 2, P4 and P5):
##   One phase runs from 0 to 1 per stride; it advances with the distance
##   the body moves (and turns), as Lesson 11's walk phase does. Each limb
##   swings during swing_fraction of the cycle, in the order left leg,
##   left hand, right leg, right hand (the lateral sequence). The rest of
##   the cycle it stands. With swing_fraction 0.25 or less, at most one
##   limb is in the air, and the other three hold the body.
##   Before a limb lifts, the center of mass must lie inside the triangle
##   of the other three (signed distance >= lift_margin). If it does not,
##   the limb waits at the start of its swing and the body stops
##   (speed_scale 0) while the sideways shift moves the body over the
##   triangle.
##
## The body (README section 3.3):
##   The surface frame follows the plane of the contacts (contact_normal()).
##   Pelvis and shoulders lie on a line pitched to that plane: the pelvis
##   hip_height above it, the shoulders shoulder_height above it, 0.44 m
##   apart (the torso of BodyProportions), moved sideways by the shift and
##   up a slope by the lean. Each limb is solved alone. The arms and the
##   scrambling legs use TwoBoneIk; in a crawl the knee is the contact, so
##   the thigh is aimed at it and the shin laid back along the ground
##   (kneeling_leg()).
##
## Order inside one physics tick:
##   BalanceMonitor, PostureController (priority -1)  center of mass, shapes
##   Player (priority 0, earlier in the tree)          moves the capsule
##   this node (priority 0, after Player)              gait, body, pose

## A limb reached the ground at the end of a swing.
signal limb_planted(limb: int, point: Vector3, normal: Vector3)

enum Limb {
	HAND_L,
	HAND_R,
	LEG_L,
	LEG_R,
}

## Phase at which each limb's swing starts, by Limb: the lateral
## sequence left leg (0), left hand (0.25), right leg (0.5), right hand
## (0.75).
const SWING_START: PackedFloat32Array = [0.25, 0.75, 0.0, 0.5]
const LIMB_NAMES: PackedStringArray = ["hand L", "hand R", "leg L", "leg R"]
## The two ends of a capsule's axis, and the two signs of a direction.
const SIGNS: PackedFloat32Array = [-1.0, 1.0]

## The player to read and slow down. The scene assigns it.
@export var player: CrawlingPlayer
## The posture controller. The scene assigns it.
@export var posture: PostureController
## Optional. Its center of mass decides whether a limb may lift.
@export var monitor: BalanceMonitor
@export_group("Gait")
## Distance the body moves during one full cycle (each limb steps once),
## meters.
@export var stride_length: float = 0.4
## Part of the cycle each limb spends in the air. Above 0.25 the swings
## overlap (README P4, T3).
@export_range(0.05, 0.5, 0.01) var swing_fraction: float = 0.2
## Height of a limb's arc above the surface, meters.
@export var step_height: float = 0.06
## A planted limb farther than this from its home point is planted there
## at once, meters.
@export var replant_distance: float = 0.5
@export_group("Balance")
## Shifts the body sideways, away from the side whose limbs swing next.
@export var weight_shift := true
## Largest sideways shift, meters.
@export var shift_range: float = 0.08
## How far ahead in the cycle the shift target switches sides, as a
## fraction of the cycle.
@export_range(0.0, 0.25, 0.01) var shift_lead: float = 0.1
## Angular frequency of the spring that smooths the shift, rad/s.
@export var shift_frequency: float = 12.0
## A limb lifts only when the center of mass lies at least this far
## inside the triangle of the other three, meters.
@export var lift_margin: float = 0.0
## Longest wait for the balance before a limb lifts anyway, seconds.
@export var hold_timeout: float = 1.0
## Fraction of the downhill drift d tan(theta) of the center of mass's
## projection that the body leans against (0 turns the lean off).
@export_range(0.0, 1.5, 0.05) var slope_lean: float = 0.5
## Largest lean, meters.
@export var max_lean: float = 0.3
@export_group("Crawl body")
## Hip joints above the plane of the contacts, meters.
@export var crawl_hip_height: float = 0.49
## Shoulder joints above the plane of the contacts, meters.
@export var crawl_shoulder_height: float = 0.52
## Hands and knees from the body's middle line, meters.
@export var hand_half_width: float = 0.16
@export var knee_half_width: float = 0.12
## Part of the torso's pitch that the neck and head undo, 0 to 1: 0 keeps
## the head in line with the torso, 1 holds it upright.
@export_range(0.0, 1.0, 0.05) var head_lift: float = 0.15
@export_group("Scramble body")
@export var scramble_hip_height: float = 0.5
@export var scramble_shoulder_height: float = 0.45
## Feet behind the hips and hands ahead of the shoulders, along the
## surface, meters.
@export var scramble_foot_back: float = 0.35
@export var scramble_hand_ahead: float = 0.1
@export_group("")
## Duration of the pose blend after a posture change, seconds.
@export var transition_time: float = 0.4
## Time constant of the surface normal the body follows, seconds.
@export var normal_time_constant: float = 0.15
## Ray start above and end below a limb's home point, along the surface
## normal, meters.
@export var ray_up: float = 0.6
@export var ray_down: float = 0.8
## Draws the collision shape in every posture and, while crawling or
## scrambling, the contacts, the swing targets and the torso line.
@export var debug_draw := true:
	set(value):
		debug_draw = value
		if _debug_instance != null:
			_debug_instance.visible = value
			if not value:
				_debug_mesh.clear_surfaces()


## The state of one limb; points are world space.
class LimbContact:
	var planted := false
	## Ground point and normal while planted.
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	## Where the end of the limb touches or would touch this tick.
	var point := Vector3.ZERO
	## Swing: start point, landing point and normal from this tick's ray.
	var lift := Vector3.ZERO
	var target := Vector3.ZERO
	var target_normal := Vector3.UP
	var target_valid := false
	## Swing progress in [0, 1); 1 or more in stance.
	var swing := 1.0


## The surface frame of the body in one tick, world space (_frame()).
class SurfaceFrame:
	## Normal of the plane the body lies on.
	var n := Vector3.UP
	## The facing along that plane, and the body's right in it.
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	## The player's origin moved along n onto the plane of the contacts.
	var base := Vector3.ZERO


var limbs: Array[LimbContact] = [LimbContact.new(), LimbContact.new(), LimbContact.new(), LimbContact.new()]
## Gait phase in [0, 1).
var phase := 0.0
## Sideways shift of the body, meters (positive to the right).
var shift := 0.0
## Whether a limb waits for the balance this tick.
var holding := false
## The limb that waits, or -1.
var waiting_limb := -1
## Time spent waiting so far, seconds.
var wait_seconds := 0.0
## Lifts so far, lifts that went ahead after hold_timeout with the center
## of mass outside the triangle, and the smallest margin at a lift.
var lifts := 0
var unstable_lifts := 0
var smallest_lift_margin := INF
## The margin the last lift test found (NAN before the first).
var lift_test_margin := NAN
## Distance from each limb's end to its target after the pose, meters:
## the hand, the scrambling ankle, or the crawling knee.
var limb_errors := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Crawl only: distance from each knee to its contact, meters.
var knee_errors := PackedFloat32Array([0.0, 0.0])
## The surface normal the body follows, smoothed.
var surface_normal := Vector3.UP
## The lean of the last tick, world space, meters.
var lean := Vector3.ZERO
## Pelvis (Hips joint) and the point between the shoulders, world space.
var pelvis := Vector3.ZERO
var shoulders := Vector3.ZERO
## Time of the last low tick, milliseconds.
var crawl_milliseconds := 0.0

var _rig: FootRig
var _spring := CriticalSpring.new()
# One frame object, filled again on every tick, as the ray query below.
var _surface := SurfaceFrame.new()
# One ray query for all limbs, as Player._ray_query (Lesson 02): up to four
# rays per tick change only their end points.
var _ray_query := PhysicsRayQueryParameters3D.new()
var _active := false
var _last_origin := Vector3.ZERO
var _last_yaw := 0.0
var _hold_time := 0.0
var _blend_time := INF
var _snapshot: Array = []
var _shoulder_offsets: Array[Vector3] = []
var _hip_offsets: Array[Vector3] = []
var _debug_instance: MeshInstance3D
var _debug_mesh: ImmediateMesh


## Swing progress of a limb at phase phi: in [0, 1) during its swing, 1
## or more during its stance.
##
## Q: How does one formula serve all four limbs?
## A: Shift the phase so that the limb's swing starts at 0, wrap it into
##    [0, 1), and divide by the swing's length. The swing maps to [0, 1)
##    and the stance to [1, 1 / swing_fraction). FootRig.swing_progress()
##    (Lesson 12) does the same for two feet with swings of length 0.5.
static func swing_progress(limb: int, phi: float, fraction: float) -> float:
	return fposmod(phi - SWING_START[limb], 1.0) / fraction


## The limb whose swing starts within (from, from + step], or -1.
static func lift_in(from: float, step: float) -> int:
	if step <= 0.0:
		return -1
	# Q: Why is the interval open at `from`?
	# A: The intervals of consecutive ticks, (a, b] and (b, c], cover the
	#    cycle once. A swing that starts at `from` itself was found by the
	#    tick that ended there.
	for limb in 4:
		var ahead := fposmod(SWING_START[limb] - from, 1.0)
		if ahead > 0.0 and ahead <= step:
			return limb
	return -1


func _ready() -> void:
	if player != null:
		_rig = player.rig as FootRig
		_ray_query.exclude = [player.get_rid()]
		_ray_query.collision_mask = player.collision_mask
	if posture != null:
		posture.posture_changed.connect(_on_posture_changed)
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "CrawlDebug"
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
	if _rig == null or player == null or _rig.skeleton() == null:
		return
	var low := is_active()
	if low:
		var start := Time.get_ticks_usec()
		if not _active:
			_enter()
		_low_tick(delta)
		crawl_milliseconds = (Time.get_ticks_usec() - start) / 1000.0
	_active = low
	_blend_pose(delta)
	_draw_debug()


## Whether the body crawls or scrambles.
func is_active() -> bool:
	return player != null and player.mode != CrawlingPlayer.Mode.UPRIGHT


## Points that carry the body: [point, is_hand] for every planted limb.
func contact_points() -> Array:
	var result := []
	if not is_active():
		return result
	for i in 4:
		if limbs[i].planted:
			result.append([limbs[i].contact, i < 2])
	return result


## The limb in the air, or -1.
func swinging_limb() -> int:
	for i in 4:
		if limbs[i].swing < 1.0:
			return i
	return -1


## The normal of the plane the body lies on, from its contacts, or
## Vector3.ZERO when no hand or no leg is planted.
##
## Q: Why not the floor normal under the capsule?
## A: At the foot of the slab the capsule stands on flat ground while the
##    hands are already on the 48 degree face; at its top the reverse.
##    The floor normal jumps from one plane to the other, and the limbs
##    on the other plane fall out of reach. The line from the planted legs
##    to the planted hands runs along the body whatever the ground does.
##    With r the body's horizontal right, the normal is r x a, a the unit
##    vector from the legs' mean point to the hands' mean point: on flat
##    ground a = forward, and r x forward = up.
func contact_normal() -> Vector3:
	var hands := Vector3.ZERO
	var legs := Vector3.ZERO
	var hand_count := 0
	var leg_count := 0
	for i in 4:
		if not limbs[i].planted:
			continue
		if i < 2:
			hands += limbs[i].contact
			hand_count += 1
		else:
			legs += limbs[i].contact
			leg_count += 1
	if hand_count == 0 or leg_count == 0:
		return Vector3.ZERO
	var right := player.facing().cross(Vector3.UP).normalized()
	return plane_normal(hands / hand_count - legs / leg_count, right)


## The normal r x a of the plane through a body axis a (legs to hands) and
## a horizontal right r, or Vector3.ZERO when a is shorter than 0.1 m or
## the plane is steeper than about 84 degrees.
static func plane_normal(axis: Vector3, right: Vector3) -> Vector3:
	if axis.length() < 0.1:
		return Vector3.ZERO
	var n := right.cross(axis.normalized()).normalized()
	return n if n.y > 0.1 else Vector3.ZERO


## Signed distance of a ground point to the polygon of the planted limbs
## other than `except` (Lesson 13: positive inside).
func support_margin(ground_point: Vector2, except: int) -> float:
	var corners := PackedVector2Array()
	for i in 4:
		if i != except and limbs[i].planted:
			corners.append(SupportPolygon.ground_point(limbs[i].contact))
	return SupportPolygon.signed_distance(SupportPolygon.convex_hull(corners), ground_point)


# --- Entering, posture changes ----------------------------------------------

func _on_posture_changed(_posture: int) -> void:
	_take_snapshot()
	_blend_time = 0.0
	# Q: Why plant every limb anew when the body changes from crawl to
	#    scramble?
	# A: The leg's contact changes from the knee to the foot, half a meter
	#    farther back. Planting all four at their new home points lets the
	#    pose blend carry the body between the two shapes.
	if _active and is_active():
		_plant_all()


func _enter() -> void:
	_cache_offsets()
	surface_normal = player.get_floor_normal() if player.is_on_floor() else Vector3.UP
	_last_origin = player.global_position
	_last_yaw = player.body_mesh().rotation.y
	# A phase at which every limb stands: the right hand's swing has just
	# ended and the left leg's has not begun.
	phase = 0.96
	_spring.frequency = shift_frequency
	_spring.reset()
	shift = 0.0
	_hold_time = 0.0
	holding = false
	waiting_limb = -1
	_plant_all()


func _plant_all() -> void:
	var frame := _frame()
	for i in 4:
		var limb := limbs[i]
		limb.swing = 1.0
		_plant_at_home(i, frame)
		if not limb.planted:
			limb.point = _home(i, frame)


# --- One low tick -------------------------------------------------------------

func _low_tick(delta: float) -> void:
	var wanted := contact_normal()
	if wanted == Vector3.ZERO:
		wanted = player.get_floor_normal() if player.is_on_floor() else Vector3.UP
	# A one-pole filter on the normal (Lesson 14). Blending the vectors and
	# normalizing stays exact enough for the small turn of one tick.
	surface_normal = surface_normal.lerp(wanted, OnePoleFilter.blend(delta, normal_time_constant)).normalized()
	var frame := _frame()

	# Q: How far does the gait advance this tick?
	# A: By the distance the body moved, as Lesson 11's walk phase does,
	#    plus the arc the hands sweep when the body turns on the spot
	#    (half the body length times the turn angle). A turn without
	#    steps would twist the arms around planted hands.
	var origin := player.global_position
	var moved := origin - _last_origin
	var yaw := player.body_mesh().rotation.y
	var turn := absf(angle_difference(_last_yaw, yaw))
	_last_origin = origin
	_last_yaw = yaw
	var step := (moved.length() + turn * _span() * 0.5) / stride_length
	var along := moved - moved.dot(frame.n) * frame.n
	var motion := along.normalized() if along.length() > 1e-5 else Vector3.ZERO

	step = _test_lift(step, delta)
	player.speed_scale = 0.0 if holding else 1.0
	phase = fposmod(phase + step, 1.0)
	for i in 4:
		_update_limb(i, frame, motion)

	_update_shift(delta)
	_place_body(frame)
	_pose(frame)


## The lift test: may the limb whose swing starts this tick lift?
## Returns the phase step that remains after the test.
##
## Q: What is tested?
## A: The ground point of the center of mass (BalanceMonitor, last tick's
##    pose) against the convex hull of the three other planted limbs,
##    with Lesson 13's signed distance. A limb in the air carries nothing,
##    so after the lift the body stands on that triangle. A negative
##    distance means the body would tip toward the lifted limb.
## Q: What happens when the test fails?
## A: The phase stops just before the limb's swing, and the limb waits.
##    The body stops (speed_scale 0) while the sideways shift keeps moving
##    it toward the triangle. The waiting limb is tested again on every
##    tick, whether the body moves or not; when the test passes, the
##    phase goes on from the start of its swing. After hold_timeout the
##    limb lifts anyway and the lift counts as unstable.
func _test_lift(step: float, delta: float) -> float:
	var limb := waiting_limb
	if limb < 0:
		limb = lift_in(phase, step)
	if limb < 0 or monitor == null:
		holding = false
		_hold_time = 0.0
		return step
	var m := support_margin(SupportPolygon.ground_point(monitor.center_of_mass), limb)
	lift_test_margin = m
	if m < lift_margin and _hold_time < hold_timeout:
		# Q: Is this the first tick of the wait?
		# A: Then the phase moves up to the swing's start and stops there.
		if waiting_limb < 0:
			phase = fposmod(SWING_START[limb] - 1e-4, 1.0)
			waiting_limb = limb
		holding = true
		_hold_time += delta
		wait_seconds += delta
		return 0.0
	if m < lift_margin:
		unstable_lifts += 1
	lifts += 1
	smallest_lift_margin = minf(smallest_lift_margin, m)
	holding = false
	_hold_time = 0.0
	# Q: Did the limb wait before this lift?
	# A: Then the phase steps over its swing start now.
	if waiting_limb >= 0:
		waiting_limb = -1
		phase = SWING_START[limb]
		return 0.0
	return step


func _update_limb(i: int, frame: SurfaceFrame, motion: Vector3) -> void:
	var limb := limbs[i]
	var was_swing := limb.swing < 1.0
	var u := swing_progress(i, phase, swing_fraction)
	# Q: Was the limb in the air last tick and is it in stance now?
	# A: Then its swing ended within this tick: it lands on the target.
	if was_swing and u >= 1.0:
		_update_target(i, frame, motion)
		limb.swing = 1.0
		if limb.target_valid:
			_set_plant(limb, limb.target, limb.target_normal)
			limb_planted.emit(i, limb.contact, limb.normal)
		else:
			limb.planted = false
			limb.point = limb.target
		return
	if u < 1.0:
		if not was_swing:
			limb.lift = limb.contact if limb.planted else limb.point
			limb.planted = false
		limb.swing = u
		_update_target(i, frame, motion)
		var s := FootRig.swing_ease(u)
		var end := limb.target if limb.target_valid else _home(i, frame)
		limb.point = limb.lift.lerp(end, s) + frame.n * _arc_height(i) * sin(PI * u)
		return
	limb.swing = u
	if not limb.planted or limb.contact.distance_to(_home(i, frame)) > replant_distance:
		_plant_at_home(i, frame)


## Height of a limb's swing arc, meters.
##
## Q: Why does a knee not lift in a crawl?
## A: With the hip crawl_hip_height above the ground, the thigh reaches
##    the ground almost straight down; a knee lifted by h would need a
##    thigh shorter by about h. The thigh keeps its length, so the knee
##    slides along the ground through its swing. Hands and scrambling
##    feet lift by step_height.
func _arc_height(i: int) -> float:
	if i >= 2 and not _scrambling():
		return 0.0
	return step_height


## Casts the landing ray of a swinging limb.
##
## Q: Why land ahead of the home point, and by how much?
## A: A limb stands for (1 - swing_fraction) of the cycle while the body
##    moves (1 - swing_fraction) stride lengths. Landing half that
##    distance ahead (along the motion) makes the stance end half that
##    distance behind: the home point lies in the middle of the stance,
##    as FootRig's lead does for the feet (Lesson 12).
func _update_target(i: int, frame: SurfaceFrame, motion: Vector3) -> void:
	var limb := limbs[i]
	var lead := 0.5 * (1.0 - swing_fraction) * stride_length
	var hit := _surface_ray(_home(i, frame) + motion * lead, frame.n)
	limb.target_valid = not hit.is_empty()
	if limb.target_valid:
		limb.target = hit.position
		limb.target_normal = hit.normal


func _plant_at_home(i: int, frame: SurfaceFrame) -> void:
	var hit := _surface_ray(_home(i, frame), frame.n)
	if hit.is_empty():
		limbs[i].planted = false
		return
	_set_plant(limbs[i], hit.position, hit.normal)


func _set_plant(limb: LimbContact, point: Vector3, normal: Vector3) -> void:
	limb.planted = true
	limb.contact = point
	limb.normal = normal
	limb.point = point


## A ray along -n through a point, from ray_up above to ray_down below.
func _surface_ray(point: Vector3, n: Vector3) -> Dictionary:
	_ray_query.from = point + n * ray_up
	_ray_query.to = point - n * ray_down
	return get_world_3d().direct_space_state.intersect_ray(_ray_query)


# --- The body -------------------------------------------------------------------

## The surface frame of the body this tick: n, forward along the surface,
## right, and the base, the player's origin moved along n onto the plane
## of the planted contacts. It fills _surface and returns it.
##
## Q: Why is forward projected onto the surface?
## A: The facing is horizontal. On a slab the body lies along the slab, so
##    its forward axis is the facing with its component along n removed:
##    f - (f . n) n, then normalized. right = forward x n completes a
##    right-handed frame (for n = up and forward = -z it gives +x).
func _frame() -> SurfaceFrame:
	var n := surface_normal
	var f := player.facing()
	_surface.n = n
	_surface.forward = (f - f.dot(n) * n).normalized()
	_surface.right = _surface.forward.cross(n)
	var origin := player.global_position
	var sum := Vector3.ZERO
	var count := 0
	for limb in limbs:
		if limb.planted:
			sum += limb.contact
			count += 1
	_surface.base = origin
	if count > 0:
		_surface.base = origin + n * (sum / count - origin).dot(n)
	return _surface


func _scrambling() -> bool:
	return player != null and player.mode == CrawlingPlayer.Mode.SCRAMBLE


func _hip_height() -> float:
	return scramble_hip_height if _scrambling() else crawl_hip_height


func _shoulder_height() -> float:
	return scramble_shoulder_height if _scrambling() else crawl_shoulder_height


## Distance along the surface from the pelvis to the shoulders, meters.
##
## Q: Where does it come from?
## A: The torso is rigid: shoulders 0.44 m from the pelvis (the rest
##    offset of the shoulder joints). Their heights above the surface
##    differ by shoulder_height - hip_height. Pythagoras gives the rest:
##    span = sqrt(0.44^2 - (shoulder_height - hip_height)^2).
func _span() -> float:
	var torso := 0.44 if _shoulder_offsets.is_empty() else _shoulder_offsets[0].y
	var rise := _shoulder_height() - _hip_height()
	return sqrt(maxf(torso * torso - rise * rise, 0.0))


## The home point of a limb on the surface (before the ray).
func _home(i: int, frame: SurfaceFrame) -> Vector3:
	var side := SIGNS[i % 2]
	var half := _span() * 0.5
	if i < 2:
		var ahead := half + (scramble_hand_ahead if _scrambling() else 0.0)
		return frame.base + frame.forward * ahead + frame.right * side * hand_half_width
	var back := half + (scramble_foot_back if _scrambling() else 0.0)
	return frame.base - frame.forward * back + frame.right * side * knee_half_width


## Moves the sideways shift toward its target.
##
## Q: Which way does the body shift?
## A: Away from the side whose limb lifts next. In the lateral sequence the
##    left leg and the left hand swing in the first half of the cycle and
##    the right limbs in the second half. The target switches sides
##    shift_lead ahead of each half: it is +shift_range (right) for phases
##    in [1 - shift_lead, 0.5 - shift_lead), with the default 0.1 in
##    [0.9, 0.4), and -shift_range in the rest. The spring (Lesson 14)
##    turns the steps into a sway. The Lesson 14 trigger shift is added
##    on top.
func _update_shift(delta: float) -> void:
	var target := 0.0
	if weight_shift:
		var left_next := fposmod(phase + shift_lead, 1.0) < 0.5
		target = shift_range if left_next else -shift_range
	_spring.frequency = shift_frequency
	shift = _spring.step(Vector2(target, 0.0), delta).x
	if posture != null:
		shift += posture.shift.x


func _place_body(frame: SurfaceFrame) -> void:
	var half := _span() * 0.5
	lean = _lean(frame.n, frame.base)
	var sway := frame.right * shift + lean
	pelvis = frame.base + frame.n * _hip_height() - frame.forward * half + sway
	shoulders = frame.base + frame.n * _shoulder_height() + frame.forward * half + sway


## The offset that moves the body up the slope, over its contacts.
##
## Q: Where does the center of mass project on a slope?
## A: Let the center of mass c lie at height d above the plane of the
##    contacts, along the normal n, and let theta be the slope. Its
##    vertical projection lands d tan(theta) down the slope from the
##    point below it along n (README section 2, P5). Moving the body up
##    the slope by that distance brings the projection back.
## Q: How is the offset computed without angles?
## A: The part of `up` along the plane, t = up - (up . n) n, points up
##    the slope and has length sin(theta); up . n = cos(theta). So
##    d t / (up . n) has length d tan(theta) and the uphill direction.
func _lean(n: Vector3, base: Vector3) -> Vector3:
	if slope_lean <= 0.0:
		return Vector3.ZERO
	var d := 0.5 * (_hip_height() + _shoulder_height())
	if monitor != null:
		d = (monitor.center_of_mass - base).dot(n)
	var t := Vector3.UP - Vector3.UP.dot(n) * n
	var offset := t * (slope_lean * maxf(d, 0.0) / maxf(Vector3.UP.dot(n), 0.1))
	return offset.limit_length(max_lean)


## Solves the four limbs and writes the pose in the rig's frame.
func _pose(frame: SurfaceFrame) -> void:
	var q := _rig.proportions
	var to_local := _rig.global_transform.affine_inverse()
	var n_local := (to_local.basis * frame.n).normalized()
	var forward_local := (to_local.basis * frame.forward).normalized()
	var right_local := (to_local.basis * frame.right).normalized()
	var hips := to_local * pelvis

	# Q: How is the torso turned so that it runs from the pelvis to the
	#    shoulders?
	# A: At rest the torso points along +y with +x to the right. The new
	#    y axis is the unit vector from the pelvis to the shoulders; the new
	#    x axis is the body's right, made perpendicular to it; z = x cross y
	#    completes the frame. Spine and Chest keep the identity, so this
	#    basis is also the frame of the shoulders.
	var axis := (to_local * shoulders - hips).normalized()
	var x := (right_local - right_local.dot(axis) * axis).normalized()
	var torso := Basis(x, axis, x.cross(axis))
	var pose := WalkCycle.Pose.new()
	pose.hips_offset = hips - Vector3(0.0, q.hip_height(), 0.0)
	pose.rotations[&"Hips"] = torso.get_rotation_quaternion()
	# Q: Where does the head point?
	# A: Along the torso, lifted by head_lift of the torso's pitch away
	#    from vertical: two thirds of the lift in the neck, one third in
	#    the head. A head held up to look ahead is the highest point of
	#    the crawling body: head_lift 0.15 keeps the body 0.69 m high,
	#    0.75 raises the top of the head to 0.81 m (README T2), above
	#    the crawl shape.
	var pitch := rad_to_deg(axis.angle_to(Vector3.UP))
	pose.rotations[&"Neck"] = WalkCycle.pitch(head_lift * pitch * 2.0 / 3.0)
	pose.rotations[&"Head"] = WalkCycle.pitch(head_lift * pitch / 3.0)

	for i in 4:
		var side := SIGNS[i % 2]
		var suffix := FootRig.SIDE_NAMES[i % 2]
		var point := to_local * limbs[i].point
		if i < 2:
			var root := hips + torso * _shoulder_offsets[i]
			var target := point + n_local * 0.03
			# Elbows point back toward the knees and out to the side.
			var pole := root - forward_local + right_local * side * 0.4
			var arm := TwoBoneIk.solve(root, target, pole, q.upper_arm_length, q.forearm_length)
			var bases := TwoBoneIk.leg_bases(arm, pole)
			pose.rotations[StringName("UpperArm." + suffix)] = (torso.transposed() * bases[0]).get_rotation_quaternion()
			pose.rotations[StringName("LowerArm." + suffix)] = (bases[0].transposed() * bases[1]).get_rotation_quaternion()
			limb_errors[i] = arm.end.distance_to(target)
			continue
		var hip := hips + torso * _hip_offsets[i - 2]
		var leg: TwoBoneIk.Solution
		var pole := Vector3.ZERO
		var foot := Basis.IDENTITY
		if _scrambling():
			# The sole on the surface, the toes up the slope; knees forward
			# and out (a frog stance, as on the climbing face).
			var ankle := point + n_local * q.ankle_height
			pole = hip + forward_local + right_local * side * 0.4
			foot = TwoBoneIk.foot_basis(n_local, forward_local)
			leg = TwoBoneIk.solve(hip, ankle, pole, q.thigh_length, q.shin_length)
			limb_errors[i] = leg.end.distance_to(ankle)
		else:
			leg = kneeling_leg(hip, point, n_local, forward_local, q)
			# A pole on the knee's side of the line from hip to ankle keeps
			# the hinge of leg_bases() perpendicular to both bones.
			pole = leg.middle + (leg.middle - (leg.root + leg.end) * 0.5)
			# The foot lies on its top, toes pointing back: its +y (sole to
			# ankle) points into the ground, its -z (toes) backward.
			foot = Basis(right_local, -n_local, forward_local)
			knee_errors[i - 2] = leg.middle.distance_to(point + n_local * q.thigh_radius)
			limb_errors[i] = knee_errors[i - 2]
		var bases := TwoBoneIk.leg_bases(leg, pole)
		pose.rotations[StringName("UpperLeg." + suffix)] = (torso.transposed() * bases[0]).get_rotation_quaternion()
		pose.rotations[StringName("LowerLeg." + suffix)] = (bases[0].transposed() * bases[1]).get_rotation_quaternion()
		pose.rotations[StringName("Foot." + suffix)] = (bases[1].transposed() * foot).get_rotation_quaternion()
	_rig.apply_pose(pose)


## A leg that kneels: the thigh points from the hip at the knee's
## contact, and the shin lies back along the ground. All points in one
## frame (the pose passes the rig's).
##
## Q: Why not TwoBoneIk from the hip to the ankle, as for the feet?
## A: Two-bone IK places the end joint and lets the middle joint fall
##    where the triangle puts it. In a crawl the middle joint (the knee)
##    carries the weight and must stand on its contact; the ankle only
##    follows. The knee joint belongs thigh_radius above the contact,
##    at knee target = contact + thigh_radius n. So the thigh is aimed at
##    the knee target (its length fixed: the knee lands short of it or
##    beyond it by | |knee target - hip| - thigh |), and the shin is laid
##    back from the knee.
## Q: Where does the ankle lie?
## A: The knee joint lies thigh_radius above the contact; the shin lies
##    back along the ground to an ankle shin_radius above it. The two
##    heights differ by r = thigh_radius - shin_radius, so the ankle lies
##    sqrt(shin^2 - r^2) behind the knee and r lower.
static func kneeling_leg(hip: Vector3, contact: Vector3, n: Vector3, forward: Vector3, q: BodyProportions) -> TwoBoneIk.Solution:
	var knee_target := contact + n * q.thigh_radius
	var r := q.thigh_radius - q.shin_radius
	var back := sqrt(q.shin_length * q.shin_length - r * r)
	var leg := TwoBoneIk.Solution.new()
	leg.root = hip
	leg.middle = hip + (knee_target - hip).normalized() * q.thigh_length
	leg.end = leg.middle - n * r - forward * back
	leg.reached = absf(hip.distance_to(knee_target) - q.thigh_length) < 1e-3
	return leg


# --- The pose blend -------------------------------------------------------------

## Keeps the pose of the moment of a posture change.
func _take_snapshot() -> void:
	var skeleton := _rig.skeleton() if _rig != null else null
	_snapshot.clear()
	if skeleton == null:
		return
	for b in skeleton.get_bone_count():
		_snapshot.append([skeleton.get_bone_pose_position(b), skeleton.get_bone_pose_rotation(b)])


## Blends from the snapshot to the pose written this tick.
##
## Q: Why blend the bone poses and not the limb targets?
## A: Before and after a posture change two different systems pose the
##    body (FootRig upright, this node low), with different contacts. The
##    bone poses are what both write. Each bone's rotation is slerped from
##    its old value (Lesson 11, Shoemake) and the Hips position lerped,
##    with an ease, over transition_time. The limbs leave their contacts
##    during the blend; the errors are reported, not hidden.
func _blend_pose(delta: float) -> void:
	if _blend_time >= transition_time or _snapshot.is_empty():
		return
	_blend_time += delta
	var w := smoothstep(0.0, 1.0, clampf(_blend_time / transition_time, 0.0, 1.0))
	var skeleton := _rig.skeleton()
	for b in mini(skeleton.get_bone_count(), _snapshot.size()):
		var old: Array = _snapshot[b]
		skeleton.set_bone_pose_position(b, (old[0] as Vector3).lerp(skeleton.get_bone_pose_position(b), w))
		skeleton.set_bone_pose_rotation(b, (old[1] as Quaternion).slerp(skeleton.get_bone_pose_rotation(b), w))


## Reads the shoulder and hip offsets from the skeleton's rest pose
## (ClimbController._cache_offsets() does the same).
func _cache_offsets() -> void:
	_shoulder_offsets.clear()
	_hip_offsets.clear()
	var skeleton := _rig.skeleton()
	var hips := skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin
	for suffix in FootRig.SIDE_NAMES:
		_shoulder_offsets.append(skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm." + suffix)).origin - hips)
		_hip_offsets.append(skeleton.get_bone_global_rest(skeleton.find_bone("UpperLeg." + suffix)).origin - hips)


# --- Debug lines --------------------------------------------------------------------

func _draw_debug() -> void:
	if _debug_mesh == null or not debug_draw:
		return
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# The collision shape in every posture; the limbs only in the low ones.
	_draw_shape()
	if is_active():
		for i in 4:
			var limb := limbs[i]
			var color := Color(0.3, 0.8, 1.0) if i < 2 else Color(0.6, 1.0, 0.4)
			if limb.planted:
				_cross(limb.contact, 0.06, color)
			elif limb.target_valid:
				_cross(limb.target, 0.04, Color(1.0, 0.6, 0.1))
				_line(limb.lift, limb.target, Color(1.0, 0.6, 0.1))
		_line(pelvis, shoulders, Color.WHITE)
	_debug_mesh.surface_end()


## The player's collision shape: two rings where the cylinder meets the
## end caps, four lines along the cylinder, and two half circles over each
## cap.
func _draw_shape() -> void:
	var shape := player.shape_transform(player.body_shape, player.body_mesh().rotation.y)
	var xf := player.global_transform * shape
	var radius := player.shape_radius(player.body_shape)
	var half := 0.5 * player.crawl_length if player.body_shape == CrawlingPlayer.BodyShape.CRAWL else 0.5 * player.shape_height(player.body_shape)
	var axis := xf.basis.y.normalized()
	var u := xf.basis.x.normalized()
	var v := xf.basis.z.normalized()
	var color := Color(1.0, 0.85, 0.3)
	for end: float in SIGNS:
		var c := xf.origin + axis * end * (half - radius)
		for k in 24:
			var a := TAU * k / 24.0
			var b := TAU * (k + 1) / 24.0
			_line(c + (u * cos(a) + v * sin(a)) * radius, c + (u * cos(b) + v * sin(b)) * radius, color)
	# The lines along the cylinder at +u, -u, +v and -v.
	for k in 4:
		var w := (u if k < 2 else v) * SIGNS[k % 2] * radius
		_line(xf.origin - axis * (half - radius) + w, xf.origin + axis * (half - radius) + w, color)
	# Each cap: half circles from the ring over the end of the capsule, in
	# the planes (axis, u) and (axis, v).
	for end: float in SIGNS:
		var c := xf.origin + axis * end * (half - radius)
		for plane in 2:
			var w := u if plane == 0 else v
			for k in 12:
				var a := PI * k / 12.0
				var b := PI * (k + 1) / 12.0
				_line(c + (w * cos(a) + axis * end * sin(a)) * radius, c + (w * cos(b) + axis * end * sin(b)) * radius, color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(a)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, color: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, color)
	_line(p - Vector3.BACK * r, p + Vector3.BACK * r, color)
	_line(p, p + Vector3.UP * r, color)
