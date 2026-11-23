extends SceneTree
## Lesson 16: checks the Lesson 16 scene in real-time physics (about 40 s).
##   1. Nodes: Player is a CrawlingPlayer, Stance a PostureController,
##      BalanceMonitor a CrawlBalanceMonitor reading Crawl; Crawl ticks
##      after Player; the gap's roof is 0.9 m above its floor, the slab's
##      ramp steeper than the walking limit and within the scramble limit.
##   2. The gap: its floor lies at the highest terrain point under it; a
##      ray up from the floor meets the roof at roof_height. Under the roof
##      the stand and crouch shapes do not fit, the crawl shape fits along
##      the passage and not across it.
##   3. Standing and crouched, the body stops at the roof's edge.
##   4. Crawling, it passes. Under the roof: standing up, key 4 and F3 are
##      refused for lack of headroom. Every tick of the straight crawl:
##      three or four contacts, planted limbs within 0.06 m of their
##      contacts; no lift with the center of mass outside its triangle;
##      the drawn body inside the crawl shape's height, width and length
##      (the crouched body, once lowered, inside the crouch shape's height
##      before). A sideways stick turns the body only until the lying shape
##      meets a wall; the stick pushed along the passage turns it back to
##      the passage's axis, and the rest of the crawl keeps the planted
##      limbs within 0.06 m with no unstable lift. After the gap, F3
##      stands the body up.
##   5. The slab: with auto_scramble off the upright body does not climb
##      it; with it on, the body scrambles to the top (three or four
##      contacts and limb errors below 0.06 m on every tick; at most one
##      lift with the center of mass outside its triangle, at the foot of
##      the slab) and stands up there.
##   6. Keys and OSC: key 0 while crawling is refused ("not upright"), F4
##      toggles the crawl lines; one /body/posture message per posture
##      change. Input map: toggle_crawl on F3 and Guide, toggle_crawl_debug
##      on F4, the Lesson 02 and 14 tick-rate bindings (test_15_climb_scene.gd
##      checks them too); T leaves the tick rate alone, 9 changes it.
##   7. Key 4 on the climbing face toggles the Lesson 14 stance and leaves
##      the posture; after the climb the posture follows the stance.
##   8. The Lesson 15 scene has no crawling. (The run/main_scene check
##      moved to test_17_light_scene.gd with Lesson 17; that test repeats
##      the input-map checks of item 6.)
## Run: Godot --headless --path game -s res://tests/test_16_crawl_scene.gd

const ERROR_LIMIT := 0.06

var _failures := 0
var _scene: Node
var _player: CrawlingPlayer
var _posture: PostureController
var _crawl: CrawlController
var _monitor: CrawlBalanceMonitor
var _terrain: Terrain
var _receiver := PacketPeerUDP.new()
var _posture_messages := 0
var _worst_error := 0.0
var _bad_support := 0
var _changes := 0
## Largest excess of the drawn body over its collision shape: height,
## half width, and length behind and ahead of the origin (meters; <= 0
## means inside).
var _body_excess := PackedFloat32Array([-INF, -INF, -INF, -INF])
var _floor_y := NAN


