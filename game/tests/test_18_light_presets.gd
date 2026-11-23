extends SceneTree
## Lesson 18: LightPreset, LightPresetSwitch and the Lesson 18 scene,
## headless (no frame times and no pixels; tools/light_perf.sh measures
## those in a window).
##   1. LightPreset: the defaults equal the Sun of the Lesson 17 scene and
##      an Environment without SSAO, SSIL, SDFGI; cascade_ends() and
##      cascade_texels() for the three shadow modes; summary().
##   2. The preset files: 15 presets with distinct titles; preset 0 equals
##      LightPreset.new() in every exported property; every other preset
##      differs from it (the differences are printed); one preset without
##      sun shadow (the reference of the edge probe).
##   3. The scene: Lighting starts on preset 0 and leaves the Sun as the
##      Lesson 17 scene has it; F8 steps through all presets, and after
##      each the Sun, the Environment and the VoxelGI node hold the
##      preset's values; the VoxelGI preset does not bake headless; the
##      first SDFGI preset frees the three raymarched formations; F8
##      wraps around; F9 steps the bias override and the override
##      survives F8; the project setting of the atlas size is unchanged;
##      the HUD names the preset.
##   4. Input map: F8, F9 keyboard only; the Lesson 15-17 bindings;
##      run/main_scene; the Lesson 17 scene has no Lighting or VoxelGI.
## Run: Godot --headless --path game -s res://tests/test_18_light_presets.gd

const SCENE := "res://scenes/lessons/18_shadows_and_gi.tscn"
const OLD_SCENE := "res://scenes/lessons/17_writing_light.tscn"

var _failures := 0


func _initialize() -> void:
	_check_preset_defaults()
	_check_preset_files()
	await _check_scene()
	_check_input_map()
	print("test_18_light_presets: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_preset_defaults() -> void:
	var old: Node = (load(OLD_SCENE) as PackedScene).instantiate()
	var sun := old.get_node("Sun") as DirectionalLight3D
	var environment := (old.get_node("WorldEnvironment") as WorldEnvironment).environment
	var p := LightPreset.new()
	_expect(p.shadows_enabled == sun.shadow_enabled and p.shadow_mode == sun.directional_shadow_mode and is_equal_approx(p.split_1, sun.directional_shadow_split_1) and is_equal_approx(p.split_2, sun.directional_shadow_split_2) and is_equal_approx(p.split_3, sun.directional_shadow_split_3) and is_equal_approx(p.max_distance, sun.directional_shadow_max_distance) and p.blend_splits == sun.directional_shadow_blend_splits, "defaults: shadow layout of the Lesson 17 Sun (PSSM 4, %.1f/%.1f/%.1f of %.0f m)" % [p.split_1, p.split_2, p.split_3, p.max_distance])
	_expect(is_equal_approx(p.bias, sun.shadow_bias) and is_equal_approx(p.normal_bias, sun.shadow_normal_bias) and is_equal_approx(p.angular_distance_degrees, sun.light_angular_distance), "defaults: bias %.2f, normal bias %.1f, sun size %.1f, as the Lesson 17 Sun" % [p.bias, p.normal_bias, p.angular_distance_degrees])
	_expect(p.atlas_size == ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size") and p.filter_quality == ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"), "defaults: atlas %d and filter %d, the project settings" % [p.atlas_size, p.filter_quality])
	_expect(p.ssao == environment.ssao_enabled and p.ssil == environment.ssil_enabled and (p.gi == LightPreset.Gi.SDFGI) == environment.sdfgi_enabled and p.gi == LightPreset.Gi.NONE, "defaults: no SSAO, SSIL, SDFGI, as the Lesson 17 Environment")
	old.free()

	_expect(p.cascade_ends() == PackedFloat32Array([12.0, 24.0, 60.0, 120.0]) and p.cascade_texels() == 2048, "PSSM 4: cascades end at 12, 24, 60, 120 m, 2048 texels each")
	p.shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_expect(p.cascade_ends() == PackedFloat32Array([12.0, 120.0]) and p.cascade_texels() == 2048, "PSSM 2: cascades end at 12, 120 m")
	p.shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_expect(p.cascade_ends() == PackedFloat32Array([120.0]) and p.cascade_texels() == 4096, "orthogonal: one map to 120 m, 4096 texels")
	p.shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_expect(p.summary() == "PSSM 4, 120 m, soft low | sky ambient", "summary(): %s" % p.summary())
	p.ssao = true
	p.gi = LightPreset.Gi.SDFGI
	p.shadows_enabled = false
	_expect(p.summary() == "no sun shadow | SSAO, SDFGI", "summary(): %s" % p.summary())


