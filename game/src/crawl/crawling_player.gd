class_name CrawlingPlayer
extends ClimbingPlayer
## A ClimbingPlayer that can lower its body (Lesson 16): three collision
## shapes, and a low movement mode for crawling and scrambling.
##
## How the files relate:
##   Player (Lesson 00-02)          walks, falls, turns the camera
##   BodyPlayer (Lesson 11)         feeds the FootRig with the distance walked
##   ClimbingPlayer (Lesson 15)     hands its body to a ClimbController
##   this file                      owns the collision shapes and the low
##                                  movement; tests whether a shape fits
##   PostureController              decides the posture, asks fits(), then
##     (posture_controller.gd)      calls set_body_shape() and sets `mode`
##   CrawlController                poses the body while `mode` is CRAWL or
##     (crawl_controller.gd)        SCRAMBLE and sets speed_scale
##   scenes/crawling_player.tscn    a copy of climbing_player.tscn with this
##                                  script
##
## The three shapes (README section 2, P1):
##   STAND   the scene's capsule: radius 0.35 m, height 1.8 m, upright
##   CROUCH  an upright capsule of the same radius, crouch_height tall
##   CRAWL   a capsule lying along the body's facing: radius crawl_radius,
##           length crawl_length, its lowest point at the player's height,
##           its center crawl_offset behind the origin
## Each shape encloses the body drawn in that posture (README P1, O1):
## the crouched head reaches 1.52 m while walking, the crawling body
## 0.69 m high and from 1.02 m behind the origin to 0.57 m ahead of it.
##
## The three movement modes:
##   UPRIGHT   Player's walking (Lessons 00-14) and FootRig's legs
##   CRAWL     slow, along the facing; the body turns at turn_rate, and only
##             when the turned shape fits
##   SCRAMBLE  slow, in any direction over the slab; the body faces up the
##             slope; floor_max_angle rises to scramble_max_angle_degrees

## The movement modes.
enum Mode {
	UPRIGHT,
	CRAWL,
	SCRAMBLE,
}

## The collision shapes.
enum BodyShape {
	STAND,
	CROUCH,
	CRAWL,
}

const MODE_NAMES: PackedStringArray = ["upright", "crawl", "scramble"]
const SHAPE_NAMES: PackedStringArray = ["stand", "crouch", "crawl"]

@export_group("Shapes (Lesson 16)")
## Total height of the upright capsule while crouched, meters.
@export var crouch_height: float = 1.55
## Radius of the lying capsule, meters.
@export var crawl_radius: float = 0.35
## Length of the lying capsule from end to end, meters.
@export var crawl_length: float = 1.65
## Distance of the lying capsule's center behind the origin, meters. The
## origin lies between the hands and the knees; the shins and feet trail
## behind the knees, so the body reaches farther back than forward.
@export var crawl_offset: float = 0.225
## A shape is tested this far above its place, meters, so that the floor
## it stands on does not count as an obstacle.
@export var fit_lift: float = 0.02
@export_group("Low movement (Lesson 16)")
## Speed at full stick while crawling, m/s.
@export var crawl_speed: float = 0.6
## Speed at full stick while scrambling, m/s.
@export var scramble_speed: float = 0.45
## Largest turn rate of the body in the low modes, radians per second.
@export var turn_rate: float = 2.5
## floor_max_angle while scrambling, degrees.
@export_range(30.0, 80.0, 0.5) var scramble_max_angle_degrees: float = 55.0
@export_group("Camera heights (Lesson 16)")
## Height of the camera pivot for each shape (stand, crouch, crawl),
## meters. The first entry is read from the scene at start.
@export var camera_heights := PackedFloat32Array([1.5, 1.2, 0.7])
## Rate at which the pivot follows its height, 1/seconds.
@export var camera_responsiveness: float = 6.0

## The movement mode. PostureController sets it.
var mode := Mode.UPRIGHT:
	set(value):
		if value == mode:
			return
		mode = value
		_on_mode_changed()
## The collision shape in use.
var body_shape := BodyShape.STAND
## Multiplies the low speeds. CrawlController sets it to 0 while a limb
## waits for the body to balance over the others.
var speed_scale := 1.0
## Steepest surface under the body in the last tick, degrees (NAN in the
## air).
var floor_angle_degrees := NAN
## Whether the last low-mode tick wanted to turn and the turned shape did
## not fit.
var turn_blocked := false

