@tool
class_name BoxCourse
extends Node3D
## Base class for test geometry built from boxes: ramps, steps, platforms.
##
## Relationships:
##   RampTower (ramp_tower.gd) and StepRow (step_row.gd) extend this class
##   and override _build(), which calls _add_box() and _add_label().
##   This class owns the bookkeeping: internal children, rebuilds,
##   collision in the running game only. It follows the pattern of
##   src/terrain/terrain.gd (Lesson 01).
##
## Q: Why build the boxes in code instead of placing them in the scene?
## A: Their sizes follow from a few numbers (an angle, a height). Code
##    computes the sizes and transforms from those numbers, and the scene
##    stores only the numbers. Internal children are never saved, so the
##    .tscn file stays short.

## How far each box extends below the node's origin, in meters, so that
## uneven ground does not expose its lower edge.
const BURY_DEPTH := 1.0

@export var material: Material:
	set(value):
		material = value
		_queue_rebuild()

var _rebuild_queued := false
var _generated: Array[Node] = []


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	for node in _generated:
		remove_child(node)
		node.queue_free()
	_generated.clear()
	_build()


## Subclasses override this and add their boxes.
func _build() -> void:
	pass


## Adds one box with a visible mesh and, in the running game, a collider.
## xf places the box center and orientation relative to this node.
func _add_box(size: Vector3, xf: Transform3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	mesh_instance.transform = xf
	_add_internal(mesh_instance)

	# Q: Why skip collision in the editor?
	# A: Same answer as in terrain.gd: nothing walks on it there.
	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		body.transform = xf
		_add_internal(body)


## Adds a text label that always faces the camera.
func _add_label(text: String, local_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.outline_size = 12
	# 64 px at 0.01 m per pixel: letters about 0.6 m tall.
	label.pixel_size = 0.01
	label.position = local_position
	_add_internal(label)


func _add_internal(node: Node) -> void:
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
	_generated.append(node)
