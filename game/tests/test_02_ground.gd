extends SceneTree
## Lesson 02: checks the walker's ground contact in the physics engine.
## Five players walk at once, each on its own course, 40 m apart:
##   ramp 44   walks up a 44 degree ramp       -> reaches the platform (3 m)
##   ramp 46   walks into a 46 degree ramp     -> stays at ground level
##   step 9    walks onto a 9 cm step          -> stands on it
##   step 25   walks into a 25 cm step         -> stays at ground level
##   slide     walks at 0.5 m/s off a platform onto a 55 degree ramp with
##             steep_slide on -> enters STEEP, reaches the ground with
##             speed sqrt(2 g drop) within 5 %, and keeps a horizontal
##             velocity (the run-out) when it lands
## Also checks that scenes/sandbox.tscn keeps the Lesson 00 player options.
## The run takes about 5 seconds: physics steps in real time.
## Run: Godot --headless --path game -s res://tests/test_02_ground.gd

const SPACING := 40.0
const DURATION := 4.5

var _players: Dictionary = {}
var _max_height: Dictionary = {}
var _slide := {"steep_y": NAN, "landing_speed": NAN, "landing_horizontal": NAN, "last_speed": 0.0, "last_horizontal": 0.0}
var _time := 0.0
var _failures := 0


func _initialize() -> void:
	_check_sandbox_defaults()

	var world := Node3D.new()
	root.add_child(world)
	_add_ground(world)

	var ramp_44 := RampTower.new()
	ramp_44.ramp_angles_degrees = PackedFloat32Array([44.0, 30.0, 30.0, 30.0])
	_add_course(world, ramp_44, 0)
	_add_player(world, "ramp 44", Vector3(0.0, 0.0, 8.0), 0.0, 3.0)

	var ramp_46 := RampTower.new()
	ramp_46.ramp_angles_degrees = PackedFloat32Array([46.0, 30.0, 30.0, 30.0])
	_add_course(world, ramp_46, 1)
	_add_player(world, "ramp 46", Vector3(SPACING, 0.0, 8.0), 0.0, 3.0)

	var step_9 := StepRow.new()
	step_9.step_heights = PackedFloat32Array([0.09])
	_add_course(world, step_9, 2)
	_add_player(world, "step 9", Vector3(2.0 * SPACING, 0.0, 3.0), 0.0, 3.0)

	var step_25 := StepRow.new()
	step_25.step_heights = PackedFloat32Array([0.25])
	_add_course(world, step_25, 3)
	_add_player(world, "step 25", Vector3(3.0 * SPACING, 0.0, 3.0), 0.0, 3.0)

	var slide_tower := RampTower.new()
	slide_tower.ramp_angles_degrees = PackedFloat32Array([55.0, 30.0, 30.0, 30.0])
	_add_course(world, slide_tower, 4)
	# Yaw PI turns the camera, and so "forward", toward +z: off the 55 degree side.
	_add_player(world, "slide", Vector3(4.0 * SPACING, 3.0, 1.0), PI, 0.5)


func _physics_process(delta: float) -> bool:
	_time += delta
	Input.action_press("move_forward", 1.0)
	for key in _players:
		var player: Player = _players[key]
		_max_height[key] = maxf(_max_height.get(key, -INF), player.global_position.y)
	_track_slide(_players["slide"])
	if _time >= DURATION:
		Input.action_release("move_forward")
		_report()
		print("test_02_ground: %s" % ("passed" if _failures == 0 else "%d failure(s)" % _failures))
		quit(0 if _failures == 0 else 1)
	return false


func _track_slide(player: Player) -> void:
	var state := player.get_ground_state()
	var horizontal := Vector2(player.velocity.x, player.velocity.z).length()
	if is_nan(_slide["steep_y"]) and state == Player.GroundState.STEEP:
		_slide["steep_y"] = player.global_position.y
	elif not is_nan(_slide["steep_y"]) and is_nan(_slide["landing_speed"]) and state == Player.GroundState.FLOOR:
		# The landing tick has already removed the vertical part, so the
		# speed of the tick before is the speed at the bottom of the ramp.
		_slide["landing_speed"] = _slide["last_speed"]
		_slide["landing_horizontal"] = horizontal
		_slide["landing_y"] = player.global_position.y
	_slide["last_speed"] = player.velocity.length()


func _report() -> void:
	var platform: float = 3.0
	print("  ramp 44: highest point %.3f m" % _max_height["ramp 44"])
	_expect(_max_height["ramp 44"] > platform - 0.1, "44 degree ramp was not climbed")
	print("  ramp 46: highest point %.3f m" % _max_height["ramp 46"])
	_expect(_max_height["ramp 46"] < 0.05, "46 degree ramp was climbed")
	print("  step 9 cm: highest point %.3f m" % _max_height["step 9"])
	_expect(_max_height["step 9"] > 0.08, "9 cm step was not climbed")
	print("  step 25 cm: highest point %.3f m" % _max_height["step 25"])
	_expect(_max_height["step 25"] < 0.05, "25 cm step was climbed")

	var steep_y: float = _slide["steep_y"]
	_expect(not is_nan(steep_y), "slide player never entered the STEEP state")
	_expect(not is_nan(_slide["landing_speed"]), "slide player never landed on the floor")
	if is_nan(steep_y) or is_nan(_slide["landing_speed"]):
		return
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var drop: float = steep_y - _slide["landing_y"]
	var expected := sqrt(2.0 * gravity * drop)
	print("  slide: STEEP from y = %.3f, landed at y = %.3f, speed %.3f m/s (sqrt(2 g h) = %.3f), horizontal at landing %.3f m/s" % [
		steep_y, _slide["landing_y"], _slide["landing_speed"], expected, _slide["landing_horizontal"]])
	_expect(absf(_slide["landing_speed"] - expected) < 0.05 * expected, "slide speed does not match sqrt(2 g h)")
	_expect(_slide["landing_horizontal"] > 1.0, "slide lost its horizontal velocity on landing")


func _check_sandbox_defaults() -> void:
	var sandbox := (load("res://scenes/sandbox.tscn") as PackedScene).instantiate()
	var player: Player = sandbox.get_node("Player")
	_expect(player.stick_response == null, "sandbox player has a stick_response")
	_expect(player.blend_rule == Player.BlendRule.EXPONENTIAL, "sandbox player blend rule changed")
	_expect(not player.steep_slide, "sandbox player has steep_slide on")
	_expect(player.look_ahead_distance == 0.0, "sandbox player has look-ahead on")
	print("  sandbox player keeps the Lesson 00 options")
	sandbox.free()


func _add_ground(world: Node3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 100.0)
	collision.shape = shape
	body.add_child(collision)
	body.position = Vector3(100.0, -1.0, 0.0)
	world.add_child(body)


func _add_course(world: Node3D, course: Node3D, index: int) -> void:
	course.position = Vector3(index * SPACING, 0.0, 0.0)
	world.add_child(course)


func _add_player(world: Node3D, key: String, at: Vector3, yaw: float, speed: float) -> void:
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	player.position = at
	player.walk_speed = speed
	player.steep_slide = true
	world.add_child(player)
	player.get_node("CameraPivot").rotation.y = yaw
	_players[key] = player


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