@onready var _collision: CollisionShape3D = $CollisionShape3D

var _shapes: Array[Shape3D] = []
var _walk_max_angle := 0.0
# Q: Why keep the queries for the life of the player?
# A: The HUD asks for the headroom on every frame, and the posture
#    controller tests shapes and probes the ground ahead on every tick. As
#    with Player._ray_query (Lesson 02), the excluded body never changes;
#    only the shape, the transform or the end points do.
var _fit_query := PhysicsShapeQueryParameters3D.new()
var _headroom_query := PhysicsShapeQueryParameters3D.new()
var _ground_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	super()
	_walk_max_angle = floor_max_angle
	camera_heights[BodyShape.STAND] = _camera_pivot.position.y
	# Q: Why build the crouch and crawl shapes here and keep the stand
	#    shape from the scene?
	# A: The stand shape is the one every earlier lesson used; reading it
	#    keeps it the reference. The others follow from the exports, so a
	#    change in the Inspector changes the shape. The scene's capsule
	#    is a sub-resource; it is not edited, only swapped out.
	var stand := _collision.shape as CapsuleShape3D
	var crouch := CapsuleShape3D.new()
	crouch.radius = stand.radius
	crouch.height = crouch_height
	var crawl := CapsuleShape3D.new()
	crawl.radius = crawl_radius
	crawl.height = crawl_length
	_shapes = [stand, crouch, crawl]
	_fit_query.exclude = [get_rid()]
	_fit_query.collision_mask = collision_mask
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	_headroom_query.shape = sphere
	_headroom_query.exclude = [get_rid()]
	_headroom_query.collision_mask = collision_mask
	_ground_query.exclude = [get_rid()]
	_ground_query.collision_mask = collision_mask


func _physics_process(delta: float) -> void:
	_follow_camera_height(delta)
	if mode == Mode.UPRIGHT:
		super(delta)
		floor_angle_degrees = rad_to_deg(get_floor_normal().angle_to(Vector3.UP)) if is_on_floor() else NAN
		return
	_low_move(delta)


# --- Shapes ---------------------------------------------------------------

## Height of a shape's top above the player's origin, meters.
func shape_height(shape: BodyShape) -> float:
	var capsule := _shapes[shape] as CapsuleShape3D
	return 2.0 * capsule.radius if shape == BodyShape.CRAWL else capsule.height


## Where a shape sits relative to the player's origin, for a body that
## faces the angle yaw (radians about +y; 0 faces -z).
##
## Q: A CapsuleShape3D lies along its own y axis. How does it lie down
##    along the facing?
## A: A quarter turn about +x sends +y to +z: the capsule now lies along
##    z, the axis the body faces along. The turn about +y by yaw then
##    points it where the body faces. The center rises by the radius, so
##    the lowest line of the capsule lies at the origin's height, and
##    moves crawl_offset backward (+z before the turn, since the body
##    faces -z), so that the capsule covers the trailing shins and feet.
func shape_transform(shape: BodyShape, yaw: float) -> Transform3D:
	var capsule := _shapes[shape] as CapsuleShape3D
	if shape == BodyShape.CRAWL:
		var turn := Basis(Vector3.UP, yaw)
		var lying := turn * Basis(Vector3.RIGHT, PI * 0.5)
		return Transform3D(lying, Vector3(0.0, capsule.radius, 0.0) + turn * Vector3(0.0, 0.0, crawl_offset))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5 * capsule.height, 0.0))


## Radius of a shape, meters.
func shape_radius(shape: BodyShape) -> float:
	return (_shapes[shape] as CapsuleShape3D).radius


