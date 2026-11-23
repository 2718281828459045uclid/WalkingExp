extends "res://src/lessons/field_to_mesh.gd"
## Root script of scenes/lessons/09_implicit_curvature.tscn.
##
## Extends src/lessons/field_to_mesh.gd (Lesson 08), so every key of
## Lessons 01-08 still works. In this scene Rocks/Boulders is a
## CurvatureMesher (src/sdf/curvature_mesher.gd) with the material
## data/rocks/weathered_rock_material.tres. This script:
##   U  cycles the rock shader's view: weathered, H map, K map, normals
##   I  switches the mesh normals between trilinear (Lesson 08) and
##      gradient (Lesson 09)
## and appends the curvature timing and normal comparison to
## HUD/RockLabel.

const CURVATURE_VIEW_NAMES: PackedStringArray = ["weathered", "mean H", "gaussian K", "normals"]
const NORMAL_SOURCE_NAMES: PackedStringArray = ["trilinear", "gradient"]

var _curvature_view := 0


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_curvature_view"):
		_curvature_view = (_curvature_view + 1) % CURVATURE_VIEW_NAMES.size()
		var rock_material := _boulders.material as ShaderMaterial
		if rock_material != null:
			rock_material.set_shader_parameter("curvature_view", _curvature_view)
	elif event.is_action_pressed("toggle_normal_source"):
		var mesher := _boulders as CurvatureMesher
		mesher.normal_source = 1 - mesher.normal_source


func _update_hud() -> void:
	super()
	var mesher := _boulders as CurvatureMesher
	if mesher == null:
		return
	var angles := mesher.normal_angle_stats()
	_rock_label.text += "\nshade: %s   [U]   normals: %s   [I]\ncurvature %.0f ms   normal angle %.2f avg, %.0f max" % [
		CURVATURE_VIEW_NAMES[_curvature_view],
		NORMAL_SOURCE_NAMES[mesher.normal_source],
		mesher.curvature_milliseconds,
		angles.x,
		angles.y,
	]
