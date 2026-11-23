extends SceneTree
## Lesson 15: checks the Lesson 15 scene.
##   1. Nodes: ClimbFace is a ClimbableRock, Player a ClimbingPlayer,
##      BalanceMonitor a ClimbBalanceMonitor, Climb ticks after Player.
##   2. Holds: more than 40, at least 2 top-outs; each one on the surface
##      and inside every threshold; no two much closer than hold_spacing;
##      the world holds are the shape-space holds moved by the node, less
##      the ones below the terrain or within ground_clearance of it (the
##      two lowest knob rows have some).
##   3. Approach: begin_climb() refuses 1.2 m from the face and starts
##      0.5 m from it; the hands end on their hold targets.
##   4. Scripted climb: the triggers and the stick, steered toward the
##      highest hold in reach, move the hands; the feet follow. Every
##      tick: reach residual and limb errors near 0. The climb ends in a
##      mantle, and the player stands on the top of the rock, where
##      begin_climb() refuses ("behind the face").
##   5. Let go: the body falls to the ground and walks again.
##   6. Keys 0, F1, F2; 9 changes the tick rate and T does not (T and
##      D-pad up belong to Lesson 02's cycle_tick_rate);
##      the Lesson 14 scene has no Climb.
## The climbing ticks of step 4 are stepped by hand (ClimbController's
## _physics_process() called in a loop) so that 15 s of climbing take
## about 2 s; the controller behaves the same as in real time.
## Run: Godot --headless --path game -s res://tests/test_15_climb_scene.gd

const DT := 1.0 / 60.0

var _failures := 0
var _climb: ClimbController
var _player: ClimbingPlayer
var _worst_residual := 0.0
var _worst_hold_error := 0.0
var _climb_ticks := 0