func _initialize() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	_receiver.bind(0, "127.0.0.1")
	var old_port := 57120
	if osc != null:
		old_port = osc.port
		osc.set_destination("127.0.0.1", _receiver.get_local_port())
	await _check_scene()
	if osc != null:
		osc.set_destination("127.0.0.1", old_port)
	print("test_16_crawl_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	_scene = (load("res://scenes/lessons/16_crawling_and_scrambling.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	await process_frame

	# 1. Nodes.
	_player = _scene.get_node("Player") as CrawlingPlayer
	_posture = _scene.get_node("Stance") as PostureController
	_crawl = _scene.get_node("Crawl") as CrawlController
	_monitor = _scene.get_node("BalanceMonitor") as CrawlBalanceMonitor
	_terrain = _scene.get_node("Terrain") as Terrain
	var gap := _scene.get_node("CrawlGap") as CrawlGap
	var slab := _scene.get_node("Slab") as RampTower
	_expect(_player != null and _posture != null and _crawl != null and _monitor != null and gap != null and slab != null,
			"CrawlingPlayer, PostureController, CrawlController, CrawlBalanceMonitor, CrawlGap, Slab")
	if _player == null or _posture == null or _crawl == null or _monitor == null or gap == null or slab == null:
		_scene.queue_free()
		return
	_expect(_monitor.crawl == _crawl and _crawl.player == _player and _crawl.posture == _posture and _posture.player == _player, "wiring")
	_expect(_crawl.get_index() > _player.get_index() and _crawl.process_physics_priority == _player.process_physics_priority, "Crawl ticks after Player")
	_expect(_posture.process_physics_priority < _player.process_physics_priority, "Stance ticks before Player")
	_expect(is_equal_approx(gap.roof_height, 0.9), "roof height %.2f m" % gap.roof_height)
	var ramp := slab.ramp_angles_degrees[0]
	_expect(ramp > _player.walk_max_angle_degrees() and ramp <= _player.scramble_max_angle_degrees, "slab %.0f deg: steeper than %.0f, within %.0f" % [ramp, _player.walk_max_angle_degrees(), _player.scramble_max_angle_degrees])
	_posture.posture_changed.connect(func(_p: int) -> void: _changes += 1)

	# 2. The gap.
	var rect := gap.floor_rect()
	var highest := -INF
	for i in 9:
		for j in 9:
			var w := gap.global_transform * Vector3(rect.position.x + rect.size.x * i / 8.0, 0, rect.position.y + rect.size.y * j / 8.0)
			highest = maxf(highest, _terrain.height_at(w.x, w.z))
	_expect(absf(gap.global_position.y - highest) < 1e-4, "floor at the highest terrain point under it")
	await physics_frame
	var center := gap.global_position
	var up := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.05, center + Vector3.UP * 2.0)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(up)
	_expect(not hit.is_empty() and absf(hit.position.y - center.y - gap.roof_height) < 1e-3, "roof underside %.3f m above the floor" % (hit.position.y - center.y if not hit.is_empty() else NAN))
	var along := atan2(-gap.global_transform.basis.z.x, -gap.global_transform.basis.z.z)
	var saved := _player.global_position
	_player.global_position = center
	_expect(not _player.fits(CrawlingPlayer.BodyShape.STAND, along) and not _player.fits(CrawlingPlayer.BodyShape.CROUCH, along), "under the roof: stand and crouch shapes do not fit")
	_expect(_player.fits(CrawlingPlayer.BodyShape.CRAWL, along), "crawl shape fits along the passage")
	_expect(not _player.fits(CrawlingPlayer.BodyShape.CRAWL, along + PI / 2), "crawl shape does not fit across it")
	_player.global_position = saved

	# 3. Standing and crouched at the entrance (the course runs toward -x).
	var roof_edge := (gap.global_transform * Vector3(0, 0, gap.gap_length * 0.5)).x
	var roof_end := (gap.global_transform * Vector3(0, 0, -gap.gap_length * 0.5)).x
	(_player.get_node("CameraPivot") as Node3D).rotation.y = PI / 2
	_player.body_mesh().rotation.y = PI / 2
	await _place(roof_edge + 0.6)
	await _push(2.0)
	_expect(_player.global_position.x > roof_edge + 0.3, "standing: stopped at x %.3f, roof edge %.3f" % [_player.global_position.x, roof_edge])
	_expect(_posture.request(PostureController.Posture.CROUCH), "crouch at the entrance")
	# The shape is lower at once; the drawn body follows the Lesson 14
	# spring and is below the shape's top after about 0.22 s (README O1).
	for k in 30:
		await _tick()
	_floor_y = gap.global_position.y
	await _push(1.0)
	_expect(_player.global_position.x > roof_edge + 0.3, "crouched: stopped at x %.3f" % _player.global_position.x)
	_expect(_body_excess[0] <= 0.0, "crouched body below the crouch shape's top: excess %.3f m" % _body_excess[0])
	_body_excess = PackedFloat32Array([-INF, -INF, -INF, -INF])

	# 4. Crawl through.
	_expect(_posture.request(PostureController.Posture.CRAWL), "crawl at the entrance (%s)" % _posture.refusal)
	for k in 30:
		await _tick()
	# Straight through the first three quarters of the passage.
	Input.action_press("move_forward", 1.0)
	var ticks := 0
	var probe_x := roof_end + 0.25 * (roof_edge - roof_end)
	while _player.global_position.x > probe_x and ticks < 60 * 25:
		await _tick()
		ticks += 1
		if ticks == 60 * 2:
			Input.action_release("move_forward")
			await _check_refusals()
			Input.action_press("move_forward", 1.0)
	Input.action_release("move_forward")
	_expect(_player.global_position.x <= probe_x, "crawled 3/4 of the passage: x %.3f after %.1f s" % [_player.global_position.x, ticks / 60.0])
	_expect(_crawl.lifts >= 18 and _crawl.unstable_lifts == 0, "lifts %d, unstable %d" % [_crawl.lifts, _crawl.unstable_lifts])
	_expect(_worst_error < ERROR_LIMIT, "planted limbs within %.2f m of their contacts: %.4f" % [ERROR_LIMIT, _worst_error])
	_expect(_bad_support == 0, "three or four contacts on every crawling tick (%d ticks without)" % _bad_support)
	_expect(_body_excess[0] <= 0.0 and _body_excess[1] <= 0.0 and _body_excess[2] <= 0.0 and _body_excess[3] <= 0.0,
			"crawling body inside the crawl shape: excess height %.3f, half width %.3f, back %.3f, front %.3f m" % Array(_body_excess))
	_floor_y = NAN
	_worst_error = 0.0
	await _check_turn()
	Input.action_press("move_forward", 1.0)
	while _player.global_position.x > roof_end - 0.65 and ticks < 60 * 30:
		await _tick()
		ticks += 1
	Input.action_release("move_forward")
	_expect(_player.global_position.x <= roof_end - 0.65, "crawled through: x %.3f after %.1f s" % [_player.global_position.x, ticks / 60.0])
	_expect(_worst_error < ERROR_LIMIT and _crawl.unstable_lifts == 0, "turn, turn back and the rest of the passage: planted limbs within %.2f m: %.4f, unstable lifts %d" % [ERROR_LIMIT, _worst_error, _crawl.unstable_lifts])
	_scene._unhandled_input(_key(KEY_F3))
	_expect(_posture.posture == PostureController.Posture.CROUCH and _player.body_shape == CrawlingPlayer.BodyShape.CROUCH, "F3 after the gap: back to crouched (%s)" % _posture.refusal)
	_scene._unhandled_input(_key(KEY_4))
	_expect(_posture.posture == PostureController.Posture.STAND and _player.mode == CrawlingPlayer.Mode.UPRIGHT, "key 4: standing")

	# 5. The slab.
	var top := slab.global_position.y + slab.platform_height
	var foot := (slab.global_transform * Vector3(0, 0, slab.platform_size * 0.5 + slab.platform_height / tan(deg_to_rad(ramp)))).x
	_posture.auto_scramble = false
	_player.body_mesh().rotation.y = PI / 2
	await _place(foot + 0.6)
	var y0 := _player.global_position.y
	await _push(3.0)
	_expect(_player.global_position.y - y0 < 0.3 and _posture.posture == PostureController.Posture.STAND, "upright: rose %.2f m against the slab" % (_player.global_position.y - y0))
	_posture.auto_scramble = true
	_player.body_mesh().rotation.y = PI / 2
	await _place(foot + 0.6)
	var lifts := _crawl.lifts
	var unstable_before := _crawl.unstable_lifts
	_worst_error = 0.0
	var scrambled := false
	Input.action_press("move_forward", 1.0)
	ticks = 0
	while ticks < 60 * 25 and not (scrambled and _posture.posture == PostureController.Posture.STAND and _player.global_position.y > top - 0.05):
		await _tick()
		ticks += 1
		scrambled = scrambled or _posture.posture == PostureController.Posture.SCRAMBLE
	Input.action_release("move_forward")
	_expect(scrambled, "the body scrambled")
	_expect(_player.global_position.y > top - 0.05 and _posture.posture == PostureController.Posture.STAND, "standing on the top: y %.3f, top %.3f (%s) after %.1f s" % [_player.global_position.y, top, PostureController.POSTURE_NAMES[_posture.posture], ticks / 60.0])
	# At the foot of the slab the legs stand on flat ground and the hands on
	# the 48 degree face; there one lift may go ahead after hold_timeout
	# with the center of mass a little outside its triangle.
	var unstable := _crawl.unstable_lifts - unstable_before
	_expect(_crawl.lifts - lifts >= 20 and unstable <= 1, "slab: lifts %d, unstable %d" % [_crawl.lifts - lifts, unstable])
	_expect(_worst_error < ERROR_LIMIT, "slab: planted limbs within %.2f m: %.4f" % [ERROR_LIMIT, _worst_error])
	_expect(_bad_support == 0, "three or four contacts on every scrambling tick")

	# 6. Keys and OSC, on the top, a step in from its edge.
	await _push(0.5)
	_scene._unhandled_input(_key(KEY_F3))
	_expect(_posture.posture == PostureController.Posture.CRAWL, "F3 on the top: crawling (%s)" % _posture.refusal)
	_scene._unhandled_input(_key(KEY_0))
	var climb := _scene.get_node("Climb") as ClimbController
	_expect(climb.state == ClimbController.State.WALKING and climb.refusal == "not upright", "key 0 while crawling: refused (%s)" % climb.refusal)
	var lines := _crawl.debug_draw
	_scene._unhandled_input(_key(KEY_F4))
	_expect(_crawl.debug_draw != lines, "F4 toggles the crawl lines")
	_scene._unhandled_input(_key(KEY_F3))
	_expect(_posture.posture == PostureController.Posture.STAND, "F3 again: standing")
	for k in 10:
		await _tick()
	_expect(_posture_messages == _changes and _changes >= 8, "%d /body/posture messages for %d changes" % [_posture_messages, _changes])
	var ticks_per_second := Engine.physics_ticks_per_second
	_scene._unhandled_input(_key(KEY_T))
	_expect(Engine.physics_ticks_per_second == ticks_per_second, "T leaves the tick rate alone")
	_scene._unhandled_input(_key(KEY_9))
	_expect(Engine.physics_ticks_per_second != ticks_per_second, "9 changes the tick rate")
	Engine.physics_ticks_per_second = ticks_per_second
	_expect(_has_key(&"toggle_crawl", KEY_F3) and _has_button(&"toggle_crawl", JOY_BUTTON_GUIDE), "toggle_crawl on F3 and Guide")
	_expect(_has_key(&"toggle_crawl_debug", KEY_F4), "toggle_crawl_debug on F4")
	var guide_actions := InputMap.get_actions().filter(func(a: StringName) -> bool: return _has_button(a, JOY_BUTTON_GUIDE))
	_expect(guide_actions == [&"toggle_crawl"], "Guide carries one action: %s" % [guide_actions])
	_expect(_has_key(&"cycle_tick_rate", KEY_T) and _has_button(&"cycle_tick_rate", JOY_BUTTON_DPAD_UP), "cycle_tick_rate on T and D-pad up (Lesson 02)")
	_expect(_has_key(&"cycle_stance_tick_rate", KEY_9) and not _has_key(&"cycle_tick_rate", KEY_9), "cycle_stance_tick_rate on 9 (Lesson 14)")

	await _check_climb_crouch()

	_scene.queue_free()
	await process_frame

	# 8. The Lesson 15 scene.
	var old: Node = (load("res://scenes/lessons/15_climbing.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Crawl") == null and not old.get_node("Player") is CrawlingPlayer and not old.get_node("Stance") is PostureController, "Lesson 15 scene has no crawling")
	old.free()


