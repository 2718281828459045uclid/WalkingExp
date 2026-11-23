extends SceneTree
## Lesson 10: checks SdfGlsl (src/sdf/sdf_glsl.gd), the translation of an
## SdfShape tree into GLSL.
##   1. Every node type of the library translates, with no unsupported
##      class, and the call of its mirror function appears in the code.
##   2. The generated code, spliced into shaders/sdf/raymarch.gdshader,
##      compiles. (A compile error prints SHADER ERROR, which
##      tools/check.sh reports; the uniform list is checked here.)
##   3. A noise shared by several SdfDisplace nodes becomes one texture,
##      whose texels equal FastNoiseLite at the grid points.
##   4. Float literals always carry a decimal point.
## Run: Godot --headless --path game -s res://tests/test_10_sdf_glsl.gd

var _failures := 0


func _initialize() -> void:
	_check_node_types()
	_check_compiles()
	_check_noise()
	_check_literals()
	print("test_10_sdf_glsl: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_node_types() -> void:
	var sphere := SdfSphere.new()
	var box := SdfBox.new()
	var capsule := SdfCapsule.new()
	var ellipsoid := SdfEllipsoid.new()
	var ellipsoid_gradient := SdfEllipsoid.new()
	ellipsoid_gradient.estimate = SdfEllipsoid.Estimate.GRADIENT
	var torus := SdfTorus.new()

	var smooth := SdfSmoothUnion.new()
	smooth.shapes = [sphere, box]
	var intersection := SdfIntersection.new()
	intersection.shapes = [capsule, ellipsoid]
	var subtraction := SdfSubtraction.new()
	subtraction.base = smooth
	subtraction.cutter = intersection
	var transform := SdfTransform.new()
	transform.shape = torus
	transform.rotation_degrees = Vector3(0, 30, 10)
	transform.scale = 0.5
	var repeat := SdfRepeat.new()
	repeat.shape = ellipsoid_gradient
	var displace := SdfDisplace.new()
	displace.shape = repeat
	displace.noise = FastNoiseLite.new()
	var union := SdfUnion.new()
	union.shapes = [subtraction, transform, displace]

	var glsl := SdfGlsl.new()
	var code := glsl.translate(union)
	_expect(glsl.unsupported.is_empty(), "unsupported: %s" % ", ".join(glsl.unsupported))
	_expect(glsl.node_count == 13, "node count %d" % glsl.node_count)
	for call in ["sdf_sphere(", "sdf_box(", "sdf_capsule(", "sdf_ellipsoid_scaled(",
			"sdf_ellipsoid_gradient(", "sdf_torus(", "sdf_smin(", "min(", "max(",
			"round(", "sdf_noise(", "float sdf_map(vec3 p0)"]:
		_expect(code.contains(call), "code lacks " + call)


func _check_compiles() -> void:
	var pile: SdfShape = load("res://data/rocks/boulder_pile.tres")
	var glsl := SdfGlsl.new()
	var code := glsl.translate(pile)
	_expect(glsl.unsupported.is_empty(), "pile translates")
	var template: Shader = load("res://shaders/sdf/raymarch.gdshader")
	var spliced := SdfGlsl.splice(template.code, code)
	_expect(spliced.contains(code), "splice inserts the code")
	_expect(not spliced.contains("return sdf_sphere(p0, vec3(0.0), 1.0);"), "splice removes the stub")
	var shader := Shader.new()
	shader.code = spliced
	var names: Array[String] = []
	for uniform in shader.get_shader_uniform_list():
		names.append(uniform["name"])
	for expected in ["sdf_noise_0", "sdf_noise_0_origin", "max_steps", "step_scale", "proxy_min"]:
		_expect(names.has(expected), "uniform %s missing (did the shader compile?)" % expected)


func _check_noise() -> void:
	var pile: SdfShape = load("res://data/rocks/boulder_pile.tres")
	var glsl := SdfGlsl.new()
	glsl.translate(pile)
	# tor_boulder (twice) and split_boulder share granite_noise.tres.
	_expect(glsl.noises.size() == 1, "%d noises, expected 1" % glsl.noises.size())
	glsl.bake_noise_textures(0.2)
	_expect(glsl.noise_textures.size() == 1, "one texture")
	if glsl.noise_textures.is_empty():
		return
	var dims := glsl.noise_dims[0]
	var texture := glsl.noise_textures[0]
	_expect(texture.get_width() == dims.x and texture.get_height() == dims.y and texture.get_depth() == dims.z, "texture size")
	# Q: Why bake the slices again instead of reading the texture?
	# A: A headless run has no real renderer, and the texture's
	#    get_data() returns nothing. bake_noise_slices() is what
	#    bake_noise_textures() hands to the texture.
	var slices := SdfGlsl.bake_noise_slices(glsl.noises[0], glsl.noise_regions[0], 0.2)
	_expect(slices.size() == dims.z, "slice count")
	var ijk := Vector3i(dims.x / 2, dims.y / 3, dims.z - 1)
	var stored := slices[ijk.z].get_pixel(ijk.x, ijk.y).r
	var p := glsl.noise_regions[0].position + Vector3(ijk) * 0.2
	var expected := glsl.noises[0].get_noise_3dv(p)
	_expect(absf(stored - expected) < 1e-6, "texel %f, noise %f" % [stored, expected])
	var region := glsl.noise_regions[0]
	_expect(region.position.x + (dims.x - 1) * 0.2 >= region.end.x - 1e-4, "grid covers the region")


func _check_literals() -> void:
	_expect(SdfGlsl._f(1.0) == "1.0", "1.0 -> %s" % SdfGlsl._f(1.0))
	_expect(SdfGlsl._f(-2.0) == "-2.0", "-2.0 -> %s" % SdfGlsl._f(-2.0))
	_expect(SdfGlsl._f(0.25) == "0.25", "0.25 -> %s" % SdfGlsl._f(0.25))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
