extends SceneTree
## Lesson 17: LitShader, ShadingSwitch, ShadingGallery and the Lesson 17
## scene, headless (no pixels; tests/test_17_light_pixels.gd checks those
## in a window).
##   1. LitShader: the generated code is the base code plus one #include
##      line; it compiles with the base uniforms and the five light_*
##      uniforms; one shader per base (cache); has_light_function();
##      copy_parameters() moves base uniforms and skips light_*.
##   2. The scene: Shading switches Terrain, Rocks/Boulders and ClimbFace;
##      it starts on the original materials; F5 steps through the four lit
##      modes (light_model 0..3, one lit material shared by both rocks)
##      and back; Tab's debug_view survives a switch; the Slab keeps the
##      original material; F6 sets light_term on the lit materials and the
##      gallery's lit columns; F7 swaps the labels.
##   3. The gallery: five columns labelled in mode order, column 0 on the
##      original materials, columns 1-4 lit with light_model 0..3, one
##      shared rock mesh, one height for all, no terrain above a tile, the
##      plinths reaching below the terrain.
##   4. Input map: F5, F6, F7, keyboard only; the Lesson 15-16 bindings.
##      run/main_scene; the Lesson 16 scene has no Shading or Gallery.
## Run: Godot --headless --path game -s res://tests/test_17_light_scene.gd

const LIGHT_UNIFORMS := ["light_model", "light_term", "light_wrap", "light_sigma_degrees", "light_f0"]

var _failures := 0


