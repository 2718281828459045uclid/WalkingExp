extends "res://src/lessons/spatial_audio.gd"
## Root script of scenes/lessons/07_sdf_primitives.tscn.
##
## Extends src/lessons/spatial_audio.gd (Lesson 06), so every key of
## Lessons 01-06 still works. This script:
##   places the Rocks node on the ground at startup,
##   G  cycles the view of both slices (distance, gradient length, sign)
##   H  moves the horizontal slice up by 0.5 m (wrapping to the bottom)
## and adds HUD lines, among them the value of the boulder SDF at the
## player's feet.
##
## The SdfSlice nodes (src/sdf/sdf_slice.gd) do the sampling and drawing.
## The SDF itself is data/rocks/boulder_pile.tres.

const VIEW_NAMES: PackedStringArray = ["distance", "gradient length", "sign"]
## Heights of the horizontal cut, in meters above the Rocks node.
const SLICE_HEIGHTS: PackedFloat64Array = [0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25]

@onready var _rocks: Node3D = $Rocks
@onready var _slice_horizontal: SdfSlice = $Rocks/SliceHorizontal
@onready var _slice_vertical: SdfSlice = $Rocks/SliceVertical

var _height_index := 0


func _ready() -> void:
	super()
	# Q: Why place the rocks in code?
	# A: As with the spawn point (sandbox.gd), the ground height comes from
	#    the HeightField. Shape space has its floor at y = 0, so the node
	#    goes to the terrain height under its own x and z.
	_rocks.position.y = _terrain.height_at(_rocks.position.x, _rocks.position.z)
	_height_index = _nearest_height_index(_slice_horizontal.origin.y)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_slice_view"):
		var next_view := (_slice_horizontal.view + 1) % VIEW_NAMES.size()
		_slice_horizontal.view = next_view
		_slice_vertical.view = next_view
	elif event.is_action_pressed("step_slice"):
		_height_index = (_height_index + 1) % SLICE_HEIGHTS.size()
		var o := _slice_horizontal.origin
		o.y = SLICE_HEIGHTS[_height_index]
		_slice_horizontal.origin = o


func _update_hud() -> void:
	super()
	var shape := _slice_horizontal.shape
	if shape == null:
		return
	# Q: Which point does the SDF need?
	# A: A point in shape space, which is the Rocks node's local space.
	#    to_local() undoes the Rocks node's transform.
	var feet := _rocks.to_local(_player.global_position)
	_hud_label.text += "\n\nslice: %s   [G / A]   cut y = %.2f m   [H / R3]\nf at feet %+.2f m   L %.2f   |grad f| %.2f..%.2f   %d samples %.0f ms" % [
		VIEW_NAMES[_slice_horizontal.view],
		_slice_horizontal.origin.y,
		shape.evaluate(feet),
		shape.lipschitz_bound(),
		_slice_horizontal.smallest_gradient,
		_slice_horizontal.largest_gradient,
		_slice_horizontal.sample_count,
		_slice_horizontal.build_milliseconds,
	]


func _nearest_height_index(y: float) -> int:
	var best := 0
	for i in SLICE_HEIGHTS.size():
		if absf(SLICE_HEIGHTS[i] - y) < absf(SLICE_HEIGHTS[best] - y):
			best = i
	return best
