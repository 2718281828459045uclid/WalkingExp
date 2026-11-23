class_name LightPresetSwitch
extends Node
## Applies LightPreset resources to the scene's sun, environment and
## VoxelGI node (Lesson 18, F8), and overrides the shadow bias for the
## acne and peter-panning study (F9).
##
## How this file relates to the others:
##   LightPreset (src/render/light_preset.gd)   the data of one preset
##   data/lighting/*.tres                       the presets the scene lists
##   src/lessons/shadows_and_gi.gd              calls cycle() and
##                                              cycle_bias(), prints
##                                              describe() on the HUD
##   tools/godot/light_perf.gd                  calls apply() for each
##                                              preset and measures
##
## What a preset touches, and where it lives:
##   DirectionalLight3D   shadow mode, splits, range, blend, bias, sun size
##   Environment          SSAO, SSIL, SDFGI
##   VoxelGI node         shown or hidden; baked the first time it is used
##   RenderingServer      shadow atlas size and filter quality: renderer-
##                        wide settings (project settings under
##                        rendering/lights_and_shadows) that last until
##                        the game quits

signal preset_changed(index: int)

## The light whose shadow the presets configure.
@export var sun: DirectionalLight3D
## The node that holds the Environment (SSAO, SSIL, SDFGI).
@export var world_environment: WorldEnvironment
## A VoxelGI node without baked data; shown only by VOXEL_GI presets.
@export var voxel_gi: VoxelGI
## The presets F8 steps through.
@export var presets: Array[LightPreset] = []
## The preset applied on entering the tree.
@export var start_preset: int = 0
## Nodes freed before SDFGI is first switched on (see free_sdfgi_conflicts()).
@export var sdfgi_conflicts: Array[Node] = []
## The (bias, normal bias) pairs F9 steps through after "the preset's own".
@export var bias_steps: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(0.1, 8.0)])

## Index of the preset in use.
var index := -1
## -1: the preset's own bias; else an index into bias_steps.
var bias_step := -1
## True once voxel_gi holds baked data.
var voxel_baked := false
## Duration of that bake, milliseconds.
var voxel_bake_milliseconds := 0.0
## Number of nodes freed by free_sdfgi_conflicts() (0 until then).
var conflicts_freed := 0


func _ready() -> void:
	if not presets.is_empty():
		apply(clampi(start_preset, 0, presets.size() - 1))


## The preset in use, or null before the first apply().
func current() -> LightPreset:
	if index < 0 or index >= presets.size():
		return null
	return presets[index]


func apply(i: int) -> void:
	if i < 0 or i >= presets.size() or presets[i] == null:
		push_error("LightPresetSwitch: no preset %d" % i)
		return
	index = i
	var preset := presets[i]
	_apply_shadow(preset)
	_apply_environment(preset)
	_apply_voxel_gi(preset)
	_apply_bias()
	preset_changed.emit(index)


func cycle() -> void:
	if not presets.is_empty():
		apply((index + 1) % presets.size())


## Steps through: the preset's own bias, then each pair of bias_steps.
func cycle_bias() -> void:
	bias_step += 1
	if bias_step >= bias_steps.size():
		bias_step = -1
	_apply_bias()


## The (bias, normal bias) pair in force.
func effective_bias() -> Vector2:
	if bias_step >= 0:
		return bias_steps[bias_step]
	var preset := current()
	if preset == null:
		return Vector2(sun.shadow_bias, sun.shadow_normal_bias)
	return Vector2(preset.bias, preset.normal_bias)


func _apply_shadow(preset: LightPreset) -> void:
	if sun == null:
		return
	sun.shadow_enabled = preset.shadows_enabled
	sun.directional_shadow_mode = preset.shadow_mode
	sun.directional_shadow_split_1 = preset.split_1
	sun.directional_shadow_split_2 = preset.split_2
	sun.directional_shadow_split_3 = preset.split_3
	sun.directional_shadow_max_distance = preset.max_distance
	sun.directional_shadow_blend_splits = preset.blend_splits
	sun.light_angular_distance = preset.angular_distance_degrees
	# Q: Why go through the RenderingServer for these two?
	# A: They are project settings, read once at startup. The server
	#    functions change them in the running renderer; the project file
	#    is not touched, and the change ends when the game quits.
	RenderingServer.directional_shadow_atlas_set_size(preset.atlas_size, ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true))
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.filter_quality as RenderingServer.ShadowQuality)


func _apply_environment(preset: LightPreset) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	if preset.gi == LightPreset.Gi.SDFGI:
		free_sdfgi_conflicts()
	var environment := world_environment.environment
	environment.ssao_enabled = preset.ssao
	environment.ssil_enabled = preset.ssil
	environment.sdfgi_enabled = preset.gi == LightPreset.Gi.SDFGI


func _apply_voxel_gi(preset: LightPreset) -> void:
	if voxel_gi == null:
		return
	var wanted := preset.gi == LightPreset.Gi.VOXEL_GI
	if wanted and not voxel_baked:
		bake_voxel_gi()
	voxel_gi.visible = wanted


## Q: Why bake at run time instead of in the editor?
## A: The terrain and the rocks are generated when the scene starts
##    (internal children, never saved), so an editor bake would have to
##    run in the editor's copy of them and store a VoxelGIData file of
##    several megabytes. Baked here, the data matches whatever the scene
##    generated. The bake voxelizes every visible GeometryInstance3D with
##    gi_mode STATIC inside the node's box, on the CPU.
## Q: What does a headless run bake?
## A: Nothing useful: its dummy renderer keeps no mesh data, so the data
##    comes back empty. The bake is skipped there.
func bake_voxel_gi() -> void:
	if voxel_gi == null or RenderingServer.get_rendering_device() == null:
		return
	var start := Time.get_ticks_usec()
	voxel_gi.bake(get_parent())
	voxel_bake_milliseconds = (Time.get_ticks_usec() - start) / 1000.0
	voxel_baked = true


func _apply_bias() -> void:
	if sun == null:
		return
	var b := effective_bias()
	sun.shadow_bias = b.x
	sun.shadow_normal_bias = b.y


## Q: Which nodes conflict with SDFGI, and why free them?
## A: The raymarched formations of Lesson 10. Their shaders write DEPTH.
##    When SDFGI is switched on, Godot 4.6.2 on Metal builds a pipeline of
##    every loaded spatial shader for SDFGI's passes, which have no depth
##    buffer, and refuses those shaders ("depthAttachmentPixelFormat is
##    not valid and shader writes to depth"), once per formation, with
##    more errors when the game quits. Hiding or detaching the nodes does
##    not help (measured); only freeing their shaders does. SDFGI could
##    not see the formations anyway: it voxelizes meshes, and a formation's
##    mesh is its bounding box.
func free_sdfgi_conflicts() -> void:
	for node in sdfgi_conflicts:
		if is_instance_valid(node):
			node.queue_free()
			conflicts_freed += 1
	sdfgi_conflicts.clear()


## One line for the HUD: the preset's number, title and summary.
func describe() -> String:
	var preset := current()
	if preset == null:
		return "no preset"
	return "%d/%d %s: %s" % [index + 1, presets.size(), preset.title, preset.summary()]
