extends "res://src/lessons/implicit_curvature.gd"
## Root script of scenes/lessons/10_raymarching.tscn.
##
## Extends src/lessons/implicit_curvature.gd (Lesson 09), so every key of
## Lessons 01-09 still works. In this scene the node Formations holds
## RaymarchVolume children (src/sdf/raymarch_volume.gd): rock formations
## drawn by sphere tracing, with no mesh. This script:
##   places each formation on the terrain (its y in the scene file is an
##     offset from the ground)
##   P  cycles the raymarch view: lit, step count, normals, mean curvature
##   X  cycles the step budget max_steps
##   Z  shows and hides all formations (to measure what they cost)
## and appends the frame time to HUD/RockLabel.

const MARCH_VIEW_NAMES: PackedStringArray = ["lit", "steps", "normals", "mean H"]
const STEP_BUDGETS: PackedInt32Array = [16, 32, 64, 96, 192]

@onready var _formations: Node3D = $Formations

var _march_view := 0
var _budget_index := 3
## Time per frame in milliseconds, smoothed over about 30 frames.
var frame_milliseconds := 0.0


func _ready() -> void:
	super()
	for volume in _volumes():
		volume.position.y += _terrain.height_at(volume.position.x, volume.position.z)
		volume.max_steps = STEP_BUDGETS[_budget_index]


## Q: Why the frame time and not the GPU time of the march alone?
## A: Godot can time the GPU (viewport_get_measured_render_time_gpu()),
##    but on the Metal backend of Godot 4.6 it returns 0. The frame time is
##    the wall-clock time between frames. With vsync on it is held at the
##    display's refresh interval (16.7 ms at 60 Hz) as long as the frame
##    fits; tools/raymarch_perf.sh switches vsync off to measure (README O5).
func _process(delta: float) -> void:
	# An exponential moving average: each frame moves 1/30 of the way.
	frame_milliseconds += (delta * 1000.0 - frame_milliseconds) / 30.0
	super(delta)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_raymarch_view"):
		_march_view = (_march_view + 1) % MARCH_VIEW_NAMES.size()
		for volume in _volumes():
			volume.debug_view = _march_view
	elif event.is_action_pressed("cycle_march_budget"):
		_budget_index = (_budget_index + 1) % STEP_BUDGETS.size()
		for volume in _volumes():
			volume.max_steps = STEP_BUDGETS[_budget_index]
	elif event.is_action_pressed("toggle_formations"):
		_formations.visible = not _formations.visible


func _volumes() -> Array[RaymarchVolume]:
	var found: Array[RaymarchVolume] = []
	for child in _formations.get_children():
		if child is RaymarchVolume:
			found.append(child)
	return found


func _update_hud() -> void:
	super()
	if _formations == null:
		return
	_rock_label.text += "\nmarch: %s [P]   steps %d [X]   %s [Z]\nframe %.2f ms" % [
		MARCH_VIEW_NAMES[_march_view],
		STEP_BUDGETS[_budget_index],
		"shown" if _formations.visible else "hidden",
		frame_milliseconds,
	]
