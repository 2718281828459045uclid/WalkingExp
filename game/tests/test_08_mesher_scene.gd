extends SceneTree
## Lesson 08: checks the Lesson 08 scene and SdfMesher (src/sdf/sdf_mesher.gd).
##   1. Rocks/Boulders built a mesh with triangles and a collision shape
##      (a ConcavePolygonShape3D) in internal children.
##   2. Every mesh vertex lies close to the zero set: |f| below one cell.
##   3. The player capsule, dropped above the split boulder, comes to
##      rest on the rock: on the floor, its feet well above the ground
##      and near the surface (|f| small).
##   4. The capsule walks forward for two seconds, across the boulder top
##      and down its side. The capsule center stays more than 0.3 m from
##      the rock (f > 0.3; the capsule radius is 0.35 m).
##   5. R cycles the rock view (mesh / mesh + slices / slices) and J
##      switches use_gpu; headless runs fall back to the CPU.
##   6. The Lesson 07 scene has no Boulders node.
## Run: Godot --headless --path game -s res://tests/test_08_mesher_scene.gd

const DROP_POINT := Vector3(3.6, 4.5, 0.8)
## From the Player origin (feet) to the capsule center (player.tscn).
const CENTER_HEIGHT := Vector3(0, 0.9, 0)

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_08_mesher_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	# The scene sends OSC (Lessons 04-06); redirect it to a local socket.
	var osc := root.get_node_or_null("Osc") as OscSender
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := 57120
	if osc != null:
		old_port = osc.port
		osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/08_field_to_mesh.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var rocks := scene.get_node("Rocks") as Node3D
	var mesher := scene.get_node("Rocks/Boulders") as SdfMesher
	var shape := mesher.shape

	# 1. Mesh and collision in internal children.
	_expect(mesher.triangle_count() > 1000, "triangles: %d" % mesher.triangle_count())
	_expect(mesher.get_child_count() == 0 and mesher.get_child_count(true) == 2, "internal children")
	var mesh_instance: MeshInstance3D = null
	var collision: CollisionShape3D = null
	for child in mesher.get_children(true):
		if child is MeshInstance3D:
			mesh_instance = child
		elif child is StaticBody3D:
			collision = child.get_child(0) as CollisionShape3D
	_expect(mesh_instance != null and mesh_instance.mesh.get_surface_count() == 1, "mesh surface")
	_expect(collision != null and collision.shape is ConcavePolygonShape3D, "trimesh collision")
	if collision != null and collision.shape is ConcavePolygonShape3D:
		var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
		_expect(faces.size() == mesher.triangle_count() * 3, "collision face count")

	# 2. Vertices near the zero set.
	var worst := 0.0
	for p in mesher.nets.positions:
		worst = maxf(worst, absf(shape.evaluate(p)))
	_expect(worst < mesher.cell_size, "vertex |f| up to %f" % worst)

	# 3. Drop the capsule onto the split boulder.
	var player := scene.get_node("Player") as CharacterBody3D
	player.global_position = rocks.to_global(DROP_POINT)
	player.velocity = Vector3.ZERO
	for i in 120:
		await physics_frame
	# The Player node's origin is at the bottom of the capsule (its feet).
	var feet := rocks.to_local(player.global_position)
	print("landed: feet %s  f(feet) %.3f  on floor %s" % [feet, shape.evaluate(feet), player.is_on_floor()])
	_expect(player.is_on_floor(), "capsule on the rock")
	_expect(feet.y > 1.5, "feet %.2f m above the ground: fell through" % feet.y)
	_expect(absf(shape.evaluate(feet)) < 0.3, "feet not near the surface: f %.3f" % shape.evaluate(feet))

	# 4. Walk forward for two seconds; the center never enters the rock.
	Input.action_press("move_forward", 1.0)
	var smallest := INF
	for i in 120:
		await physics_frame
		var center := rocks.to_local(player.global_position) + CENTER_HEIGHT
		smallest = minf(smallest, shape.evaluate(center))
	Input.action_release("move_forward")
	print("walking: smallest f at the capsule center %.3f" % smallest)
	_expect(smallest > 0.3, "capsule center entered the rock: f %.3f" % smallest)

	# 5. Keys.
	var slice := scene.get_node("Rocks/SliceHorizontal") as Node3D
	_expect(mesher.visible and not slice.visible, "view 0: mesh only")
	scene._unhandled_input(_action("cycle_rock_view"))
	_expect(mesher.visible and slice.visible, "view 1: mesh and slices")
	scene._unhandled_input(_action("cycle_rock_view"))
	_expect(not mesher.visible and slice.visible, "view 2: slices only")
	var before := mesher.use_gpu
	scene._unhandled_input(_action("toggle_mesher_backend"))
	_expect(mesher.use_gpu != before, "J switches use_gpu")
	await process_frame
	await process_frame
	if not mesher.gpu_available():
		_expect(not mesher.used_gpu, "headless run must fall back to the CPU")

	scene.queue_free()
	await process_frame

	# 6. Lesson 07 scene is unchanged.
	var old: Node = (load("res://scenes/lessons/07_sdf_primitives.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Rocks/Boulders") == null, "Lesson 07 scene has Boulders")
	old.free()

	if osc != null:
		osc.set_destination("127.0.0.1", old_port)


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _near(a: float, b: float, tolerance: float, message: String) -> void:
	_expect(absf(a - b) <= tolerance, "%s: %f vs %f" % [message, a, b])
