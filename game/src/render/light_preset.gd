class_name LightPreset
extends Resource
## One configuration of the sun's shadows and of global illumination
## (Lesson 18). A LightPresetSwitch (src/render/light_preset_switch.gd)
## writes these values into the scene's DirectionalLight3D, its
## Environment, its VoxelGI node and two renderer-wide settings.
##
## How this file relates to the others:
##   data/lighting/*.tres                 one preset per file; the Lesson 18
##                                        scene lists them in the switch
##   LightPresetSwitch                    applies a preset (F8) and overrides
##                                        its bias (F9)
##   tools/godot/light_perf.gd            measures each preset's frame time
##                                        and image
##
## The defaults are the values of the Lesson 17 scene, so a preset made
## with no changes leaves that scene as it was.

enum Gi {
	NONE,      ## sky ambient only (Lessons 03-17)
	SDFGI,     ## signed distance field GI, built around the camera at run time
	VOXEL_GI,  ## the VoxelGI node, baked once on first use
}

const GI_NAMES: Array[String] = ["none", "SDFGI", "VoxelGI"]
const MODE_NAMES: Array[String] = ["orthogonal", "PSSM 2", "PSSM 4"]
const FILTER_NAMES: Array[String] = ["hard", "soft very low", "soft low", "soft medium", "soft high", "soft ultra"]

## Short name shown on the HUD and in the measurement table.
@export var title: String = "Lesson 17"

@export_group("Sun shadow")
@export var shadows_enabled: bool = true
## Orthogonal: one shadow map over the whole range. PSSM 2 / 4: the view
## range is cut into 2 or 4 slices (cascades), each with its own map.
@export var shadow_mode: DirectionalLight3D.ShadowMode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
## Ends of the first three cascades, as fractions of max_distance.
@export_range(0.0, 1.0, 0.01) var split_1: float = 0.1
@export_range(0.0, 1.0, 0.01) var split_2: float = 0.2
@export_range(0.0, 1.0, 0.01) var split_3: float = 0.5
## Distance from the camera, in meters, beyond which nothing is shadowed.
@export_range(1.0, 1000.0, 0.1) var max_distance: float = 120.0
## Cross-fade between neighboring cascades instead of a hard seam.
@export var blend_splits: bool = false
## Moves the receiving point toward the light (depth bias, scaled per
## cascade by the engine).
@export_range(0.0, 10.0, 0.001) var bias: float = 0.1
## Moves the receiving point along its normal (scaled per cascade).
@export_range(0.0, 10.0, 0.001) var normal_bias: float = 2.0
## Angular size of the sun in degrees. Above 0 the engine softens shadows
## with the distance to the caster (PCSS).
@export_range(0.0, 10.0, 0.01) var angular_distance_degrees: float = 0.0

@export_group("Renderer")
## Size in texels of the directional shadow atlas (all cascades share it).
@export_enum("1024:1024", "2048:2048", "4096:4096", "8192:8192") var atlas_size: int = 4096
## Filter of the shadow lookup: 0 hard ... 5 soft ultra
## (RenderingServer.ShadowQuality).
@export_range(0, 5) var filter_quality: int = 2

@export_group("Global illumination")
## Screen-space ambient occlusion.
@export var ssao: bool = false
## Screen-space indirect lighting.
@export var ssil: bool = false
@export var gi: Gi = Gi.NONE


## Q: What does one line on the HUD say about a preset?
## A: The shadow layout, its range and filter, then the GI terms that are
##    on, for example "PSSM 4, 120 m, soft low | SSAO, SDFGI".
func summary() -> String:
	var shadow := "no sun shadow"
	if shadows_enabled:
		shadow = "%s, %.0f m, %s" % [MODE_NAMES[shadow_mode], max_distance, FILTER_NAMES[filter_quality]]
		if blend_splits:
			shadow += ", blended"
		if angular_distance_degrees > 0.0:
			shadow += ", sun %.2f°" % angular_distance_degrees
		if atlas_size != 4096:
			shadow += ", atlas %d" % atlas_size
	var terms := PackedStringArray()
	if ssao:
		terms.append("SSAO")
	if ssil:
		terms.append("SSIL")
	if gi != Gi.NONE:
		terms.append(GI_NAMES[gi])
	if terms.is_empty():
		terms.append("sky ambient")
	return "%s | %s" % [shadow, ", ".join(terms)]


## Q: Why compute cascade ends here instead of reading them from Godot?
## A: The engine keeps them internal. These are the distances along the
##    view direction at which each map ends, the quantities Predict P3
##    works with: split_k × max_distance, and max_distance for the last.
func cascade_ends() -> PackedFloat32Array:
	match shadow_mode:
		DirectionalLight3D.SHADOW_ORTHOGONAL:
			return PackedFloat32Array([max_distance])
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return PackedFloat32Array([split_1 * max_distance, max_distance])
	return PackedFloat32Array([split_1 * max_distance, split_2 * max_distance, split_3 * max_distance, max_distance])


## The side length in texels of one cascade's square in the atlas: the
## whole atlas for orthogonal, half of it for PSSM 2 and PSSM 4 (the
## atlas is cut into two halves or four quadrants).
func cascade_texels() -> int:
	if shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL:
		return atlas_size
	return atlas_size / 2
