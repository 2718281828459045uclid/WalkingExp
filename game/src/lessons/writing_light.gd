extends "res://src/lessons/crawling_and_scrambling.gd"
## Root script of scenes/lessons/17_writing_light.tscn.
##
## Extends src/lessons/crawling_and_scrambling.gd (Lesson 16), so every key
## of Lessons 01-16 still works. The scene adds two nodes:
##   Shading   a ShadingSwitch (src/render/shading_switch.gd): switches the
##             Terrain, the Boulders and the ClimbFace between the built-in
##             light and the four custom models
##   Gallery   a ShadingGallery (src/render/shading_gallery.gd): five
##             columns of ground tile and rock, one per mode, labelled
## and a label HUD/LightLabel. This script adds:
##   F5   next shading mode on the terrain and the rocks
##   F6   diffuse + specular / diffuse only / specular only (custom modes
##        and the gallery's custom columns)
##   F7   shows this lesson's label or the labels of Lessons 01-16
## The CrawlGap, the Slab and the StepRow keep the built-in light: they
## share the terrain's material but are not targets of the switch, so
## they stay as a reference beside the switched terrain.

@onready var _shading: ShadingSwitch = $Shading
@onready var _gallery: ShadingGallery = $Gallery
@onready var _light_label: Label = $HUD/LightLabel
@onready var _sun: DirectionalLight3D = $Sun
@onready var _earlier_labels: Array[Label] = [$HUD/Label, $HUD/RockLabel]

## Extra camera pitch at the start, in degrees (negative looks down), so
## that the gallery appears above the player's head.
@export var start_pitch_degrees: float = 0.0

## The parameters the HUD line evaluates Brdf with (the shader defaults).
var _hud_params := Brdf.Params.new()


func _ready() -> void:
	super()
	# Turn the camera toward the gallery's center (the formula of
	# climbing.gd), so that the five columns are in view at the start.
	var d := _gallery.global_position - _player.global_position
	var pivot := _player.get_node("CameraPivot") as Node3D
	_player._rotate_camera(atan2(-d.x, -d.z) - pivot.rotation.y, start_pitch_degrees * PI / 180.0)
	# Q: Why hide the labels of the earlier lessons?
	# A: Together they cover most of a 1280 x 720 window, and this lesson
	#    is about the image behind them. F7 brings them back.
	_show_earlier_labels(false)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if _shading == null:
		return
	if event.is_action_pressed("cycle_shading_model"):
		_shading.cycle_mode()
	elif event.is_action_pressed("cycle_light_term"):
		_shading.cycle_term()
		_gallery.set_term(_shading.term)
	elif event.is_action_pressed("toggle_lesson_hud"):
		_show_earlier_labels(not _earlier_labels[0].visible)


func _show_earlier_labels(shown: bool) -> void:
	for label in _earlier_labels:
		label.visible = shown
	_light_label.visible = not shown


## Q: What does the third line show?
## A: The value pi * f * cos(theta_l) of each model for a white surface
##    with the ground's normal under the player, the sun's direction and
##    the direction to the camera: the brightness each model gives that
##    piece of ground, per unit of sun energy, before albedo (Brdf, the
##    CPU copy of the shader). Walk around and watch the ratios change
##    with the angles.
func _update_hud() -> void:
	super()
	if _shading == null or _light_label == null:
		return
	var feet := _player.global_position
	var ground_point := Vector3(feet.x, _terrain.height_at(feet.x, feet.z), feet.z)
	var n := _terrain.field.normal(Vector2(feet.x - _terrain.global_position.x, feet.z - _terrain.global_position.z))
	var l := _sun.global_transform.basis.z
	var camera := get_viewport().get_camera_3d()
	var v := Vector3.UP
	if camera != null:
		v = (camera.global_position - ground_point).normalized()
	var values: Array[float] = []
	for model in Brdf.Model.values():
		values.append(Brdf.reflected(model, n, l, v, _hud_params))
	_light_label.text = "light: %s   [F5]   term: %s   [F6]\nsun %.0f° above the horizon   ground here: N·L %.2f   N·V %.2f\nwhite ground here:  Lambert %.2f   wrap %.2f   O-N %.2f   GGX %.2f" % [
		ShadingSwitch.MODE_NAMES[_shading.mode],
		ShadingSwitch.TERM_NAMES[_shading.term],
		rad_to_deg(asin(clampf(l.y, -1.0, 1.0))),
		n.dot(l),
		n.dot(v),
		values[0],
		values[1],
		values[2],
		values[3],
	]
