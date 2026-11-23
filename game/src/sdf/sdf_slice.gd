@tool
class_name SdfSlice
extends Node3D
## Draws one plane cut through an SdfShape (Lesson 07).
##
## How the files relate:
##   shape           an SdfShape Resource (src/sdf/), in this project a .tres from
##                   data/rocks/. This node's local space is the shape's
##                   space: a point p of this node is passed to
##                   shape.evaluate(p) unchanged.
##   slice_material  data/debug/sdf_slice_material.tres
##                   (shaders/sdf_slice.gdshader). Each SdfSlice draws with
##                   its own copy, because each has its own texture.
##   rebuild()       samples the shape on a grid in the plane, stores f and
##                   |grad f| in an Image (two float channels), and hands
##                   it to the copy of the material as the `field` uniform.
##
## The plane is perpendicular to `axis` and passes through `origin`.
## The quad and the texture are internal children: they are rebuilt at
## load and never written into the .tscn file.
##
## The script is @tool, so the slice also appears in the editor and
## redraws when the shape Resource or any child of it changes.

enum Axis { X, Y, Z }

@export var shape: SdfShape:
	set(value):
		if shape != null and shape.changed.is_connected(_queue_rebuild):
			shape.changed.disconnect(_queue_rebuild)
		shape = value
		if shape != null:
			shape.changed.connect(_queue_rebuild)
		_queue_rebuild()
@export var slice_material: ShaderMaterial:
	set(value):
		slice_material = value
		_queue_rebuild()
## The plane's normal: X gives a cut seen from the side along x, Y a
## horizontal cut, Z a cut seen from the front.
@export var axis: Axis = Axis.Y:
	set(value):
		axis = value
		_queue_rebuild()
## A point on the plane and the center of the drawn rectangle.
@export var origin: Vector3 = Vector3.ZERO:
	set(value):
		origin = value
		_queue_rebuild()
## Width and height of the drawn rectangle in meters.
@export var size: Vector2 = Vector2(10, 10):
	set(value):
		size = value
		_queue_rebuild()
## Samples along the width. The height gets the same spacing.
@export_range(8, 512) var resolution: int = 96:
	set(value):
		resolution = value
		_queue_rebuild()
## 0 distance, 1 gradient length, 2 sign (see shaders/sdf_slice.gdshader).
@export_range(0, 2) var view: int = 0:
	set(value):
		view = value
		if _material != null:
			_material.set_shader_parameter("view", view)

## Results of the last rebuild(), read by the HUD and the tests.
var image: Image
var sample_count := 0
var build_milliseconds := 0.0
var smallest_value := INF
var largest_gradient := 0.0
var smallest_gradient := INF

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	rebuild()


## The plane's in-plane directions u (texture right), v (texture up) and
## its normal n, in this node's space.
##
## Q: Why these particular vectors?
## A: A QuadMesh lies in its local xy plane, facing +z. The basis
##    (u, v, n) turns that plane onto the slice plane, and it must be
##    right-handed (u x v = n) or the quad is mirrored. Check each case:
##    for Y, (1,0,0) x (0,0,-1) = (0,1,0).
func plane_basis() -> Basis:
	match axis:
		Axis.X:
			return Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		Axis.Y:
			return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		_:
			return Basis.IDENTITY


## Grid size (columns, rows) for the current size and resolution.
func grid_size() -> Vector2i:
	var columns := maxi(resolution, 2)
	var rows := maxi(roundi(columns * size.y / size.x), 2)
	return Vector2i(columns, rows)


## The point of this node's space at texel (i, j). Texel (0, 0) is the
## top-left corner of the quad, as in the QuadMesh's UV layout.
func texel_point(i: int, j: int) -> Vector3:
	var grid := grid_size()
	var b := plane_basis()
	var a := ((i + 0.5) / grid.x - 0.5) * size.x
	var c := (0.5 - (j + 0.5) / grid.y) * size.y
	return origin + b.x * a + b.y * c


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	if shape == null or slice_material == null:
		_mesh_instance.mesh = null
		return
	var started := Time.get_ticks_usec()
	var grid := grid_size()
	var b := plane_basis()
	var spacing := size.x / grid.x

	# Three layers of samples: the plane itself and one spacing to each
	# side along the normal. The side layers give d f / d n.
	var middle := PackedFloat64Array()
	var below := PackedFloat64Array()
	var above := PackedFloat64Array()
	middle.resize(grid.x * grid.y)
	below.resize(grid.x * grid.y)
	above.resize(grid.x * grid.y)
	for j in grid.y:
		for i in grid.x:
			var p := texel_point(i, j)
			var k := j * grid.x + i
			middle[k] = shape.evaluate(p)
			below[k] = shape.evaluate(p - b.z * spacing)
			above[k] = shape.evaluate(p + b.z * spacing)
	sample_count = grid.x * grid.y * 3

	image = Image.create_empty(grid.x, grid.y, false, Image.FORMAT_RGF)
	smallest_value = INF
	largest_gradient = 0.0
	smallest_gradient = INF
	for j in grid.y:
		for i in grid.x:
			var k := j * grid.x + i
			# Q: How is the gradient found from the grid?
			# A: Central differences: (f(right) - f(left)) / (2 spacing),
			#    and the same up-down and across the plane. At the border
			#    one neighbor is missing, so the texel itself stands in for
			#    it and the step is one spacing (a one-sided difference).
			#    Rows grow downward while v points up, hence "up - down"
			#    uses j - 1 for up.
			var left: float = middle[k - 1] if i > 0 else middle[k]
			var right: float = middle[k + 1] if i < grid.x - 1 else middle[k]
			var up: float = middle[k - grid.x] if j > 0 else middle[k]
			var down: float = middle[k + grid.x] if j < grid.y - 1 else middle[k]
			var steps_u: int = (1 if i > 0 else 0) + (1 if i < grid.x - 1 else 0)
			var steps_v: int = (1 if j > 0 else 0) + (1 if j < grid.y - 1 else 0)
			var g := Vector3(
				(right - left) / (steps_u * spacing),
				(up - down) / (steps_v * spacing),
				(above[k] - below[k]) / (2.0 * spacing))
			var grad_length := g.length()
			image.set_pixel(i, j, Color(middle[k], grad_length, 0.0))
			smallest_value = minf(smallest_value, middle[k])
			largest_gradient = maxf(largest_gradient, grad_length)
			smallest_gradient = minf(smallest_gradient, grad_length)

	# Q: Why duplicate the material?
	# A: The .tres is shared by every slice. Setting `field` on the shared
	#    Resource would give all slices the texture of the last one built.
	if _material == null or _material.shader != slice_material.shader:
		_material = slice_material.duplicate() as ShaderMaterial
	_material.set_shader_parameter("field", ImageTexture.create_from_image(image))
	_material.set_shader_parameter("view", view)

	var quad := QuadMesh.new()
	quad.size = size
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = _material
	_mesh_instance.transform = Transform3D(b, origin)
	build_milliseconds = (Time.get_ticks_usec() - started) / 1000.0


# Q: Why rebuild later instead of at once?
# A: Loading a scene sets several exports in a row, and editing a
#    boulder in the Inspector emits `changed` many times per second.
#    call_deferred collects them into one rebuild at the end of the frame.
func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()
