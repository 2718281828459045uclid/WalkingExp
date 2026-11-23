extends SceneTree
## Lesson 17, windowed: rendered pixels against src/render/brdf.gd. In a
## headless run (tools/check.sh) there is no renderer; the test prints
## "skipped" and passes. Run it in a window:
##   Godot --path game -s res://tests/test_17_light_pixels.gd
##
## Setup: 24 flat quads with random normals (within 75 degrees of up), one
## directional light of energy 1 at 55 degrees from the vertical, no
## ambient light, no sky reflection, Linear tonemapping, a SubViewport with
## a 16-bit float buffer (linear values, not sRGB), an orthographic camera
## 2000 m above the quads looking straight down.
##
## Q: Why 2000 m?
## A: Godot computes VIEW from the pixel's position relative to the camera,
##    also for an orthographic camera. From 2000 m the direction to the
##    camera is within 0.2 degrees of straight up for every quad, which
##    is the V the CPU formulas assume.
##
## Checks:
##   1. LIGHT_COLOR = color * energy * PI: 0.1 * LIGHT_COLOR reads 0.1 pi.
##   2. DIFFUSE_LIGHT is multiplied by ALBEDO afterward, SPECULAR_LIGHT is not.
##   3. Godot 4.6's default diffuse (no render_mode) equals
##      render_mode diffuse_lambert, and both equal the custom Lambert.
##   4. Each custom model (custom_light.gdshaderinc through LitShader) equals
##      Brdf.reflected() on every quad within 2e-3 + 0.2 %.

const QUADS := 24
const COLUMNS := 6
const SPACING := 1.3
const PIXELS_PER_METER := 80.0

var _failures := 0
var _viewport: SubViewport
var _camera: Camera3D
var _quads: Array[MeshInstance3D] = []
var _normals: Array[Vector3] = []
var _light_direction := Vector3.ZERO
var _base: Shader
var _include: ShaderInclude


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("test_17_light_pixels: skipped (headless; run it in a window)")
		quit(0)
		return
	_include = load("res://shaders/lighting/custom_light.gdshaderinc")
	_base = Shader.new()
	_base.code = "shader_type spatial;\nuniform float albedo = 0.5;\nuniform float rough = 0.92;\nvoid fragment() { ALBEDO = vec3(albedo); ROUGHNESS = rough; }\n"
	_build()
	await _check_conventions()
	await _check_models()
	print("test_17_light_pixels: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _build() -> void:
	var rows := ceili(QUADS / float(COLUMNS))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(COLUMNS * SPACING * PIXELS_PER_METER), int(rows * SPACING * PIXELS_PER_METER))
	_viewport.use_hdr_2d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.BLACK
	environment.ambient_light_energy = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	_viewport.add_child(light)
	var t := deg_to_rad(55.0)
	_light_direction = Vector3(sin(t), cos(t), 0.0)
	light.look_at_from_position(Vector3.ZERO, -_light_direction, Vector3.BACK)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = rows * SPACING
	_camera.far = 5000.0
	_viewport.add_child(_camera)
	var center := Vector3((COLUMNS - 1) * SPACING * 0.5, 0.0, (rows - 1) * SPACING * 0.5)
	_camera.look_at_from_position(center + Vector3(0.0, 2000.0, 0.0), center, Vector3.FORWARD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for k in QUADS:
		var theta := 0.0 if k == 0 else deg_to_rad(75.0) * sqrt(rng.randf())
		var phi := rng.randf() * TAU
		var n := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
		var basis := Basis(Quaternion(Vector3.UP, n))
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.0, 1.0)
		quad.mesh = plane
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.transform = Transform3D(basis, Vector3((k % COLUMNS) * SPACING, 0.0, (k / COLUMNS) * SPACING))
		_viewport.add_child(quad)
		_quads.append(quad)
		_normals.append((basis * Vector3.UP).normalized())


## Renders with one material on every quad and returns the red channel at
## each quad's center.
func _render(material: Material) -> PackedFloat32Array:
	for quad in _quads:
		quad.material_override = material
	for k in 4:
		await process_frame
	var image := _viewport.get_texture().get_image()
	var values := PackedFloat32Array()
	for quad in _quads:
		var pixel := _camera.unproject_position(quad.global_position)
		values.append(image.get_pixel(int(pixel.x), int(pixel.y)).r)
	return values


func _material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\n" + code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _check_conventions() -> void:
	# Quad 0 faces straight up: N.L = cos 55 degrees.
	var color := await _render(_material("void fragment() { ALBEDO = vec3(1.0); } void light() { DIFFUSE_LIGHT += 0.1 * LIGHT_COLOR; }"))
	_expect(absf(color[0] - 0.1 * PI) < 1e-3, "0.1 * LIGHT_COLOR reads %.4f (0.1 pi = %.4f)" % [color[0], 0.1 * PI])
	var diffuse := await _render(_material("void fragment() { ALBEDO = vec3(0.5); } void light() { DIFFUSE_LIGHT += vec3(0.25); }"))
	_expect(absf(diffuse[0] - 0.125) < 1e-3, "DIFFUSE_LIGHT 0.25 with ALBEDO 0.5 reads %.4f (times albedo)" % diffuse[0])
	var specular := await _render(_material("void fragment() { ALBEDO = vec3(0.5); } void light() { SPECULAR_LIGHT += vec3(0.25); }"))
	_expect(absf(specular[0] - 0.25) < 1e-3, "SPECULAR_LIGHT 0.25 with ALBEDO 0.5 reads %.4f (unchanged)" % specular[0])
	var default_diffuse := await _render(_material("render_mode specular_disabled; void fragment() { ALBEDO = vec3(0.5); ROUGHNESS = 1.0; }"))
	var lambert := await _render(_material("render_mode diffuse_lambert, specular_disabled; void fragment() { ALBEDO = vec3(0.5); ROUGHNESS = 1.0; }"))
	var custom := LitShader.material(_base_material(0.5, 1.0), _include)
	custom.set_shader_parameter("light_model", Brdf.Model.LAMBERT)
	var own := await _render(custom)
	var worst_default := 0.0
	var worst_own := 0.0
	for k in QUADS:
		worst_default = maxf(worst_default, absf(default_diffuse[k] - lambert[k]))
		worst_own = maxf(worst_own, absf(own[k] - lambert[k]))
	_expect(worst_default < 1e-3, "default diffuse equals diffuse_lambert: max difference %.5f" % worst_default)
	_expect(worst_own < 1e-3, "custom Lambert equals diffuse_lambert: max difference %.5f" % worst_own)


func _check_models() -> void:
	for roughness in [0.5, 0.92]:
		for model in Brdf.Model.values():
			var material := LitShader.material(_base_material(0.5, roughness), _include)
			material.set_shader_parameter("light_model", model)
			var values := await _render(material)
			var p := Brdf.Params.new()
			p.albedo = 0.5
			p.roughness = roughness
			var worst := 0.0
			for k in QUADS:
				var expected := Brdf.reflected(model, _normals[k], _light_direction, Vector3.UP, p)
				worst = maxf(worst, absf(values[k] - expected) - 0.002 * expected)
			_expect(worst < 2e-3, "%s, roughness %.2f: pixels equal Brdf.reflected() (worst excess %.5f)" % [Brdf.MODEL_NAMES[model], roughness, worst])


func _base_material(albedo: float, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _base
	material.set_shader_parameter("albedo", albedo)
	material.set_shader_parameter("rough", roughness)
	return material


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok    " + message)
