@tool
class_name StepRow
extends BoxCourse
## A row of single steps of increasing height, laid out along -z.
## Lesson 02 uses it to find the tallest step the capsule climbs without
## a dedicated step-up rule, and to watch floor snapping on the way down.
##
##   side view (-z to the right)
##
##                                   ___
##                       ___        |   |
##           ___        |   |       |   |
##   ___    |   |       |   |       |   |
##  ____|___|___|_______|___|_______|___|____ ground
##
## Each step is a box whose top lies step_heights[i] above this node's
## origin. Place the node where the ground is flat, or the height walked
## onto differs from the number on the label.

## Heights of the steps above this node's origin, in meters.
@export var step_heights := PackedFloat32Array([0.05, 0.09, 0.12, 0.25]):
	set(value):
		step_heights = value
		_queue_rebuild()
## Distance between the fronts of consecutive steps, in meters.
@export_range(2.0, 20.0, 0.5) var spacing: float = 4.0:
	set(value):
		spacing = value
		_queue_rebuild()
## Width (x) and depth (z) of each step, in meters.
@export var step_size := Vector2(3.0, 2.0):
	set(value):
		step_size = value
		_queue_rebuild()


func _build() -> void:
	for i in step_heights.size():
		var h := step_heights[i]
		var center := Vector3(0.0, (h - BURY_DEPTH) * 0.5, -i * spacing)
		_add_box(Vector3(step_size.x, h + BURY_DEPTH, step_size.y), Transform3D(Basis(), center))
		_add_label("%d cm" % roundi(h * 100.0), Vector3(0.0, h + 0.8, -i * spacing))
