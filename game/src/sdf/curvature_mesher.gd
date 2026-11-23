@tool
class_name CurvatureMesher
extends SdfMesher
## SdfMesher (Lesson 08) plus normals and curvature from the field
## (Lesson 09).
##
## How the files relate:
##   SdfMesher           builds grid, cell table, faces, collision (unchanged)
##   ImplicitCurvature   gradient, Hessian, H and K at each mesh vertex
##   this file           replaces the mesh with one that carries
##                         NORMAL   trilinear (Lesson 08) or field gradient
##                         CUSTOM0  (H, K, k1, k2) per vertex, 32-bit floats
##   shaders/rock_weathering.gdshader  reads CUSTOM0 and colors the rock
##
## The collision shape of SdfMesher is not touched: curvature changes
## the drawing, not the ground.

enum NormalSource { TRILINEAR, GRADIENT }

## Which normal the mesh carries. Changing it re-assembles the mesh from
## stored arrays; it does not resample the field.
@export var normal_source: NormalSource = NormalSource.GRADIENT:
	set(value):
		normal_source = value
		if is_node_ready() and not mean_curvatures.is_empty():
			_assemble_mesh()
## Step h of the differences in meters (ImplicitCurvature.DEFAULT_STEP).
@export_range(0.001, 0.1, 0.001) var curvature_step: float = ImplicitCurvature.DEFAULT_STEP:
	set(value):
		curvature_step = value
		_queue_rebuild()

## Per-vertex results of the last rebuild, in the order of nets.positions.
## curvature_milliseconds is not part of SdfMesher.total_milliseconds,
## which is measured before the curvature pass starts.
var gradient_normals := PackedVector3Array()
var mean_curvatures := PackedFloat32Array()
var gaussian_curvatures := PackedFloat32Array()
var curvature_milliseconds := 0.0


func rebuild() -> void:
	super()
	gradient_normals.clear()
	mean_curvatures.clear()
	gaussian_curvatures.clear()
	curvature_milliseconds = 0.0
	if nets == null or nets.triangle_count() == 0:
		return
	var started := Time.get_ticks_usec()
	var count := nets.positions.size()
	gradient_normals.resize(count)
	mean_curvatures.resize(count)
	gaussian_curvatures.resize(count)
	for i in count:
		var s := ImplicitCurvature.sample(shape, nets.positions[i], curvature_step)
		gradient_normals[i] = s.normal
		mean_curvatures[i] = s.mean
		gaussian_curvatures[i] = s.gaussian
	curvature_milliseconds = (Time.get_ticks_usec() - started) / 1000.0
	_assemble_mesh()


## Q: Why build a second ArrayMesh instead of editing the first one?
## A: An ArrayMesh surface fixes its vertex format when it is created.
##    CUSTOM0 is not part of the format SdfMesher chose, so the surface
##    is created again with the extra channel and the chosen normals.
func _assemble_mesh() -> void:
	var count := nets.positions.size()
	var custom := PackedFloat32Array()
	custom.resize(count * 4)
	for i in count:
		var k := ImplicitCurvature.principal_curvatures(mean_curvatures[i], gaussian_curvatures[i])
		custom[4 * i] = mean_curvatures[i]
		custom[4 * i + 1] = gaussian_curvatures[i]
		custom[4 * i + 2] = k.x
		custom[4 * i + 3] = k.y

	var arrays := nets.mesh_arrays()
	if normal_source == NormalSource.GRADIENT:
		arrays[Mesh.ARRAY_NORMAL] = gradient_normals
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	# Q: What does the format flag say?
	# A: CUSTOM0 can hold bytes, half floats or floats. The flag, shifted
	#    into the CUSTOM0 bits of the format, picks four 32-bit floats.
	#    Curvature values range over several orders of magnitude, so
	#    8-bit bytes would lose them.
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	# _mesh_instance belongs to SdfMesher. GDScript has no private
	# members; the leading underscore is a convention this subclass
	# breaks on purpose, in one place.
	_mesh_instance.mesh = mesh


## Mean angle and largest angle in degrees between the trilinear normals
## (Lesson 08) and the gradient normals. Vector2(mean, max).
func normal_angle_stats() -> Vector2:
	var total := 0.0
	var largest := 0.0
	for i in gradient_normals.size():
		var angle := rad_to_deg(nets.normals[i].angle_to(gradient_normals[i]))
		total += angle
		largest = maxf(largest, angle)
	if gradient_normals.is_empty():
		return Vector2.ZERO
	return Vector2(total / gradient_normals.size(), largest)
