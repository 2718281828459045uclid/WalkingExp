class_name Player
extends CharacterBody3D
## Placeholder walker: a capsule moved by analog input, with an orbit camera.
##
## Scene layout (scenes/player.tscn):
##   Player (CharacterBody3D, this script)
##     CollisionShape3D     capsule the physics engine collides
##     BodyMesh             visible capsule + a "nose" box showing facing
##     CameraPivot          rotates for yaw and pitch
##       SpringArm3D        pulls the camera in when terrain blocks the view
##         Camera3D
##
## A CharacterBody3D is "kinematic": physics does not push it around.
## The script sets velocity, and move_and_slide() moves the body along that
## velocity, sliding along whatever it touches. Phase 4 of the roadmap
## replaces the capsule with a procedural skeleton, IK, and a balance model;
## docs/decisions/0002-character-model.md records why.
##
## Lesson 02 added the exported options in the groups marked "Lesson 02".
## Their defaults keep the Lesson 00 behavior, which scenes/sandbox.tscn
## uses. scenes/lessons/02_walking_on_a_surface.tscn turns them on.

## Rule for the per-tick blend factor in the velocity smoothing.
enum BlendRule {
	EXPONENTIAL,  ## 1 - exp(-k dt): the exact solution of dv/dt = k (target - v).
	LINEAR,       ## k dt: one explicit Euler step. Depends on the tick rate.
}

## What the capsule stood on after the last move_and_slide().
enum GroundState {
	FLOOR,  ## Contact no steeper than floor_max_angle: walkable.
	STEEP,  ## Contact steeper than floor_max_angle but not a vertical wall.
	AIR,    ## No supporting contact.
}

## A wall contact whose normal has a y component above this value counts
## as steep ground (normal less than about 87 degrees from up).
const STEEP_NORMAL_MIN_Y := 0.05

@export_group("Movement")
## Target speed at full stick deflection, in meters per second.
@export var walk_speed: float = 3.0
## How quickly velocity approaches the target, in 1/seconds.
@export var responsiveness: float = 8.0

@export_group("Movement (Lesson 02)")
## Deadzones and response curve for the left stick. Empty: Godot's
## built-in radial deadzone with a linear response (Lesson 00).
@export var stick_response: StickResponse
## Blend rule for the velocity smoothing. LINEAR exists for comparison.
@export var blend_rule: BlendRule = BlendRule.EXPONENTIAL

@export_group("Ground (Lesson 02)")
## When true, steep ground does not hold the body: the stick has no grip
## on it, and gravity accelerates the body down along the surface.
@export var steep_slide: bool = false

@export_group("Camera")
## Radians per second at full right-stick deflection.
@export var stick_look_speed: float = 2.5
## Radians per pixel of mouse motion.
@export var mouse_look_speed: float = 0.003
@export var pitch_min_degrees: float = -70.0
@export var pitch_max_degrees: float = 20.0

@export_group("Camera look-ahead (Lesson 02)")
## Distance ahead of the player, in meters, at which the ground is sampled.
## 0 turns look-ahead off.
@export var look_ahead_distance: float = 0.0
## Fraction of the slope angle ahead that is added to the camera pitch.
@export_range(0.0, 1.0) var look_ahead_gain: float = 0.5
## Rate at which the camera pitch follows the ground, in 1/seconds.
@export var look_ahead_responsiveness: float = 3.0

## Stick vector of the last physics tick before shaping (no deadzone).
var stick_raw := Vector2.ZERO
## Stick vector of the last physics tick after the deadzone and curve.
var stick_shaped := Vector2.ZERO

@onready var _body_mesh: Node3D = $BodyMesh
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _ground_state := GroundState.AIR

