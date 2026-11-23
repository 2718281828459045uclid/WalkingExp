extends SceneTree
## Lesson 07: checks the Lesson 07 scene and SdfSlice (src/sdf/sdf_slice.gd).
##   1. The Rocks node stands at the terrain height under it.
##   2. Both slices built a texture of the grid size; each holds negative
##      values (the cut passes through rock) and |grad f| no larger than
##      the shape's Lipschitz bound.
##   3. A texel of the image equals shape.evaluate() at texel_point().
##   4. G cycles the view of both materials (0, 1, 2, 0); H moves the
##      horizontal cut up 0.5 m and rebuilds it.
##   5. The Lesson 06 scene has no Rocks node.
## Run: Godot --headless --path game -s res://tests/test_07_sdf_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_07_sdf_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	# The scene sends OSC (Lessons 04-06); send it to a local socket
	# instead of sclang's port, and restore the port afterwards.
	var osc := root.get_node_or_null("Osc") as OscSender
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := 57120
	if osc != null:
		old_port = osc.port
		osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/07_sdf_primitives.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var rocks := scene.get_node("Rocks") as Node3D
	var terrain := scene.get_node("Terrain") as Terrain
	_near(rocks.position.y, terrain.height_at(rocks.position.x, rocks.position.z), 1e-4, "Rocks height")

	var horizontal := scene.get_node("Rocks/SliceHorizontal") as SdfSlice
	var vertical := scene.get_node("Rocks/SliceVertical") as SdfSlice
	for slice in [horizontal, vertical]:
		var grid: Vector2i = slice.grid_size()
		_expect(slice.image != null and slice.image.get_size() == grid, "%s: image size" % slice.name)
		_expect(slice.sample_count == grid.x * grid.y * 3, "%s: sample count" % slice.name)
		_expect(slice.smallest_value < 0.0, "%s: no rock in the cut" % slice.name)
		_expect(slice.largest_gradient <= slice.shape.lipschitz_bound(),
			"%s: |grad f| %f above the bound" % [slice.name, slice.largest_gradient])
		var texel: Color = slice.image.get_pixel(10, 7)
		_near(texel.r, slice.shape.evaluate(slice.texel_point(10, 7)), 1e-5, "%s: texel value" % slice.name)

	var mesh := _slice_mesh(horizontal)
	var other_mesh := _slice_mesh(vertical)
	_expect(mesh.material_override != other_mesh.material_override, "the slices share one material")
	var views: Array[int] = []
	for i in 3:
		scene._unhandled_input(_action("cycle_slice_view"))
		views.append((mesh.material_override as ShaderMaterial).get_shader_parameter("view"))
		_expect((other_mesh.material_override as ShaderMaterial).get_shader_parameter("view") == views[-1],
			"G changed only one slice")
	_expect(views == [1, 2, 0], "G views %s" % [views])

	var before := horizontal.origin.y
	scene._unhandled_input(_action("step_slice"))
	await process_frame
	_near(horizontal.origin.y, before + 0.5, 1e-9, "H moves the cut 0.5 m")
	_near(mesh.transform.origin.y, before + 0.5, 1e-5, "the quad follows the cut")

	scene.queue_free()
	await process_frame
	var old_scene: Node = (load("res://scenes/lessons/06_spatial_audio.tscn") as PackedScene).instantiate()
	_expect(old_scene.get_node_or_null("Rocks") == null, "the Lesson 06 scene has a Rocks node")
	old_scene.free()
	if osc != null:
		osc.set_destination("127.0.0.1", old_port)
	receiver.close()


## The internal quad that SdfSlice builds in _ready().
func _slice_mesh(slice: SdfSlice) -> MeshInstance3D:
	for child in slice.get_children(true):
		if child is MeshInstance3D:
			return child
	return null


func _action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


func _near(value: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(value - expected) <= tolerance, "%s: %f, expected %f" % [message, value, expected])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
