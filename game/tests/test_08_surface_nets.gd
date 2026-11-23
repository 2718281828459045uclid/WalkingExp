extends SceneTree
## Lesson 08: checks SdfGrid, SurfaceNets and (when a GPU exists)
## SurfaceNetsGpu.
##   1. edge_crossing() finds the zero of the line through two values.
##   2. trilinear_gradient() of a linear field returns its slope.
##   3. SdfGrid.sample() covers bounds() with a positive outer layer and
##      stores evaluate() at point(i, j, k).
##   4. A sphere of radius 1 on a 0.2 m grid: every vertex lies in its own
##      cell and within 0.03 m of the sphere; normals within 10 degrees of
##      the radial direction; the mesh is closed (each edge in exactly two
##      triangles) with Euler characteristic V - E + F = 2; every triangle
##      faces outward under Godot's clockwise rule.
##   5. If a RenderingDevice exists (windowed runs only), the GPU cell
##      table has the same vertex cells as the CPU table, positions within
##      1e-5 m and normals within 1e-3.
## Run: Godot --headless --path game -s res://tests/test_08_surface_nets.gd

var _failures := 0


func _initialize() -> void:
	_check_edge_crossing()
	_check_trilinear_gradient()
	_check_grid()
	_check_sphere()
	_check_gpu()
	print("test_08_surface_nets: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_edge_crossing() -> void:
	_near(SurfaceNets.edge_crossing(-1.0, 1.0), 0.5, 1e-12, "crossing midway")
	_near(SurfaceNets.edge_crossing(-0.1, 0.3), 0.25, 1e-12, "crossing at a quarter")
	_near(SurfaceNets.edge_crossing(0.3, -0.1), 0.75, 1e-12, "crossing from the outside")


func _check_trilinear_gradient() -> void:
	# f = 2x - 3y + 0.5z at the corners of the unit cell.
	var f := PackedFloat64Array()
	for n in 8:
		f.append(2.0 * (n & 1) - 3.0 * ((n >> 1) & 1) + 0.5 * ((n >> 2) & 1))
	var g := SurfaceNets.trilinear_gradient(f, 0.3, 0.6, 0.1)
	_expect(g.is_equal_approx(Vector3(2, -3, 0.5)), "gradient of a linear field: %s" % g)


func _sphere() -> SdfSphere:
	var sphere := SdfSphere.new()
	sphere.radius = 1.0
	return sphere


func _check_grid() -> void:
	var sphere := _sphere()
	var grid := SdfGrid.sample(sphere, 0.2)
	_expect(grid.values.size() == grid.dims.x * grid.dims.y * grid.dims.z, "value count")
	_near(grid.value(3, 5, 7), sphere.evaluate(grid.point(3, 5, 7)), 1e-6, "stored value")
	var box := AABB(grid.origin, Vector3(grid.dims - Vector3i.ONE) * grid.cell_size)
	_expect(box.encloses(sphere.bounds()), "grid covers bounds()")
	var outer_positive := true
	for k in grid.dims.z:
		for j in grid.dims.y:
			for i in [0, grid.dims.x - 1]:
				outer_positive = outer_positive and grid.value(i, j, k) > 0.0
	_expect(outer_positive, "outer layer positive")


func _check_sphere() -> void:
	var grid := SdfGrid.sample(_sphere(), 0.2)
	var nets := SurfaceNets.new()
	nets.build(grid)
	_expect(nets.positions.size() > 100, "vertex count %d" % nets.positions.size())

	var worst_distance := 0.0
	var worst_angle := 0.0
	var outside_cell := 0
	var cells := grid.dims - Vector3i.ONE
	for c in nets.cell_vertex.size():
		var v := nets.cell_vertex[c]
		if v < 0:
			continue
		var ijk := Vector3i(c % cells.x, (c / cells.x) % cells.y, c / (cells.x * cells.y))
		var corner := grid.point(ijk.x, ijk.y, ijk.z)
		var cell_box := AABB(corner, Vector3.ONE * grid.cell_size).grow(1e-5)
		if not cell_box.has_point(nets.positions[v]):
			outside_cell += 1
		worst_distance = maxf(worst_distance, absf(nets.positions[v].length() - 1.0))
		worst_angle = maxf(worst_angle, rad_to_deg(nets.normals[v].angle_to(nets.positions[v])))
	_expect(outside_cell == 0, "%d vertices outside their cell" % outside_cell)
	_expect(worst_distance < 0.03, "vertex off the sphere by %f" % worst_distance)
	_expect(worst_angle < 10.0, "normal off by %f degrees" % worst_angle)

	var edges := {}
	var inward := 0
	for t in nets.triangle_count():
		var a := nets.indices[3 * t]
		var b := nets.indices[3 * t + 1]
		var c := nets.indices[3 * t + 2]
		for pair in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(pair.x, pair.y), maxi(pair.x, pair.y))
			edges[key] = edges.get(key, 0) + 1
		# Godot's front side: (c - a) x (b - a) points toward the viewer.
		var front := (nets.positions[c] - nets.positions[a]).cross(nets.positions[b] - nets.positions[a])
		if front.dot(nets.positions[a]) <= 0.0:
			inward += 1
	var open_edges := 0
	for key in edges:
		if edges[key] != 2:
			open_edges += 1
	_expect(open_edges == 0, "%d edges not shared by two triangles" % open_edges)
	var euler := nets.positions.size() - edges.size() + nets.triangle_count()
	_expect(euler == 2, "Euler characteristic %d" % euler)
	_expect(inward == 0, "%d triangles face inward" % inward)


