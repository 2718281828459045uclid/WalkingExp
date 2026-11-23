extends "res://src/lessons/sdf_primitives.gd"
## Root script of scenes/lessons/08_field_to_mesh.tscn.
##
## Extends src/lessons/sdf_primitives.gd (Lesson 07), so every key of
## Lessons 01-07 still works. This script:
##   R  cycles what the rocks show: mesh, mesh and slices, slices only
##   J  switches pass 1 of the mesher between GPU and CPU and rebuilds
## and writes the mesh size and the measured timings into HUD/RockLabel,
## a second label at the top right (the first one is full).
##
## The SdfMesher node Rocks/Boulders (src/sdf/sdf_mesher.gd) samples the
## same boulder_pile.tres as the slices and builds the mesh and the
## collision shape. Its collision is always present, whatever R shows.

const ROCK_VIEW_NAMES: PackedStringArray = ["mesh", "mesh + slices", "slices"]

@onready var _boulders: SdfMesher = $Rocks/Boulders
@onready var _rock_label: Label = $HUD/RockLabel

var _rock_view := 0


func _ready() -> void:
	super()
	_apply_rock_view()


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_rock_view"):
		_rock_view = (_rock_view + 1) % ROCK_VIEW_NAMES.size()
		_apply_rock_view()
	elif event.is_action_pressed("toggle_mesher_backend"):
		# The setter queues a rebuild for the end of the frame.
		_boulders.use_gpu = not _boulders.use_gpu


func _apply_rock_view() -> void:
	_boulders.visible = _rock_view != 2
	_slice_horizontal.visible = _rock_view != 0
	_slice_vertical.visible = _rock_view != 0


func _update_hud() -> void:
	super()
	# Q: Why "gpu" and "cpu" from used_gpu instead of use_gpu?
	# A: use_gpu is the request. Without a RenderingDevice (headless) or
	#    without the shader the mesher falls back to the CPU, and the HUD
	#    reports what ran.
	_rock_label.text = "rocks: %s   [R]\npass 1: %s   [J]   cell %.2f m\n%d vertices   %d triangles\nsample %.0f ms   vertices %.1f ms\nfaces %.0f ms   collision %.0f ms" % [
		ROCK_VIEW_NAMES[_rock_view],
		"gpu" if _boulders.used_gpu else "cpu",
		_boulders.cell_size,
		_boulders.vertex_count(),
		_boulders.triangle_count(),
		_boulders.sample_milliseconds,
		_boulders.vertex_milliseconds,
		_boulders.face_milliseconds,
		_boulders.collision_milliseconds,
	]