## Under the roof: no standing up.
func _check_refusals() -> void:
	for k in 5:
		await _tick()
	_expect(_player.headroom() < 1.0, "headroom under the roof: %.3f m" % _player.headroom())
	_expect(not _posture.request(PostureController.Posture.STAND) and _posture.refusal == "no headroom", "stand refused: %s" % _posture.refusal)
	_scene._unhandled_input(_key(KEY_4))
	_expect(_posture.posture == PostureController.Posture.CRAWL and _posture.refusal == "no headroom", "key 4 refused: %s" % _posture.refusal)
	_scene._unhandled_input(_key(KEY_F3))
	_expect(_posture.posture == PostureController.Posture.CRAWL and _posture.refusal == "no headroom", "F3 refused: %s" % _posture.refusal)


## Under the roof: the lying shape turns until it meets a wall.
func _check_turn() -> void:
	var yaw := _player.body_mesh().rotation.y
	Input.action_press("move_left", 1.0)
	var blocked := false
	for k in 180:
		await _tick()
		if _player.turn_blocked:
			blocked = true
			break
	Input.action_release("move_left")
	var turned := absf(angle_difference(yaw, _player.body_mesh().rotation.y))
	# The lying capsule turns about the origin. The far end of its axis
	# lies e = crawl_length / 2 - r + crawl_offset behind the origin and
	# swings out by e sin(a); a wall stops it when e sin(a) + r reaches
	# half the passage's width (README P2): 16.6 degrees.
	var gap := _scene.get_node("CrawlGap") as CrawlGap
	var r := _player.crawl_radius
	var e := 0.5 * _player.crawl_length - r + _player.crawl_offset
	var limit := asin((0.5 * gap.gap_width - r) / e)
	_expect(blocked and turned < limit + deg_to_rad(0.5), "sideways stick: turn blocked after %.1f deg (limit %.1f deg)" % [rad_to_deg(turned), rad_to_deg(limit)])
	# Turn back to the passage's axis with the stick along the passage. The
	# opposite sideways stick would point more than 96 degrees from the
	# facing and back the body up (CrawlingPlayer._crawl_velocity()).
	Input.action_press("move_forward", 1.0)
	for k in 60:
		await _tick()
		if absf(angle_difference(yaw, _player.body_mesh().rotation.y)) < deg_to_rad(0.1):
			break
	Input.action_release("move_forward")
	var off := absf(angle_difference(yaw, _player.body_mesh().rotation.y))
	_expect(off < deg_to_rad(0.1), "stick along the passage: turned back to its axis (%.2f deg off)" % rad_to_deg(off))


