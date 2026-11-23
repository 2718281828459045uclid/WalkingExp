extends SceneTree
## Lesson 09: checks the Lesson 09 scene and CurvatureMesher
## (src/sdf/curvature_mesher.gd).
##   1. Rocks/Boulders is a CurvatureMesher with the weathering
##      ShaderMaterial; it has one H, K and normal per mesh vertex.
##   2. The mesh carries CUSTOM0 as four 32-bit floats per vertex, equal
##      to (H, K, k1, k2) of the mesher's arrays.
##   3. Gradient normals are unit vectors and agree with the trilinear
##      normals of Lesson 08 on average within 5 degrees.
##   4. The median mean curvature lies between 0.2 and 2 per meter
##      (boulders a meter or two across), and some vertices have K < 0.
##   5. I switches the mesh normals without resampling; U cycles the
##      shader's curvature_view.
##   6. The Lesson 08 scene still uses a plain SdfMesher.
## Run: Godot --headless --path game -s res://tests/test_09_curvature_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_09_curvature_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
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

	var scene: Node = (load("res://scenes/lessons/09_implicit_curvature.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame

	# 1. Node, material, arrays.
	var mesher := scene.get_node("Rocks/Boulders") as CurvatureMesher
	_expect(mesher != null, "Rocks/Boulders is a CurvatureMesher")
	if mesher == null:
		return
	var rock_material := mesher.material as ShaderMaterial
	_expect(rock_material != null and rock_material.shader.resource_path.ends_with("rock_weathering.gdshader"), "weathering material")
	var count := mesher.vertex_count()
	_expect(count > 1000, "vertices: %d" % count)
	_expect(mesher.mean_curvatures.size() == count and mesher.gaussian_curvatures.size() == count \
		and mesher.gradient_normals.size() == count, "one curvature per vertex")

	# 2. CUSTOM0 in the mesh.
	var mesh := _mesh_of(mesher)
	var arrays := mesh.surface_get_arrays(0)
	var custom := arrays[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array
	var format := mesh.surface_get_format(0)
	var custom_bits := (format >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK
	_expect(custom_bits == Mesh.ARRAY_CUSTOM_RGBA_FLOAT, "CUSTOM0 format %d" % custom_bits)
	_expect(custom.size() == count * 4, "CUSTOM0 size %d" % custom.size())
	if custom.size() == count * 4:
		var i := count / 2
		_expect(custom[4 * i] == mesher.mean_curvatures[i] and custom[4 * i + 1] == mesher.gaussian_curvatures[i], "CUSTOM0 holds H, K")
		_expect(custom[4 * i + 2] >= custom[4 * i + 3], "k1 >= k2")

	# 3. Normals.
	var off_unit := 0
	for n in mesher.gradient_normals:
		if absf(n.length() - 1.0) > 1e-4:
			off_unit += 1
	_expect(off_unit == 0, "%d gradient normals are not unit vectors" % off_unit)
	var angles := mesher.normal_angle_stats()
	print("normal angle: mean %.2f deg, max %.1f deg" % [angles.x, angles.y])
	_expect(angles.x < 5.0, "mean angle trilinear vs gradient %.2f deg" % angles.x)

	# 4. Curvature distribution.
	var sorted := Array(mesher.mean_curvatures)
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var saddles := 0
	for k in mesher.gaussian_curvatures:
		if k < 0.0:
			saddles += 1
	print("median H %.3f 1/m, %d of %d vertices with K < 0" % [median, saddles, count])
	_expect(median > 0.2 and median < 2.0, "median H %f" % median)
	_expect(saddles > 0, "no saddle vertices")

	# 5. Keys.
	scene._unhandled_input(_action("toggle_normal_source"))
	_expect(mesher.normal_source == CurvatureMesher.NormalSource.TRILINEAR, "I selects trilinear")
	var normals := _mesh_of(mesher).surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array
	# Q: Why compare by angle and not with is_equal_approx()?
	# A: The GPU copy of a normal is packed into fewer bits (octahedral
	#    encoding); surface_get_arrays() unpacks it with a small error.
	var i := 0
	_expect(rad_to_deg(normals[i].angle_to(mesher.nets.normals[i])) < 0.5, "mesh carries trilinear normals")
	scene._unhandled_input(_action("toggle_normal_source"))
	_expect(mesher.normal_source == CurvatureMesher.NormalSource.GRADIENT, "I selects gradient")
	scene._unhandled_input(_action("cycle_curvature_view"))
	_expect(rock_material.get_shader_parameter("curvature_view") == 1, "U cycles the view")
	scene._unhandled_input(_action("cycle_curvature_view"))
	scene._unhandled_input(_action("cycle_curvature_view"))
	scene._unhandled_input(_action("cycle_curvature_view"))
	_expect(rock_material.get_shader_parameter("curvature_view") == 0, "U wraps to 0")

	scene.queue_free()
	await process_frame

	# 6. Lesson 08 scene keeps its plain mesher.
	var old: Node = (load("res://scenes/lessons/08_field_to_mesh.tscn") as PackedScene).instantiate()
	var old_mesher := old.get_node("Rocks/Boulders")
	_expect(old_mesher is SdfMesher and not old_mesher is CurvatureMesher, "Lesson 08 Boulders changed type")
	old.free()

	if osc != null:
		osc.set_destination("127.0.0.1", old_port)


func _mesh_of(mesher: SdfMesher) -> ArrayMesh:
	for child in mesher.get_children(true):
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh as ArrayMesh
	return null


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