func _initialize() -> void:
	_check_lit_shader()
	await _check_scene()
	_check_input_map()
	print("test_17_light_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_lit_shader() -> void:
	var include := load("res://shaders/lighting/custom_light.gdshaderinc") as ShaderInclude
	for path in ["res://data/terrain/painted_terrain_material.tres", "res://data/rocks/weathered_rock_material.tres"]:
		var base := load(path) as ShaderMaterial
		var lit := LitShader.material(base, include)
		_expect(lit != null, "%s: lit copy made" % path.get_file())
		if lit == null:
			continue
		_expect(lit.shader.code.begins_with(base.shader.code) and lit.shader.code.contains("#include \"res://shaders/lighting/custom_light.gdshaderinc\""), "%s: base code plus the include" % path.get_file())
		var names := _uniform_names(lit.shader)
		var base_names := _uniform_names(base.shader)
		var all_base := true
		for n in base_names:
			all_base = all_base and names.has(n)
		var all_light := true
		for n in LIGHT_UNIFORMS:
			all_light = all_light and names.has(n)
		_expect(all_base and all_light and names.size() == base_names.size() + LIGHT_UNIFORMS.size(), "%s: compiles with %d base and %d light uniforms (%d)" % [path.get_file(), base_names.size(), LIGHT_UNIFORMS.size(), names.size()])
		_expect(LitShader.make(base.shader, include) == lit.shader, "%s: one generated shader per base" % path.get_file())
		_expect(not LitShader.has_light_function(base.shader.code) and LitShader.has_light_function(lit.shader.code + "\nvoid  light ( ) {}"), "%s: has_light_function()" % path.get_file())
		# copy_parameters: both directions, light_* skipped.
		var copy := base.duplicate() as ShaderMaterial
		lit.set_shader_parameter(base_names[0], _changed(lit.get_shader_parameter(base_names[0])))
		var count := LitShader.copy_parameters(lit, copy)
		_expect(count == base_names.size() and copy.get_shader_parameter(base_names[0]) == lit.get_shader_parameter(base_names[0]), "%s: %d uniforms copied lit -> original, light_* skipped" % [path.get_file(), count])
	_expect(not LitShader.has_light_function("void lighting() {}"), "has_light_function() ignores lighting()")


func _check_scene() -> void:
	var scene: Node = (load("res://scenes/lessons/17_writing_light.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for k in 5:
		await process_frame
	var shading := scene.get_node("Shading") as ShadingSwitch
	var terrain := scene.get_node("Terrain") as Terrain
	var boulders := scene.get_node("Rocks/Boulders") as SdfMesher
	var face := scene.get_node("ClimbFace") as SdfMesher
	var slab := scene.get_node("Slab") as BoxCourse
	var gallery := scene.get_node("Gallery") as ShadingGallery
	var painted := load("res://data/terrain/painted_terrain_material.tres") as ShaderMaterial
	var weathered := load("res://data/rocks/weathered_rock_material.tres") as ShaderMaterial
	_expect(shading != null and shading.targets == [terrain, boulders, face], "Shading targets Terrain, Rocks/Boulders, ClimbFace")
	_expect(shading.mode == ShadingSwitch.Mode.BUILT_IN and terrain.material == painted and boulders.material == weathered and face.material == weathered, "starts on the original materials")

	# F5 through the four lit modes and back.
	for m in range(1, 5):
		scene._unhandled_input(_key(KEY_F5))
		var lit := terrain.material as ShaderMaterial
		_expect(shading.mode == m and lit != painted and lit.get_shader_parameter("light_model") == m - 1, "F5 -> %s: terrain lit, light_model %d" % [ShadingSwitch.MODE_NAMES[m], m - 1])
		_expect(boulders.material == face.material and boulders.material != weathered and (boulders.material as ShaderMaterial).get_shader_parameter("light_model") == m - 1, "F5 -> %s: both rocks share one lit material" % ShadingSwitch.MODE_NAMES[m])
		_expect(_mesh_material(terrain) == lit, "F5 -> %s: the terrain mesh shows it" % ShadingSwitch.MODE_NAMES[m])
		if m == 1:
			scene._unhandled_input(_key(KEY_TAB))
			_expect(lit.get_shader_parameter("debug_view") == 1, "Tab sets debug_view on the shown (lit) material")
	_expect((terrain.material as ShaderMaterial).get_shader_parameter("debug_view") == 1, "debug_view kept across three switches")
	scene._unhandled_input(_key(KEY_F5))
	_expect(shading.mode == ShadingSwitch.Mode.BUILT_IN and terrain.material == painted and boulders.material == weathered, "fifth F5: back to the originals")
	_expect(painted.get_shader_parameter("debug_view") == 1, "debug_view copied back to the original")
	scene._unhandled_input(_key(KEY_TAB))
	scene._unhandled_input(_key(KEY_TAB))
	_expect(painted.get_shader_parameter("debug_view") == 0, "Tab twice more: lit view again")
	_expect(_mesh_material(slab) == painted, "the Slab keeps the original material")

	# F6: the term, on the switch's and the gallery's lit materials.
	scene._unhandled_input(_key(KEY_F6))
	var terms_ok := shading.term == ShadingSwitch.Term.DIFFUSE
	for lit in shading.lit_materials.values():
		terms_ok = terms_ok and (lit as ShaderMaterial).get_shader_parameter("light_term") == 1
	for column in gallery.columns:
		if column.mode != ShadingSwitch.Mode.BUILT_IN:
			terms_ok = terms_ok and column.tile_material.get_shader_parameter("light_term") == 1 and column.rock_material.get_shader_parameter("light_term") == 1
	_expect(terms_ok, "F6: diffuse only on every lit material")
	scene._unhandled_input(_key(KEY_F6))
	scene._unhandled_input(_key(KEY_F6))
	_expect(shading.term == ShadingSwitch.Term.ALL, "F6 three times: back to diffuse + specular")

	# F7: labels.
	var label := scene.get_node("HUD/Label") as Label
	var rock_label := scene.get_node("HUD/RockLabel") as Label
	var light_label := scene.get_node("HUD/LightLabel") as Label
	_expect(light_label.visible and not label.visible and not rock_label.visible and light_label.text.begins_with("light: built-in"), "start: the Lesson 17 label alone")
	scene._unhandled_input(_key(KEY_F7))
	_expect(not light_label.visible and label.visible and rock_label.visible, "F7: the labels of Lessons 01-16")
	scene._unhandled_input(_key(KEY_F7))
	_expect(light_label.visible and not label.visible, "F7 again: the Lesson 17 label")

	_check_gallery(gallery, terrain, painted, weathered)
	scene.queue_free()
	await process_frame


func _check_gallery(gallery: ShadingGallery, terrain: Terrain, painted: ShaderMaterial, weathered: ShaderMaterial) -> void:
	_expect(gallery.columns.size() == ShadingSwitch.Mode.size() and gallery.rock_mesh != null, "gallery: %d columns, rock meshed" % gallery.columns.size())
	var heights := []
	for column in gallery.columns:
		var i: int = column.mode
		_expect(column.label.text == ShadingSwitch.MODE_NAMES[i], "column %d labelled %s" % [i, column.label.text])
		if i == ShadingSwitch.Mode.BUILT_IN:
			_expect(column.tile_material == painted and column.rock_material == weathered and column.tile.material == painted, "column 0: the original materials")
		else:
			_expect(column.tile_material.get_shader_parameter("light_model") == i - 1 and column.rock_material.get_shader_parameter("light_model") == i - 1 and column.rock.mesh == gallery.rock_mesh and column.rock.material_override == column.rock_material, "column %d: lit, light_model %d, shared rock mesh" % [i, i - 1])
		heights.append(column.root.global_position.y)
		# No terrain above the tile's lowest point, and the plinth reaches
		# below the terrain, at every sample under the tile.
		var amplitude := gallery.tile_field.ripple_amplitude
		var above := -INF
		var below := INF
		for a in 9:
			for b in 9:
				var local := Vector3((a / 8.0 - 0.5) * gallery.tile_size, 0.0, (b / 8.0 - 0.5) * gallery.tile_size)
				var world := column.root.global_transform * local
				var ground := terrain.height_at(world.x, world.z)
				above = maxf(above, ground - (column.root.global_position.y - amplitude))
				below = minf(below, ground - (column.root.global_position.y - amplitude - column.plinth.mesh.size.y))
		_expect(above <= 1e-4 and below > 0.0, "column %d: terrain below the tile (%.3f m) and above the plinth's bottom (%.3f m)" % [i, above, below])
	var level := true
	for h in heights:
		level = level and absf(h - heights[0]) < 1e-5
	_expect(level, "all columns at one height (%.3f m)" % heights[0])


func _check_input_map() -> void:
	_expect(_keys(&"cycle_shading_model") == [KEY_F5] and _keys(&"cycle_light_term") == [KEY_F6] and _keys(&"toggle_lesson_hud") == [KEY_F7], "F5, F6, F7 bound, keyboard only")
	_expect(_has_key(&"toggle_crawl", KEY_F3) and _has_button(&"toggle_crawl", JOY_BUTTON_GUIDE) and _has_key(&"toggle_crawl_debug", KEY_F4), "Lesson 16 keys F3 (and Guide), F4")
	var guide_actions := InputMap.get_actions().filter(func(a: StringName) -> bool: return _has_button(a, JOY_BUTTON_GUIDE))
	_expect(guide_actions == [&"toggle_crawl"], "Guide carries one action: %s" % [guide_actions])
	_expect(_has_key(&"cycle_tick_rate", KEY_T) and _has_button(&"cycle_tick_rate", JOY_BUTTON_DPAD_UP), "cycle_tick_rate on T and D-pad up (Lesson 02)")
	_expect(_has_key(&"cycle_stance_tick_rate", KEY_9) and not _has_key(&"cycle_tick_rate", KEY_9), "cycle_stance_tick_rate on 9 (Lesson 14)")
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/lessons/17_writing_light.tscn", "run/main_scene")
	var old: Node = (load("res://scenes/lessons/16_crawling_and_scrambling.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Shading") == null and old.get_node_or_null("Gallery") == null and old.get_node_or_null("HUD/LightLabel") == null, "Lesson 16 scene has no Shading, Gallery or LightLabel")
	old.free()


func _uniform_names(shader: Shader) -> Array:
	var names := []
	for u in shader.get_shader_uniform_list():
		names.append(u["name"])
	return names


## A value different from the given one, of the same type. An unset
## uniform reads null; the first uniform of both shaders is an int.
func _changed(value: Variant) -> Variant:
	if value == null:
		return 1
	if value is int:
		return value + 1
	if value is float:
		return value + 0.25
	if value is bool:
		return not value
	if value is Color:
		return Color(0.1, 0.2, 0.3)
	return value


func _mesh_material(node: Node) -> Material:
	for child in node.get_children(true):
		if child is MeshInstance3D:
			return (child as MeshInstance3D).material_override
	return null


func _keys(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			codes.append((event as InputEventKey).physical_keycode)
		else:
			codes.append(-1)
	return codes


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
	else:
		print("ok    " + message)