func _check_preset_files() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var lighting := scene.get_node("Lighting") as LightPresetSwitch
	var presets := lighting.presets
	var titles := {}
	for preset in presets:
		titles[preset.title] = true
	_expect(presets.size() == 15 and titles.size() == 15, "15 presets with distinct titles")
	var plain := LightPreset.new()
	_expect(_differences(presets[0], plain).is_empty(), "preset 0 (%s) equals the defaults" % presets[0].title)
	var all_differ := true
	for i in range(1, presets.size()):
		var names := _differences(presets[i], plain)
		names.erase("title")
		all_differ = all_differ and not names.is_empty()
		print("      preset %d %-16s differs in %s" % [i, presets[i].title, ", ".join(names)])
	_expect(all_differ, "every other preset differs from preset 0")
	var unshadowed := presets.filter(func(p: LightPreset) -> bool: return not p.shadows_enabled)
	_expect(unshadowed.size() == 1, "one preset without sun shadow (the edge probe's reference)")
	scene.free()


func _check_scene() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	for k in 5:
		await process_frame
	var lighting := scene.get_node("Lighting") as LightPresetSwitch
	var sun := scene.get_node("Sun") as DirectionalLight3D
	var environment := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var voxel_gi := scene.get_node("VoxelGI") as VoxelGI
	var formations := scene.get_node("Formations")
	_expect(lighting.sun == sun and lighting.world_environment == scene.get_node("WorldEnvironment") and lighting.voxel_gi == voxel_gi, "Lighting wired to Sun, WorldEnvironment, VoxelGI")
	_expect(voxel_gi.data == null and not voxel_gi.visible, "VoxelGI: no baked data in the scene, hidden")

	var old: Node = (load(OLD_SCENE) as PackedScene).instantiate()
	var old_sun := old.get_node("Sun") as DirectionalLight3D
	var same := true
	for property in ["shadow_enabled", "directional_shadow_mode", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_max_distance", "directional_shadow_blend_splits", "shadow_bias", "shadow_normal_bias", "light_angular_distance"]:
		same = same and sun.get(property) == old_sun.get(property)
	old.free()
	_expect(lighting.index == 0 and same and not environment.ssao_enabled and not environment.sdfgi_enabled, "start: preset 0, Sun as in the Lesson 17 scene")
	_expect(formations.get_child_count() == 3 and lighting.conflicts_freed == 0, "start: three formations")

	# F8 through every preset and around.
	var all_applied := true
	for i in range(1, lighting.presets.size() + 1):
		scene._unhandled_input(_key(KEY_F8))
		await process_frame
		var expected := i % lighting.presets.size()
		var applied := lighting.index == expected and _applied(lighting.presets[expected], sun, environment, voxel_gi)
		all_applied = all_applied and applied
		if not applied:
			printerr("      preset %d not applied" % expected)
		var preset := lighting.presets[expected]
		if preset.gi == LightPreset.Gi.VOXEL_GI:
			_expect(voxel_gi.visible and not lighting.voxel_baked and voxel_gi.data == null, "%s: VoxelGI shown, not baked headless" % preset.title)
		if preset.gi == LightPreset.Gi.SDFGI and lighting.conflicts_freed > 0:
			_expect(formations.get_child_count() == 0 and lighting.conflicts_freed == 3, "%s: the three formations freed" % preset.title)
	_expect(all_applied and lighting.index == 0, "F8 x %d: each preset applied to Sun, Environment and VoxelGI, back to preset 0" % lighting.presets.size())
	_expect(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size") == 4096, "project setting of the atlas size untouched")

	# F9: bias override.
	var steps := [Vector2(0.1, 2.0)]
	for b in lighting.bias_steps:
		steps.append(b)
	steps.append(Vector2(0.1, 2.0))
	var bias_ok := true
	for k in range(1, steps.size()):
		scene._unhandled_input(_key(KEY_F9))
		bias_ok = bias_ok and is_equal_approx(sun.shadow_bias, steps[k].x) and is_equal_approx(sun.shadow_normal_bias, steps[k].y)
	_expect(bias_ok and lighting.bias_step == -1, "F9 x %d: bias %s, back to the preset's own" % [steps.size() - 1, steps])
	scene._unhandled_input(_key(KEY_F9))
	scene._unhandled_input(_key(KEY_F8))
	_expect(lighting.index == 1 and is_equal_approx(sun.shadow_bias, lighting.bias_steps[0].x) and is_equal_approx(sun.shadow_normal_bias, lighting.bias_steps[0].y), "the F9 override survives F8")
	scene._unhandled_input(_key(KEY_F9))
	scene._unhandled_input(_key(KEY_F9))
	scene._unhandled_input(_key(KEY_F9))

	await process_frame
	var label := scene.get_node("HUD/LightLabel") as Label
	_expect(label.text.contains("preset 2/15 no sun shadow") and label.text.contains("[F9]"), "HUD/LightLabel names the preset and F9")
	scene.queue_free()
	await process_frame


## True when the Sun, the Environment and the VoxelGI node hold the
## preset's values (the bias is the preset's, since F9 was not pressed).
func _applied(p: LightPreset, sun: DirectionalLight3D, environment: Environment, voxel_gi: VoxelGI) -> bool:
	return sun.shadow_enabled == p.shadows_enabled \
		and sun.directional_shadow_mode == p.shadow_mode \
		and is_equal_approx(sun.directional_shadow_split_1, p.split_1) \
		and is_equal_approx(sun.directional_shadow_split_2, p.split_2) \
		and is_equal_approx(sun.directional_shadow_split_3, p.split_3) \
		and is_equal_approx(sun.directional_shadow_max_distance, p.max_distance) \
		and sun.directional_shadow_blend_splits == p.blend_splits \
		and is_equal_approx(sun.shadow_bias, p.bias) \
		and is_equal_approx(sun.shadow_normal_bias, p.normal_bias) \
		and is_equal_approx(sun.light_angular_distance, p.angular_distance_degrees) \
		and environment.ssao_enabled == p.ssao \
		and environment.ssil_enabled == p.ssil \
		and environment.sdfgi_enabled == (p.gi == LightPreset.Gi.SDFGI) \
		and voxel_gi.visible == (p.gi == LightPreset.Gi.VOXEL_GI)


## Names of the exported properties in which two presets differ.
func _differences(a: LightPreset, b: LightPreset) -> Array:
	var names := []
	for property in a.get_property_list():
		if property["usage"] & PROPERTY_USAGE_STORAGE and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if a.get(property["name"]) != b.get(property["name"]):
				names.append(property["name"])
	return names


func _check_input_map() -> void:
	_expect(_keys(&"cycle_light_preset") == [KEY_F8] and _keys(&"cycle_shadow_bias") == [KEY_F9], "F8, F9 bound, keyboard only")
	_expect(_keys(&"cycle_shading_model") == [KEY_F5] and _keys(&"cycle_light_term") == [KEY_F6] and _keys(&"toggle_lesson_hud") == [KEY_F7], "Lesson 17 keys F5, F6, F7")
	_expect(_has_key(&"toggle_crawl", KEY_F3) and _has_button(&"toggle_crawl", JOY_BUTTON_GUIDE) and _has_key(&"toggle_crawl_debug", KEY_F4), "Lesson 16 keys F3 (and Guide), F4")
	var guide_actions := InputMap.get_actions().filter(func(a: StringName) -> bool: return _has_button(a, JOY_BUTTON_GUIDE))
	_expect(guide_actions == [&"toggle_crawl"], "Guide carries one action: %s" % [guide_actions])
	_expect(_has_key(&"cycle_tick_rate", KEY_T) and _has_button(&"cycle_tick_rate", JOY_BUTTON_DPAD_UP), "cycle_tick_rate on T and D-pad up (Lesson 02)")
	_expect(_has_key(&"cycle_stance_tick_rate", KEY_9) and not _has_key(&"cycle_tick_rate", KEY_9), "cycle_stance_tick_rate on 9 (Lesson 14)")
	_expect(ProjectSettings.get_setting("application/run/main_scene") == SCENE, "run/main_scene")
	var old: Node = (load(OLD_SCENE) as PackedScene).instantiate()
	_expect(old.get_node_or_null("Lighting") == null and old.get_node_or_null("VoxelGI") == null, "Lesson 17 scene has no Lighting or VoxelGI")
	old.free()


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