## Whether a shape fits at the player's position without touching
## anything, for a body facing yaw.
##
## Q: Why test the shape before using it?
## A: A collision shape that appears inside a roof or a wall is not
##    pushed out by move_and_slide() in a useful direction: the solver
##    separates the overlap along whatever normal it finds, which can be
##    down through the floor or sideways into the wall. Growing taller
##    under a roof, or turning a long shape in a narrow gap, is a move,
##    and a move into geometry is refused before it happens.
## Q: What does fit_lift do?
## A: The body rests on the floor; a shape placed on it, with no gap, touches
##    it, and a touch counts as an overlap within the solver's margin.
##    The test lifts the shape by fit_lift (2 cm). A roof lower than
##    shape height + fit_lift counts as touching.
func fits(shape: BodyShape, yaw: float = NAN) -> bool:
	if is_nan(yaw):
		yaw = _body_mesh.rotation.y
	_fit_query.shape = _shapes[shape]
	_fit_query.transform = global_transform * shape_transform(shape, yaw)
	_fit_query.transform.origin += Vector3.UP * fit_lift
	return get_world_3d().direct_space_state.intersect_shape(_fit_query, 1).is_empty()


## Puts a shape in place. PostureController calls fits() first.
func set_body_shape(shape: BodyShape) -> void:
	body_shape = shape
	_collision.shape = _shapes[shape]
	_collision.transform = shape_transform(shape, _body_mesh.rotation.y)


## Free height above the player's origin, meters, up to `limit`.
##
## Q: How is it measured?
## A: A sphere of radius 0.25 m is swept straight up from just above the
##    origin (cast_motion() returns the fraction of the sweep that is
##    free). The free height is where the sweep stops plus the sphere's
##    top. It is the number to compare with shape_height(): standing up
##    needs headroom above the stand shape's 1.8 m.
func headroom(limit: float = 2.5) -> float:
	var radius := (_headroom_query.shape as SphereShape3D).radius
	var start := radius + fit_lift
	_headroom_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * start)
	var travel := limit - start - radius
	_headroom_query.motion = Vector3.UP * travel
	var free: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(_headroom_query)
	return start + travel * free[0] + radius


## floor_max_angle of the upright body (Lesson 02: 45 degrees), degrees.
func walk_max_angle_degrees() -> float:
	return rad_to_deg(_walk_max_angle)


# --- Directions -------------------------------------------------------------

## The stick as a horizontal world direction, relative to the camera, of
## length 0 to 1 (Player._physics_process() computes the same vector).
func wish_direction() -> Vector3:
	var camera_yaw := Basis(Vector3.UP, _camera_pivot.rotation.y)
	return camera_yaw * Vector3(stick_shaped.x, 0.0, stick_shaped.y)


## The horizontal direction the body faces.
func facing() -> Vector3:
	return Basis(Vector3.UP, _body_mesh.rotation.y) * Vector3.FORWARD


## The ground under a point `distance` ahead along a horizontal direction:
## the hit of a ray cast down from 1.5 m above the origin's height to
## 1.5 m below it, or {} on a miss.
func ground_ahead(direction: Vector3, distance: float) -> Dictionary:
	var point := global_position + direction.normalized() * distance
	_ground_query.from = point + Vector3.UP * 1.5
	_ground_query.to = point + Vector3.DOWN * 1.5
	return get_world_3d().direct_space_state.intersect_ray(_ground_query)


# --- Low movement ---------------------------------------------------------

