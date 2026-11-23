extends SceneTree
## Lesson 03: checks the lesson scene and its keys.
##   1. terrain_painted.gdshader compiles and declares the uniforms that
##      sandbox.gd (debug_view) and painting_the_ground.gd write.
##   2. The Lesson 01 material still uses terrain.gdshader.
##   3. In the lesson scene, the V, C, M, F actions change paint_view,
##      show_contours, the tonemapper (five steps return to the start),
##      and fog; Tab still changes debug_view on the painted material.
##   4. The RampTower shares the terrain's material, stands at ground
##      height, and has a ramp of 60 degrees or more (O3 compares the
##      projections there; the terrain's slopes stay below 41 degrees).
## Headless runs compile shaders but draw nothing; tools/render_check.sh
## shows the result.
## Run: Godot --headless --path game -s res://tests/test_03_painted_scene.gd

const SCENE_PATH := "res://scenes/lessons/03_painting_the_ground.tscn"

var _failures := 0


func _initialize() -> void:
	var shader := load("res://shaders/terrain_painted.gdshader") as Shader
	var names: Array[String] = []
	for uniform in shader.get_shader_uniform_list():
		names.append(uniform.name)
	for required in ["debug_view", "paint_view", "show_contours", "contour_interval", "ground_noise", "triplanar_sharpness"]:
		_expect(required in names, "terrain_painted.gdshader lacks uniform " + required)

	var lesson_01_material := load("res://data/terrain/terrain_material.tres") as ShaderMaterial
	_expect(lesson_01_material.shader.resource_path == "res://shaders/terrain.gdshader", "terrain_material.tres no longer uses terrain.gdshader")

	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	var material := (scene.get_node("Terrain") as Terrain).material as ShaderMaterial
	_expect(material.get_shader_parameter("ground_noise") is NoiseTexture2D, "painted material has no noise texture")
	var environment: Environment = scene.get_node("WorldEnvironment").environment

	var tower := scene.get_node("RampTower") as RampTower
	_expect(tower.material == material, "RampTower does not share the terrain's painted material")
	var ground := (scene.get_node("Terrain") as Terrain).height_at(tower.position.x, tower.position.z)
	_expect(absf(tower.position.y - ground) < 1e-3, "RampTower is not at ground height")
	var steepest := 0.0
	for angle in tower.ramp_angles_degrees:
		steepest = maxf(steepest, angle)
	_expect(steepest >= 60.0, "RampTower has no ramp of 60 degrees or more")

	_press(scene, "cycle_paint_view")
	_expect(material.get_shader_parameter("paint_view") == 1, "V does not set paint_view to 1")
	var contours_before: bool = material.get_shader_parameter("show_contours")
	_press(scene, "toggle_contours")
	_expect(material.get_shader_parameter("show_contours") == not contours_before, "C does not toggle show_contours")

	var tonemap_start := environment.tonemap_mode
	var seen: Array[int] = []
	for i in 5:
		_press(scene, "cycle_tonemapper")
		seen.append(environment.tonemap_mode)
	_expect(environment.tonemap_mode == tonemap_start, "five presses of M do not return to the first tonemapper")
	_expect(Environment.TONE_MAPPER_LINEAR in seen and Environment.TONE_MAPPER_FILMIC in seen, "M does not reach Linear and Filmic")

	var fog_before := environment.fog_enabled
	_press(scene, "toggle_fog")
	_expect(environment.fog_enabled == not fog_before, "F does not toggle fog")

	_press(scene, "cycle_debug_view")
	_expect(material.get_shader_parameter("debug_view") == 1, "Tab does not set debug_view on the painted material")

	# Put the shared material back, so later scenes in this process start clean.
	material.set_shader_parameter("paint_view", 0)
	material.set_shader_parameter("debug_view", 0)
	material.set_shader_parameter("show_contours", contours_before)

	print("test_03_painted_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _press(scene: Node, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene._unhandled_input(event)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