# Q: Why keep one ray query for the whole life of the player?
# A: With look-ahead on, _ground_height_below() casts two rays on every
#    physics tick. Creating a new query and a new exclude array for each
#    ray allocates four objects per tick. The excluded body never changes,
#    so the query is built once and each ray changes only its endpoints.
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	# The spring arm casts a ray from the pivot to the camera. Without this
	# line the ray hits the player's own capsule and the camera collapses
	# into the player's head.
	_spring_arm.add_excluded_object(get_rid())
	# The look-ahead rays (Lesson 02) skip the capsule for the same reason.
	_ray_query.exclude = [get_rid()]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_rotate_camera(-motion.relative.x * mouse_look_speed, -motion.relative.y * mouse_look_speed)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_rotate_camera(-look.x * stick_look_speed * delta, -look.y * stick_look_speed * delta)

	# Q: Which way is "forward" when the stick is pushed up?
	# A: The direction the camera faces, flattened onto the ground plane.
	#    The stick vector is expressed in the camera's yaw frame
	#    (-z = forward, +x = right), then rotated into world space.
	var stick := _read_stick()
	var camera_yaw := Basis(Vector3.UP, _camera_pivot.rotation.y)
	var wish := camera_yaw * Vector3(stick.x, 0.0, stick.y)

	# Q: Why not normalize "wish"?
	# A: Its length (0 to 1) is the analog part of the input. Half
	#    deflection should mean half speed. Normalizing throws that away.
	var target := wish * walk_speed

	var blend := blend_factor(responsiveness, delta, blend_rule)

	# Q: Why skip the blend while sliding?
	# A: The blend pulls the horizontal velocity toward the stick target.
	#    On steep ground that would act as grip: with the stick released it
	#    pulls the slide toward zero. Skipping it leaves gravity in charge.
	var sliding := steep_slide and _ground_state == GroundState.STEEP
	if not sliding:
		velocity.x = lerpf(velocity.x, target.x, blend)
		velocity.z = lerpf(velocity.z, target.z, blend)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	move_and_slide()
	_update_ground_state()

	# Q: Why remove part of the velocity after move_and_slide()?
	# A: Gravity added a vertical velocity. On steep ground the surface
	#    stops the part of it that points into the surface (along -n) and
	#    leaves the part along the surface. velocity.slide(n) keeps the
	#    tangential part: v - (v . n) n. What remains accelerates the body
	#    down the slope at g sin(angle), as on a frictionless incline.
	if steep_slide and _ground_state == GroundState.STEEP:
		var n := get_wall_normal()
		if velocity.dot(n) < 0.0:
			velocity = velocity.slide(n)

	# Turn the visible body toward the direction of travel.
	# Q: Why atan2(-x, -z)?
	# A: Godot treats -z as a node's forward axis. A rotation by angle a
	#    about +y sends (0, 0, -1) to (-sin a, 0, -cos a). Solve for a.
	if wish.length() > 0.1:
		var facing := atan2(-wish.x, -wish.z)
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, facing, blend)

	_update_look_ahead(delta)


## Fraction of the remaining distance to the target covered in one tick.
##
## Q: Why 1 - exp(-k * dt) and not k * dt?
## A: Blending by k * dt makes the result depend on frame rate, and it
##    overshoots when k * dt > 1. The exponential form gives the same
##    approach curve at 30, 60, or 144 frames per second. It is the exact
##    solution of dv/dt = k * (target - v) over one time step.
static func blend_factor(rate: float, delta: float, rule: BlendRule = BlendRule.EXPONENTIAL) -> float:
	if rule == BlendRule.LINEAR:
		return rate * delta
	return 1.0 - exp(-rate * delta)


func get_ground_state() -> GroundState:
	return _ground_state


func _read_stick() -> Vector2:
	# The deadzone argument 0.0 turns off Godot's radial deadzone, so the
	# raw vector reaches the HUD and the StickResponse unchanged.
	stick_raw = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
	if stick_response == null:
		stick_shaped = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	else:
		stick_shaped = stick_response.apply(stick_raw)
	return stick_shaped


func _update_ground_state() -> void:
	if is_on_floor():
		_ground_state = GroundState.FLOOR
	elif is_on_wall() and get_wall_normal().y > STEEP_NORMAL_MIN_Y:
		_ground_state = GroundState.STEEP
	else:
		_ground_state = GroundState.AIR


## Tilts the spring arm toward the slope of the ground ahead.
##
## Q: How steep is the ground ahead, along the camera's direction u?
## A: The directional derivative D_u h = grad(h) . u answers that at one
##    point. Here it is estimated by a secant over a long baseline L:
##      (h(p + L u) - h(p)) / L
##    Both heights come from rays cast down onto the collision geometry,
##    so the estimate works on any ground, not only on a HeightField.
##    A long baseline averages out small bumps and looks where the player
##    is going rather than where the player stands.
func _update_look_ahead(delta: float) -> void:
	if look_ahead_distance <= 0.0:
		return
	var forward := Basis(Vector3.UP, _camera_pivot.rotation.y) * Vector3.FORWARD
	var here := _ground_height_below(global_position)
	var ahead := _ground_height_below(global_position + forward * look_ahead_distance)

	var target_pitch := 0.0
	if not (is_nan(here) or is_nan(ahead)):
		var slope_ahead := (ahead - here) / look_ahead_distance
		target_pitch = look_ahead_gain * atan(slope_ahead)

	var blend := blend_factor(look_ahead_responsiveness, delta)
	_spring_arm.rotation.x = lerp_angle(_spring_arm.rotation.x, target_pitch, blend)


## Height of the first surface below (or at) a point, or NAN if the ray misses.
func _ground_height_below(point: Vector3) -> float:
	# Q: Why start the ray above the point?
	# A: Ground ahead may be higher than the feet (uphill). The ray spans
	#    look_ahead_distance + 2 m above and below, enough for slopes up
	#    to 45 degrees over the baseline.
	var reach := look_ahead_distance + 2.0
	_ray_query.from = point + Vector3.UP * reach
	_ray_query.to = point + Vector3.DOWN * reach
	_ray_query.collision_mask = collision_mask
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return NAN
	return hit.position.y


func _rotate_camera(yaw_delta: float, pitch_delta: float) -> void:
	_camera_pivot.rotation.y += yaw_delta
	_camera_pivot.rotation.x = clampf(
		_camera_pivot.rotation.x + pitch_delta,
		deg_to_rad(pitch_min_degrees),
		deg_to_rad(pitch_max_degrees)
	)