func _low_move(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_rotate_camera(-look.x * stick_look_speed * delta, -look.y * stick_look_speed * delta)
	_read_stick()
	var wish := wish_direction()
	var target := Vector3.ZERO
	if mode == Mode.CRAWL:
		target = _crawl_velocity(wish, delta)
	else:
		target = _scramble_velocity(wish, delta)
	var blend := blend_factor(responsiveness, delta, blend_rule)
	# Q: Why stop at once when speed_scale is 0?
	# A: speed_scale 0 means a limb waits for the balance before it lifts.
	#    With the blend of Lesson 02 the body would coast on for about
	#    0.3 s (1 / responsiveness, a few centimeters), carrying the
	#    planted limbs farther behind than the gait allows. A body on
	#    hands and knees moves at a low speed and stops within a tick.
	if speed_scale <= 0.0:
		blend = 1.0
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var before := global_position
	move_and_slide()
	_update_ground_state()
	floor_angle_degrees = rad_to_deg(get_floor_normal().angle_to(Vector3.UP)) if is_on_floor() else NAN
	# BodyPlayer's bookkeeping, so that walking resumes without a jump in
	# the walk phase.
	var moved := global_position - before
	moved.y = 0.0
	ground_speed = moved.length() / delta
	_last_position = global_position


## CRAWL: turn toward the stick when the turned shape fits, then move
## along the facing.
##
## Q: Why move along the facing and not along the stick?
## A: A body on hands and knees moves forward or backward; a sideways
##    shuffle of the long shape would also sweep it into walls the turn
##    test never checked. The speed is the stick's component along the
##    facing: a stick pointing sideways turns the body first and moves it
##    little. A stick pointing behind the body backs it up without a turn,
##    the way one backs out of a crawl space.
## Q: Where does "behind" begin?
## A: Where wish . facing < -0.1 for a full stick: more than 96 degrees
##    from the facing. After a turn of 14 degrees in the passage, the
##    opposite sideways stick points 104 degrees from the facing, and the
##    body backs up at 0.6 sin(14 degrees) = 0.15 m/s instead of turning
##    back. The stick pushed along the passage turns it back (README O4).
func _crawl_velocity(wish: Vector3, delta: float) -> Vector3:
	var yaw := _body_mesh.rotation.y
	turn_blocked = false
	# Q: Why does a waiting limb (speed_scale 0) block the turn?
	# A: Turning on the spot moves the shoulders and hips away from the
	#    planted contacts. While a limb waits, the gait phase stands
	#    still, so no limb steps to follow the turn.
	if speed_scale > 0.0 and wish.length() > 0.1 and wish.dot(facing()) > -0.1:
		var wanted := atan2(-wish.x, -wish.z)
		var step := clampf(angle_difference(yaw, wanted), -turn_rate * delta, turn_rate * delta)
		if absf(step) > 1e-5:
			if fits(BodyShape.CRAWL, yaw + step):
				_turn_body(yaw + step)
			else:
				turn_blocked = true
	return facing() * wish.dot(facing()) * crawl_speed * speed_scale


## SCRAMBLE: face up the slope, move in any direction.
##
## Q: Which way is up the slope?
## A: Against the horizontal part of the floor normal. For a graph
##    y = h(x, z) the normal is proportional to (-h_x, 1, -h_z) (Lesson
##    01), so its horizontal part is minus the gradient of h, and the
##    gradient points up the slope (DDG section 4.6.1). The body turns
##    toward -(n_x, 0, n_z). On flat ground the horizontal part is zero
##    and the facing stays.
func _scramble_velocity(wish: Vector3, delta: float) -> Vector3:
	if is_on_floor() and speed_scale > 0.0:
		var n := get_floor_normal()
		var downhill := Vector3(n.x, 0.0, n.z)
		if downhill.length() > 0.05:
			var uphill := -downhill.normalized()
			var wanted := atan2(-uphill.x, -uphill.z)
			var yaw := _body_mesh.rotation.y
			var step := clampf(angle_difference(yaw, wanted), -turn_rate * delta, turn_rate * delta)
			_turn_body(yaw + step)
	return wish * scramble_speed * speed_scale


func _turn_body(yaw: float) -> void:
	_body_mesh.rotation.y = yaw
	_collision.transform = shape_transform(body_shape, yaw)


## Q: What must change when the mode changes?
## A: Three things. floor_max_angle: scrambling makes the slab a floor.
##    The FootRig's planted feet: they stay where they were planted while
##    the rig is not advanced, so they are released, and FootRig plants
##    them under the hips on its first walking tick (Lesson 15 does the
##    same). The last position: BodyPlayer turns the distance moved into
##    walk phase.
func _on_mode_changed() -> void:
	floor_max_angle = deg_to_rad(scramble_max_angle_degrees) if mode == Mode.SCRAMBLE else _walk_max_angle
	speed_scale = 1.0
	turn_blocked = false
	_last_position = global_position
	var foot_rig := rig as FootRig
	if foot_rig != null:
		for foot in foot_rig.feet:
			foot.planted = false


func _follow_camera_height(delta: float) -> void:
	var wanted := camera_heights[body_shape]
	_camera_pivot.position.y = lerpf(_camera_pivot.position.y, wanted, blend_factor(camera_responsiveness, delta))