## Key 4 on the rock: the Lesson 14 crouch that the climb reads (Lesson 15).
func _check_climb_crouch() -> void:
	var face := _scene.get_node("ClimbFace") as ClimbableRock
	var climb := _scene.get_node("Climb") as ClimbController
	var front := face.global_transform * Vector3(0, 0, 0.6) + face.face_normal_world() * 0.5
	_player.global_position = Vector3(front.x, _terrain.height_at(front.x, front.z) + 0.2, front.z)
	_player.velocity = Vector3.ZERO
	for k in 40:
		await _tick()
	_expect(_posture.posture == PostureController.Posture.STAND, "standing before the face")
	_scene._unhandled_input(_key(KEY_0))
	_expect(climb.state == ClimbController.State.CLIMBING, "key 0 at the face: climbing (%s)" % climb.refusal)
	_scene._unhandled_input(_key(KEY_4))
	_expect(_posture.stance == StanceController.Stance.CROUCHED and _posture.posture == PostureController.Posture.STAND and _player.body_shape == CrawlingPlayer.BodyShape.STAND,
			"key 4 while climbing: crouch for the climb, posture and shape unchanged (%s)" % _posture.refusal)
	for k in 30:
		await _tick()
	_expect(_posture.crouch > 0.5 * _posture.crouch_depth, "the crouch the climb reads: %.3f m" % _posture.crouch)
	_scene._unhandled_input(_key(KEY_0))
	for k in 5:
		await _tick()
	_expect(climb.state == ClimbController.State.WALKING and _posture.posture == PostureController.Posture.CROUCH and _player.body_shape == CrawlingPlayer.BodyShape.CROUCH,
			"after the climb: the posture follows the stance (%s)" % PostureController.POSTURE_NAMES[_posture.posture])
	_scene._unhandled_input(_key(KEY_4))
	_expect(_posture.posture == PostureController.Posture.STAND and _posture.stance == StanceController.Stance.STANDING, "key 4: standing again")