func _initialize() -> void:
	await _check_scene()
	print("test_15_climb_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	var scene: Node = (load("res://scenes/lessons/15_climbing.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	# 1. Nodes.
	var face := scene.get_node("ClimbFace") as ClimbableRock
	_climb = scene.get_node("Climb") as ClimbController
	_player = scene.get_node("Player") as ClimbingPlayer
	var monitor := scene.get_node("BalanceMonitor") as ClimbBalanceMonitor
	_expect(face != null and _climb != null and _player != null and monitor != null, "ClimbFace, Climb, ClimbingPlayer, ClimbBalanceMonitor")
	if face == null or _climb == null or _player == null or monitor == null:
		scene.queue_free()
		return
	_expect(_climb.get_index() > _player.get_index() and _climb.process_physics_priority == _player.process_physics_priority, "Climb ticks after Player")
	_expect(_player.rig is FootRig, "the player keeps the FootRig")

	# 2. Holds.
	var c := face.criteria()
	_expect(face.holds.size() > 40, "holds: %d" % face.holds.size())
	var top_outs := face.local_holds.filter(func(h: HoldFinder.Hold) -> bool: return h.top_out).size()
	_expect(top_outs >= 2, "top-outs: %d" % top_outs)
	var worst_f := 0.0
	var inside := true
	for hold in face.local_holds:
		worst_f = maxf(worst_f, absf(face.shape.evaluate(hold.position)))
		inside = inside and hold.mean >= c.min_mean and hold.mean <= c.max_mean and hold.gradient_length >= c.min_gradient \
				and hold.normal.y >= c.min_up and hold.normal.dot(c.face) >= c.min_facing
	_expect(worst_f < 1e-3, "holds on the surface: largest |f| %f" % worst_f)
	_expect(inside, "every hold inside the thresholds")
	var closest := INF
	for i in face.local_holds.size():
		for j in i:
			closest = minf(closest, face.local_holds[i].position.distance_to(face.local_holds[j].position))
	# Suppression runs before refinement, which moves a hold by a few
	# centimeters; the pairs may end closer than the spacing by up to the
	# sum of two such moves.
	_expect(closest >= c.spacing - 0.05, "holds apart: closest %f" % closest)
	var terrain := scene.get_node("Terrain") as Terrain
	var moved := true
	var next := 0
	var buried := 0
	for local in face.local_holds:
		var world := face.global_transform * local.position
		if world.y < terrain.height_at(world.x, world.z) + face.ground_clearance:
			buried += 1
			continue
		moved = moved and next < face.holds.size() and face.holds[next].position.is_equal_approx(world)
		next += 1
	_expect(moved and next == face.holds.size(), "world holds = node transform * shape-space holds above the terrain")
	_expect(buried > 0 and buried == face.buried_count, "holds at or below the terrain left out: %d (buried_count %d)" % [buried, face.buried_count])

	# 3. Approach.
	var front := face.global_transform * Vector3(0, 0, 0.6)
	await _stand_at(front + face.face_normal_world() * 1.2, terrain)
	_expect(not _climb.begin_climb() and _climb.refusal == "face too far", "1.2 m away: refused (%s)" % _climb.refusal)
	await _stand_at(front + face.face_normal_world() * 0.5, terrain)
	_expect(_climb.begin_climb(), "0.5 m away: climbing (%s)" % _climb.refusal)
	_expect(_player.climbing, "the player hands over its body")
	await physics_frame
	await physics_frame
	var skeleton := _player.rig.skeleton()
	skeleton.force_update_all_bone_transforms()
	for hand in 2:
		var bone := skeleton.find_bone("LowerArm." + FootRig.SIDE_NAMES[hand])
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var end := pose * Vector3(0, -_player.rig.proportions.forearm_length, 0)
		var target := _climb.limb_target(hand, _climb.limbs[hand].hold)
		_expect(end.distance_to(target) < 0.01, "hand %d on its hold: %f m" % [hand, end.distance_to(target)])

	# 4. Scripted climb, stepped by hand.
	_climb.set_physics_process(false)
	var start_height := _climb.pelvis.y
	await _settle()
	var reaches := 0
	var hand := 0
	while _climb.state == ClimbController.State.CLIMBING and reaches < 30:
		var got := _reach(hand)
		reaches += 1
		if not got:
			got = _reach(1 - hand)
			reaches += 1
			if not got:
				break
		hand = 1 - hand
		await process_frame
	_climb.set_physics_process(true)
	_expect(_climb.hand_moves >= 6, "hand moves: %d" % _climb.hand_moves)
	_expect(_climb.foot_moves >= 6, "foot moves: %d" % _climb.foot_moves)
	_expect(_worst_residual < 1e-3, "reach residual on every tick: %f" % _worst_residual)
	_expect(_worst_hold_error < 0.02, "limb errors on every tick: %f" % _worst_hold_error)
	_expect(_climb.state != ClimbController.State.CLIMBING, "the climb ended (state %s, ascent %.2f)" % [ClimbController.STATE_NAMES[_climb.state], _climb.ascent])
	for k in 120:
		await physics_frame
	var top := (face.global_transform * Vector3(0, 4.4, 0)).y
	_expect(_climb.state == ClimbController.State.WALKING, "walking after the mantle")
	_expect(not _player.climbing, "the player has its body back")
	_expect(_player.global_position.y > top - 0.1, "standing on the top: y %.3f, top %.3f" % [_player.global_position.y, top])
	_expect(_player.global_position.y - (start_height - 0.94) > 4.0, "ascent above 4 m")
	_expect(_player.is_on_floor(), "on the floor")
	_expect(not _climb.begin_climb() and _climb.refusal == "behind the face", "on the top: refused (%s)" % _climb.refusal)

	# 5. Let go.
	await _stand_at(front + face.face_normal_world() * 0.5, terrain)
	_expect(_climb.begin_climb(), "second climb")
	_climb.set_physics_process(false)
	await _settle()
	_reach(0)
	_reach(1)
	_climb.set_physics_process(true)
	var lifted := _player.global_position.y - terrain.height_at(_player.global_position.x, _player.global_position.z)
	scene._unhandled_input(_key(KEY_0))
	_expect(_climb.state == ClimbController.State.WALKING and not _player.climbing, "key 0 lets go")
	for k in 90:
		await physics_frame
	var height := _player.global_position.y - terrain.height_at(_player.global_position.x, _player.global_position.z)
	_expect(lifted > 0.5 and height < 0.1, "fell from %.2f m to %.3f m above the terrain" % [lifted, height])
	_expect(_player.is_on_floor(), "landed")
	_expect(_climb.face_distance(_player.global_position) >= 0.44, "landed clear of the face: %f" % _climb.face_distance(_player.global_position))

	# 6. Keys.
	var lines := _climb.debug_draw
	scene._unhandled_input(_key(KEY_F1))
	_expect(_climb.debug_draw != lines and face.show_holds == _climb.debug_draw, "F1 toggles the lines and the holds")
	var solver := _climb.arm_solver
	scene._unhandled_input(_key(KEY_F2))
	_expect(_climb.arm_solver != solver, "F2 switches the arm solver")
	scene._unhandled_input(_key(KEY_F2))
	await _stand_at(front + face.face_normal_world() * 0.5, terrain)
	scene._unhandled_input(_key(KEY_0))
	_expect(_climb.state == ClimbController.State.CLIMBING, "key 0 starts a climb")
	scene._unhandled_input(_key(KEY_0))
	_expect(_climb.state == ClimbController.State.WALKING, "key 0 again lets go")
	var ticks := Engine.physics_ticks_per_second
	scene._unhandled_input(_key(KEY_T))
	_expect(Engine.physics_ticks_per_second == ticks, "T leaves the tick rate alone")
	scene._unhandled_input(_key(KEY_9))
	_expect(Engine.physics_ticks_per_second != ticks, "9 changes the tick rate")
	Engine.physics_ticks_per_second = ticks
	_expect(_has_key(&"cycle_tick_rate", KEY_T) and _has_button(&"cycle_tick_rate", JOY_BUTTON_DPAD_UP), "cycle_tick_rate on T and D-pad up (Lesson 02)")
	_expect(_has_key(&"cycle_stance_tick_rate", KEY_9) and not _has_key(&"cycle_tick_rate", KEY_9), "cycle_stance_tick_rate on 9 (Lesson 14)")

	scene.queue_free()
	await process_frame

	var old: Node = (load("res://scenes/lessons/14_analog_stances.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Climb") == null and not old.get_node("Player") is ClimbingPlayer, "Lesson 14 scene has no climbing")
	old.free()


## Places the player at a point on the terrain and lets it settle.
func _stand_at(point: Vector3, terrain: Terrain) -> void:
	point.y = terrain.height_at(point.x, point.z) + 0.2
	_player.global_position = point
	_player.velocity = Vector3.ZERO
	for k in 40:
		await physics_frame


## One climbing tick, stepped by hand.
func _tick() -> void:
	_player._read_stick()
	_climb._physics_process(DT)
	if _climb.state != ClimbController.State.CLIMBING:
		return
	_climb_ticks += 1
	_worst_residual = maxf(_worst_residual, _climb.residual)
	for i in 4:
		_worst_hold_error = maxf(_worst_hold_error, _climb.limb_errors[i])


## Ticks until no limb has moved for three ticks (at most 5 s).
func _settle() -> void:
	var quiet := 0
	for k in 300:
		_tick()
		if _climb.state != ClimbController.State.CLIMBING:
			return
		quiet = quiet + 1 if _climb._moving_limb() < 0 else 0
		if quiet >= 3:
			return


## One reach of a hand: the trigger is held, the stick steers the hand
## toward the highest free hold within 0.25 m of the arm's reach, and the
## trigger is released when the controller's candidate is that hold.
## Returns whether it was grabbed.
func _reach(hand: int) -> bool:
	var limb := _climb.limbs[hand]
	var shoulder := _climb.limb_root(hand, _climb.pelvis)
	var target: HoldFinder.Hold
	for hold in HoldFinder.in_reach(_climb.rock.holds, shoulder, _climb.limb_reach(hand) + 0.25, shoulder, _climb._used_holds(hand)):
		if hold.position.y > limb.hold.position.y + 0.05 and (target == null or hold.position.y > target.position.y):
			target = hold
	if target == null:
		return false
	var action: String = ClimbController.REACH_ACTIONS[hand]
	Input.action_press(action, 1.0)
	var got := false
	for k in 120:
		_tick()
		if limb.state != ClimbController.LimbState.REACH:
			continue
		if _climb.candidate == target:
			got = true
			break
		var basis := _climb.body_basis()
		var offset := target.position - limb.point
		var on_face := Vector2(offset.dot(basis.x), offset.dot(basis.y))
		_set_stick(on_face.normalized() * clampf(on_face.length() / 0.15, 0.3, 1.0))
	_set_stick(Vector2.ZERO)
	Input.action_release(action)
	_settle()
	return got


## Presses the move actions so that the stick reads x to the right and y
## up the face (Input.get_vector() has forward = -y).
func _set_stick(s: Vector2) -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)
	if s.x > 0.0:
		Input.action_press("move_right", s.x)
	elif s.x < 0.0:
		Input.action_press("move_left", -s.x)
	if s.y > 0.0:
		Input.action_press("move_forward", s.y)
	elif s.y < 0.0:
		Input.action_press("move_back", -s.y)


## Whether an action lists a key (by physical keycode) among its events.
func _has_key(action: StringName, code: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


## Whether an action lists a gamepad button among its events.
func _has_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
