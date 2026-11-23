@tool
class_name Terrain
extends Node3D
## Turns a HeightField (math) into a triangle mesh (rendering) and a
## collision shape (physics).
##
## Relationships:
##   HeightField (.tres in game/data/terrain/) -> supplies height and gradient
##   Terrain (this script)                     -> samples the field on a grid
##   ShaderMaterial (terrain.gdshader)         -> colors the mesh
##
## The @tool line makes this script run inside the editor, so changes in
## the Inspector rebuild the mesh while you watch.
##
## Q: Why are the MeshInstance3D and StaticBody3D created in code instead
##    of placed in the scene file?
## A: A generated mesh holds tens of thousands of numbers. If it were a
##    normal child node, Godot would write all of them into sandbox.tscn on
##    every save, and Git would show huge diffs. "Internal" children are
##    never saved; the mesh is rebuilt from the HeightField each time the
##    scene loads.

enum NormalMethod {
	ANALYTIC,           ## From HeightField.gradient(): exact for the smooth surface.
	FINITE_DIFFERENCE,  ## From height() samples: approximate, depends on the step size.
	FACE_AVERAGED,      ## From the triangles alone: Godot's SurfaceTool.generate_normals().
}

@export var field: HeightField:
	set(value):
		if field and field.changed.is_connected(_queue_rebuild):
			field.changed.disconnect(_queue_rebuild)
		field = value
		if field:
			field.changed.connect(_queue_rebuild)
		_queue_rebuild()

@export var material: Material:
	set(value):
		material = value
		if _mesh_instance:
			_mesh_instance.material_override = material

## Width and depth of the square terrain, in meters.
@export_range(8.0, 1024.0) var size_meters: float = 128.0:
	set(value):
		size_meters = value
		_queue_rebuild()

## Grid vertices along one side. Spacing = size_meters / (vertices_per_side - 1).
@export_range(3, 513) var vertices_per_side: int = 129:
	set(value):
		vertices_per_side = value
		_queue_rebuild()

@export var normal_method: NormalMethod = NormalMethod.ANALYTIC:
	set(value):
		normal_method = value
		_queue_rebuild()

## Step size (meters) for the FINITE_DIFFERENCE method.
@export_range(0.00001, 4.0, 0.00001) var finite_difference_step: float = 0.05:
	set(value):
		finite_difference_step = value
		_queue_rebuild()

var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)

	# Q: Why skip collision in the editor?
	# A: Nothing walks on the terrain in the editor, and building the
	#    collision shape costs time on every Inspector change.
	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		_collision_shape = CollisionShape3D.new()
		body.add_child(_collision_shape)
		add_child(body, false, Node.INTERNAL_MODE_FRONT)

	rebuild()


## Q: Why "queue" a rebuild instead of rebuilding inside each setter?
## A: Loading a scene or dragging a slider can set several properties in
##    one frame. Deferring the call collapses them into a single rebuild
##    at the end of the frame.
func _queue_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if field == null:
		return

	var arrays := _build_arrays()
	var mesh: ArrayMesh

	if normal_method == NormalMethod.FACE_AVERAGED:
		# Discard our normals and let SurfaceTool derive them from the triangles.
		arrays[Mesh.ARRAY_NORMAL] = null
		var surface_tool := SurfaceTool.new()
		surface_tool.create_from_arrays(arrays)
		surface_tool.generate_normals()
		mesh = surface_tool.commit()
	else:
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = material

	if _collision_shape:
		_collision_shape.shape = mesh.create_trimesh_shape()


## World-space height at (x, z), accounting for this node's position.
func height_at(world_x: float, world_z: float) -> float:
	var local := Vector2(world_x - global_position.x, world_z - global_position.z)
	return field.height(local) + global_position.y


func _build_arrays() -> Array:
	var n := vertices_per_side
	var spacing := size_meters / float(n - 1)
	var half := size_meters * 0.5

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)

	# Vertices: a square grid centered on the origin.
	# "row" walks along z, "col" walks along x.
	# The vertex at (row, col) is stored at index row * n + col.
	for row in n:
		for col in n:
			var p := Vector2(-half + col * spacing, -half + row * spacing)
			var i := row * n + col
			positions[i] = Vector3(p.x, field.height(p), p.y)
			normals[i] = _normal_at(p)
			uvs[i] = Vector2(col, row) / float(n - 1)

	# Indices: two triangles per grid square.
	#
	#   i00 ---- i10      +x -->
	#    |  \     |
	#    |    \   |       +z
	#    |      \ |        |
	#   i01 ---- i11       v
	#
	# Q: Why i00 -> i10 -> i11 and not i00 -> i11 -> i10?
	# A: Godot draws a triangle's front side when its vertices appear in
	#    clockwise order from the camera, and hides the back side.
	#    Seen from above, +x points right and +z points down the screen
	#    (draw the axes to confirm), so i00 -> i10 -> i11 runs clockwise.
	#    Reverse the order and the terrain is visible only from below.
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for row in n - 1:
		for col in n - 1:
			var i00 := row * n + col
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			indices[k + 0] = i00
			indices[k + 1] = i10
			indices[k + 2] = i11
			indices[k + 3] = i00
			indices[k + 4] = i11
			indices[k + 5] = i01
			k += 6

	# Mesh.ARRAY_MAX is the number of slots Godot expects; unused slots stay null.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _normal_at(p: Vector2) -> Vector3:
	match normal_method:
		NormalMethod.FINITE_DIFFERENCE:
			# Central differences: slope of the secant line through p - e and p + e.
			# Q: What happens as e shrinks toward zero? As it grows large?
			# A: Lesson 01 asks you to find out by experiment, then explain why.
			var e := finite_difference_step
			var dh_dx := (field.height(p + Vector2(e, 0)) - field.height(p - Vector2(e, 0))) / (2.0 * e)
			var dh_dz := (field.height(p + Vector2(0, e)) - field.height(p - Vector2(0, e))) / (2.0 * e)
			return Vector3(-dh_dx, 1.0, -dh_dz).normalized()
		_:
			# ANALYTIC (FACE_AVERAGED replaces these later in rebuild()).
			return field.normal(p)