## Places the player standing on the terrain at (x, 52) and lets it settle.
func _place(x: float) -> void:
	_player.global_position = Vector3(x, _terrain.height_at(x, 52.0) + 0.3, 52.0)
	_player.velocity = Vector3.ZERO
	for k in 40:
		await _tick()


func _push(seconds: float) -> void:
	Input.action_press("move_forward", 1.0)
	for k in int(seconds * 60):
		await _tick()
	Input.action_release("move_forward")


## One physics tick: the per-tick checks and the OSC receiver.
func _tick() -> void:
	await physics_frame
	if not is_nan(_floor_y) and _player.body_shape != CrawlingPlayer.BodyShape.STAND and (not _crawl.is_active() or _crawl._blend_time >= _crawl.transition_time):
		_measure_body()
	if _crawl.is_active() and _crawl._blend_time >= _crawl.transition_time:
		for i in 4:
			if _crawl.limbs[i].planted:
				_worst_error = maxf(_worst_error, _crawl.limb_errors[i])
		if _monitor.support_count < 3:
			_bad_support += 1
	while _receiver.get_available_packet_count() > 0:
		if _receiver.get_packet().get_string_from_ascii() == "/body/posture":
			_posture_messages += 1


## Compares the rig's capsules with the collision shape: the top of the
## highest capsule against the shape's height above the floor, the widest
## against the shape's radius, and (crawl shape) the farthest back and
## ahead along the facing against the ends of the lying capsule.
func _measure_body() -> void:
	var skeleton := _player.rig.skeleton()
	skeleton.force_update_all_bone_transforms()
	var shape := _player.body_shape
	var radius := _player.shape_radius(shape)
	var facing := _player.facing()
	var right := facing.cross(Vector3.UP)
	var origin := _player.global_position
	var stack: Array[Node] = [skeleton]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(true):
			stack.append(child)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.mesh is CapsuleMesh:
			continue
		var capsule := mesh_instance.mesh as CapsuleMesh
		var half := 0.5 * capsule.height - capsule.radius
		for end: float in [-1.0, 1.0]:
			var p := mesh_instance.global_transform * Vector3(0.0, end * half, 0.0)
			_body_excess[0] = maxf(_body_excess[0], p.y + capsule.radius - _floor_y - _player.shape_height(shape))
			if shape != CrawlingPlayer.BodyShape.CRAWL:
				continue
			var along := (p - origin).dot(facing)
			_body_excess[1] = maxf(_body_excess[1], absf((p - origin).dot(right)) + capsule.radius - radius)
			_body_excess[2] = maxf(_body_excess[2], -along + capsule.radius - (0.5 * _player.crawl_length + _player.crawl_offset))
			_body_excess[3] = maxf(_body_excess[3], along + capsule.radius - (0.5 * _player.crawl_length - _player.crawl_offset))


func _has_key(action: StringName, code: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


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
