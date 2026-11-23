class_name SurfaceNetsGpu
extends RefCounted
## Runs pass 1 of surface nets (the cell table) on the GPU (Lesson 08).
##
## How the files relate:
##   shader_file  an RDShaderFile: shaders/compute/surface_nets.glsl after
##                Godot's importer compiled it to SPIR-V. SdfMesher holds it
##                as an exported property, so no path appears in code.
##   SdfGrid      supplies the values to upload.
##   SurfaceNets  reads the table this class returns, exactly as it reads
##                its own CPU table.
##
## Q: What is a RenderingDevice?
## A: Godot's thin layer over Vulkan, Metal or Direct3D 12. It hands out
##    "RIDs" (resource IDs) for buffers, shaders and pipelines, and every
##    RID must be freed by hand. A "local" device is a second device next
##    to the one that draws the game, so compute work does not wait for
##    the frame and the frame does not wait for compute work.
##
## Headless runs have no RenderingDevice: create_local_rendering_device()
## returns null there, and is_available() reports false. SdfMesher then
## uses the CPU path (the fallback).

## Workgroup size along each axis; must match local_size in the shader.
const GROUP := 4

## Timings of the last run(), in milliseconds.
var upload_milliseconds := 0.0
var dispatch_milliseconds := 0.0
var download_milliseconds := 0.0

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()


func _init(shader_file: RDShaderFile) -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null or shader_file == null:
		return
	var spirv := shader_file.get_spirv()
	# Q: Why check the compile error here, after import?
	# A: The importer stores the compiler's message instead of failing.
	#    A shader with an error has no bytecode, and creating a pipeline
	#    from it would fail later with a less helpful message.
	if spirv.compile_error_compute != "":
		push_error("surface_nets.glsl: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)


func is_available() -> bool:
	return _rd != null and _pipeline.is_valid()


## The cell table for `grid`, or an empty array if there is no GPU.
func run(grid: SdfGrid) -> PackedFloat32Array:
	if not is_available():
		return PackedFloat32Array()
	var started := Time.get_ticks_usec()
	var cells := grid.dims - Vector3i.ONE
	var table_bytes := grid.cell_count() * SurfaceNets.CELL_FLOATS * 4

	# Two storage buffers: the values (filled now) and the table (empty).
	var values_bytes := grid.values.to_byte_array()
	var values_buffer := _rd.storage_buffer_create(values_bytes.size(), values_bytes)
	var table_buffer := _rd.storage_buffer_create(table_bytes)

	# Q: What is a uniform set?
	# A: The list that connects buffers to the shader's "binding" numbers.
	#    Set 0 binding 0 is the values, binding 1 the table, as declared
	#    in the shader.
	var values_uniform := RDUniform.new()
	values_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	values_uniform.binding = 0
	values_uniform.add_id(values_buffer)
	var table_uniform := RDUniform.new()
	table_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	table_uniform.binding = 1
	table_uniform.add_id(table_buffer)
	var uniform_set := _rd.uniform_set_create([values_uniform, table_uniform], _shader, 0)

	# The push constant: ivec4 dims, vec4 (origin, cell size). 32 bytes,
	# written field by field in the shader's order.
	var params := PackedByteArray()
	params.resize(32)
	params.encode_s32(0, grid.dims.x)
	params.encode_s32(4, grid.dims.y)
	params.encode_s32(8, grid.dims.z)
	params.encode_s32(12, 0)
	params.encode_float(16, grid.origin.x)
	params.encode_float(20, grid.origin.y)
	params.encode_float(24, grid.origin.z)
	params.encode_float(28, grid.cell_size)
	upload_milliseconds = (Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, params, params.size())
	# Q: How many workgroups?
	# A: Enough to cover every cell: ceil(cells / GROUP) on each axis.
	#    The shader discards the invocations past the last cell.
	_rd.compute_list_dispatch(list,
		ceili(cells.x / float(GROUP)), ceili(cells.y / float(GROUP)), ceili(cells.z / float(GROUP)))
	_rd.compute_list_end()
	# submit() starts the work; sync() waits for it to finish. Only a
	# local device may be synced by hand.
	_rd.submit()
	_rd.sync()
	dispatch_milliseconds = (Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	var table := _rd.buffer_get_data(table_buffer).to_float32_array()
	_rd.free_rid(uniform_set)
	_rd.free_rid(values_buffer)
	_rd.free_rid(table_buffer)
	download_milliseconds = (Time.get_ticks_usec() - started) / 1000.0
	return table


## Frees the device. RefCounted objects get NOTIFICATION_PREDELETE just
## before they are destroyed.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	_rd.free()
