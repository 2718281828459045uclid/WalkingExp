@tool
class_name RaymarchVolume
extends Node3D
## Draws an SdfShape by raymarching in a fragment shader (Lesson 10).
##
## How this file relates to the others:
##   shape      any SdfShape tree (Lessons 07 and 09); read, never changed
##   template   shaders/sdf/raymarch.gdshader; its stub sdf_map() is
##              replaced by the code SdfGlsl (src/sdf/sdf_glsl.gd) writes
##              for `shape`
##   an internal MeshInstance3D with a BoxMesh (the proxy) that covers
##   shape.bounds(); its ShaderMaterial runs the march
##
## The node's transform places the shape in the world, as the Rocks node
## does for the meshed pile. Use uniform scale only: the march measures
## distances in the local frame.
##
## Nothing here is collidable. A raymarched rock is seen, not walked on.

## The field to draw.
@export var shape: SdfShape:
	set(value):
		if shape != null and shape.changed.is_connected(_queue_rebuild):
			shape.changed.disconnect(_queue_rebuild)
		shape = value
		if shape != null:
			shape.changed.connect(_queue_rebuild)
		_queue_rebuild()
## The raymarching template (shaders/sdf/raymarch.gdshader).
@export var template: Shader:
	set(value):
		template = value
		_queue_rebuild()
## Spacing of the baked noise grid, in meters of the noise's own frame.
@export_range(0.02, 0.5, 0.01) var noise_cell: float = 0.1:
	set(value):
		noise_cell = value
		_queue_rebuild()
## The largest number of sphere-tracing steps per pixel.
@export_range(1, 512) var max_steps: int = 96:
	set(value):
		max_steps = value
		_set_uniform("max_steps", max_steps)
## Hit tolerance in pixels at the distance of the hit.
@export_range(0.05, 8.0, 0.05) var epsilon_pixels: float = 0.5:
	set(value):
		epsilon_pixels = value
		_set_uniform("epsilon_pixels", epsilon_pixels)
## 0 lit, 1 step count, 2 normals, 3 mean curvature.
@export_range(0, 3) var debug_view: int = 0:
	set(value):
		debug_view = value
		_set_uniform("debug_view", debug_view)

## The material of the proxy; created by rebuild().
var material: ShaderMaterial
## The generated sdf_map() and noise uniforms (for reading and for tests).
var generated_code := ""
## The Lipschitz bound of `shape`; the shader steps by f / lipschitz.
var lipschitz := 1.0
## The box the proxy covers, in the local frame.
var proxy_bounds := AABB()
## Time of the last rebuild() and of its noise baking, in milliseconds.
var build_milliseconds := 0.0
var bake_milliseconds := 0.0
## Number of nodes in the translated tree.
var node_count := 0

var _proxy: MeshInstance3D
var _rebuild_queued := false


func _ready() -> void:
	_proxy = MeshInstance3D.new()
	_proxy.name = "Proxy"
	# Q: Why no shadow from the proxy?
	# A: The shadow pass would draw the box, not the rock: a box-shaped
	#    shadow. Exercise E3 makes the shadow pass march as well.
	_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_proxy, false, Node.INTERNAL_MODE_FRONT)
	rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Translates the shape, bakes the noise, and builds the proxy and material.
func rebuild() -> void:
	_rebuild_queued = false
	if _proxy == null:
		return
	if shape == null or template == null:
		_proxy.mesh = null
		return
	var start := Time.get_ticks_usec()

	var glsl := SdfGlsl.new()
	generated_code = glsl.translate(shape)
	node_count = glsl.node_count
	glsl.bake_noise_textures(noise_cell)
	bake_milliseconds = glsl.bake_milliseconds

	var shader := Shader.new()
	shader.code = SdfGlsl.splice(template.code, generated_code)

	# Q: Why is an INF Lipschitz bound not used as it is?
	# A: SdfEllipsoid with the GRADIENT estimate reports INF (Lesson 07).
	#    1 / INF = 0 would freeze the march. A step of half the value is
	#    an unguarded guess, and the warning says so.
	lipschitz = shape.lipschitz_bound()
	if is_inf(lipschitz):
		push_warning("RaymarchVolume: the shape has no finite Lipschitz bound; stepping by f / 2")
		lipschitz = 2.0

	# Q: Why level_bounds(0) and a margin?
	# A: bounds() holds the zero set. The margin keeps the surface away from
	#    the box faces, where the march starts.
	proxy_bounds = shape.bounds().grow(0.05)
	_proxy.mesh = _box_mesh(proxy_bounds)

	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("proxy_min", proxy_bounds.position)
	material.set_shader_parameter("proxy_max", proxy_bounds.end)
	material.set_shader_parameter("step_scale", 1.0 / lipschitz)
	material.set_shader_parameter("max_steps", max_steps)
	material.set_shader_parameter("epsilon_pixels", epsilon_pixels)
	material.set_shader_parameter("debug_view", debug_view)
	var uniforms := glsl.noise_uniforms()
	for uniform_name: String in uniforms:
		material.set_shader_parameter(uniform_name, uniforms[uniform_name])
	_proxy.material_override = material

	build_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


## A box mesh covering `box`, with its vertices in the node's own frame.
##
## Q: Why not a BoxMesh on a MeshInstance3D moved to the box's center?
## A: The shader marches in the frame given by MODEL_MATRIX, the frame of
##    the MeshInstance3D. Moving it would shift that frame away from the
##    shape's frame, and sdf_map() would see every point offset. Moving the
##    vertices instead leaves MODEL_MATRIX equal to this node's transform.
static func _box_mesh(box: AABB) -> ArrayMesh:
	var cube := BoxMesh.new()
	cube.size = box.size
	var arrays := cube.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] += box.get_center()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_uniform(uniform_name: String, value: Variant) -> void:
	if material != null:
		material.set_shader_parameter(uniform_name, value)
