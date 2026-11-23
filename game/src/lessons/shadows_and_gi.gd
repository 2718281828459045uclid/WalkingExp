extends "res://src/lessons/writing_light.gd"
## Root script of scenes/lessons/18_shadows_and_gi.tscn.
##
## Extends src/lessons/writing_light.gd (Lesson 17), so every key of
## Lessons 01-17 still works. The scene adds two nodes:
##   VoxelGI    a VoxelGI box over the play area, without baked data
##   Lighting   a LightPresetSwitch (src/render/light_preset_switch.gd)
##              with the presets of data/lighting/
## This script adds:
##   F8   next lighting preset (shadow layout, filter, GI)
##   F9   next shadow bias: the preset's own, none, depth bias only,
##        normal bias only (the acne and peter-panning study)
## and two lines on HUD/LightLabel: the preset, the bias, the number of
## draw calls and triangles the shadow pass and the main pass rendered in
## the last frame, and the frame time.

@onready var _lighting: LightPresetSwitch = $Lighting

## Moving average of the frame time, milliseconds.
var _frame_ms := 0.0


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if _lighting == null:
		return
	if event.is_action_pressed("cycle_light_preset"):
		_lighting.cycle()
	elif event.is_action_pressed("cycle_shadow_bias"):
		_lighting.cycle_bias()


func _process(delta: float) -> void:
	super(delta)
	_frame_ms += (delta * 1000.0 - _frame_ms) * 0.05


## Q: What do the draw-call numbers count?
## A: RenderingServer counts, per viewport and per pass, the draw calls
##    and primitives (triangles) of the last frame. The shadow pass draws
##    every caster once per cascade it falls in; the visible pass draws
##    what the camera sees. They are exact and free to read, unlike the
##    frame time, which also holds the CPU's work and, with vsync on, the
##    wait for the display.
func _update_hud() -> void:
	super()
	if _lighting == null or _light_label == null:
		return
	var viewport := get_viewport().get_viewport_rid()
	var bias := _lighting.effective_bias()
	_light_label.text += "\npreset %s   [F8]\nbias %.2f, normal bias %.1f%s   [F9]   shadow pass %d draws, %dk tris   main pass %d draws, %dk tris   frame %.1f ms" % [
		_lighting.describe(),
		bias.x,
		bias.y,
		"" if _lighting.bias_step < 0 else " (override)",
		RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		_frame_ms,
	]
