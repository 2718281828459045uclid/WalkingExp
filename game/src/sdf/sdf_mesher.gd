@tool
class_name SdfMesher
extends Node3D
## Builds a triangle mesh and a collision shape from the zero set of an
## SdfShape (Lesson 08).
##
## How the files relate:
##   shape           an SdfShape Resource (data/rocks/*.tres). This node's
##                   local space is the shape's space, as for SdfSlice.
##   SdfGrid         samples shape.evaluate() on a grid inside bounds()
##   SurfaceNetsGpu  pass 1 (one vertex per cell) on the GPU, through
##                   compute_shader (shaders/compute/surface_nets.glsl)
##   SurfaceNets     pass 1 on the CPU when there is no GPU or use_gpu is
##                   off; pass 2 (the faces) always
##   material        the rock material (data/rocks/rock_material.tres)
##
## The MeshInstance3D and the StaticBody3D are internal children: they
## are rebuilt from the shape at load and never written into the .tscn.
##
## Q: Why does pass 2 stay on the CPU?
## A: Each sign-changing edge adds a quad, and the number of quads is not
##    known in advance. On the GPU every invocation would need a place to
##    write: a counter shared by all invocations (an atomic) or a second
##    pass that counts first. Exercise E5 builds it. Pass 1 has a fixed
##    output size, one row per cell, so it moves to the GPU unchanged.

@export var shape: SdfShape:
	set(value):
		if shape != null and shape.changed.is_connected(_queue_rebuild):
			shape.changed.disconnect(_queue_rebuild)
		shape = value
		if shape != null:
			shape.changed.connect(_queue_rebuild)
		_queue_rebuild()
@export var material: Material:
	set(value):
		material = value
		if _mesh_instance != null:
			_mesh_instance.material_override = material
## Edge length of a grid cell in meters. Halving it gives about four
## times the triangles and eight times the samples.
@export_range(0.03, 1.0, 0.01) var cell_size: float = 0.15:
	set(value):
		cell_size = value
		_queue_rebuild()
## The compiled surface_nets.glsl. Without it the CPU path runs.
@export var compute_shader: RDShaderFile:
	set(value):
		compute_shader = value
		_gpu = null
		_queue_rebuild()
## Run pass 1 on the GPU when a RenderingDevice exists.
@export var use_gpu := true:
	set(value):
		use_gpu = value
		_queue_rebuild()
## Build a collision shape from the triangles (skipped in the editor).
@export var build_collision := true:
	set(value):
		build_collision = value
		_queue_rebuild()

## Results of the last rebuild(), read by the HUD and the tests.
var grid: SdfGrid
var nets: SurfaceNets
var used_gpu := false
var sample_milliseconds := 0.0
var vertex_milliseconds := 0.0
var face_milliseconds := 0.0
var collision_milliseconds := 0.0
var total_milliseconds := 0.0

var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _gpu: SurfaceNetsGpu
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = material
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		_collision_shape = CollisionShape3D.new()
		body.add_child(_collision_shape)
		add_child(body, false, Node.INTERNAL_MODE_FRONT)
	rebuild()


## Is a GPU path ready? Creates the local RenderingDevice on first use.
func gpu_available() -> bool:
	if compute_shader == null:
		return false
	if _gpu == null:
		_gpu = SurfaceNetsGpu.new(compute_shader)
	return _gpu.is_available()


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	if shape == null:
		_mesh_instance.mesh = null
		return
	var started := Time.get_ticks_usec()
	grid = SdfGrid.sample(shape, cell_size)
	sample_milliseconds = grid.sample_milliseconds

	# Pass 1 on the GPU if possible; an empty table means "use the CPU".
	var table := PackedFloat32Array()
	used_gpu = use_gpu and gpu_available()
	var gpu_started := Time.get_ticks_usec()
	if used_gpu:
		table = _gpu.run(grid)
	var gpu_milliseconds := (Time.get_ticks_usec() - gpu_started) / 1000.0

	nets = SurfaceNets.new()
	nets.build(grid, table)
	# Q: Why not read nets.vertex_milliseconds in the GPU case?
	# A: build() times its own pass 1, which is skipped when a table is
	#    given; the GPU time was taken around _gpu.run() above.
	vertex_milliseconds = gpu_milliseconds if used_gpu else nets.vertex_milliseconds
	face_milliseconds = nets.face_milliseconds

	var mesh := ArrayMesh.new()
	if nets.triangle_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nets.mesh_arrays())
	_mesh_instance.mesh = mesh

	var collision_started := Time.get_ticks_usec()
	if _collision_shape != null:
		# Q: Which collision shape fits a mesh like this?
		# A: A ConcavePolygonShape3D ("trimesh"): the triangles themselves.
		#    It may only be static (a StaticBody3D), which a rock is. A
		#    convex shape would fill the cleft and the gap under the
		#    perched stone.
		var use_mesh := build_collision and nets.triangle_count() > 0
		_collision_shape.shape = mesh.create_trimesh_shape() if use_mesh else null
	collision_milliseconds = (Time.get_ticks_usec() - collision_started) / 1000.0
	total_milliseconds = (Time.get_ticks_usec() - started) / 1000.0


## Q: Why rebuild later instead of at once?
## A: As in SdfSlice: loading sets several exports in a row, and each
##    Inspector edit of the boulder emits `changed`. One rebuild at the
##    end of the frame serves them all. A rebuild of the boulder pile
##    takes about a second (O4), so this matters more here.
func _queue_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func vertex_count() -> int:
	return 0 if nets == null else nets.positions.size()


func triangle_count() -> int:
	return 0 if nets == null else nets.triangle_count()