func _check_gpu() -> void:
	var shader := load("res://shaders/compute/surface_nets.glsl") as RDShaderFile
	_expect(shader != null and shader.get_spirv().compile_error_compute == "", "compute shader compiles")
	var gpu := SurfaceNetsGpu.new(shader)
	if not gpu.is_available():
		print("test_08_surface_nets: no RenderingDevice (headless); GPU comparison skipped")
		return
	var grid := SdfGrid.sample(load("res://data/rocks/boulder_pile.tres") as SdfShape, 0.3)
	var gpu_table := gpu.run(grid)
	var cpu_table := SurfaceNets.cell_table(grid)
	_expect(gpu_table.size() == cpu_table.size(), "table sizes")
	var flag_differences := 0
	var worst_position := 0.0
	var worst_normal := 0.0
	for c in grid.cell_count():
		var at := c * SurfaceNets.CELL_FLOATS
		if gpu_table[at + 3] != cpu_table[at + 3]:
			flag_differences += 1
		elif cpu_table[at + 3] > 0.5:
			var dp := Vector3(gpu_table[at] - cpu_table[at], gpu_table[at + 1] - cpu_table[at + 1], gpu_table[at + 2] - cpu_table[at + 2])
			var dn := Vector3(gpu_table[at + 4] - cpu_table[at + 4], gpu_table[at + 5] - cpu_table[at + 5], gpu_table[at + 6] - cpu_table[at + 6])
			worst_position = maxf(worst_position, dp.length())
			worst_normal = maxf(worst_normal, dn.length())
	print("test_08_surface_nets: GPU vs CPU: %d flag differences, position %s m, normal %s" % [flag_differences, str(worst_position), str(worst_normal)])
	_expect(flag_differences == 0, "GPU and CPU disagree on %d cells" % flag_differences)
	_expect(worst_position < 1e-5, "GPU position differs by %f" % worst_position)
	_expect(worst_normal < 1e-3, "GPU normal differs by %f" % worst_normal)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _near(a: float, b: float, tolerance: float, message: String) -> void:
	_expect(absf(a - b) <= tolerance, "%s: %f vs %f" % [message, a, b])
