class_name SdfGlsl
extends RefCounted
## Translates an SdfShape resource tree into GLSL (Lesson 10).
##
## How this file relates to the others:
##   src/sdf/*.gd                       the CPU library; every class has a
##                                      branch in _emit_node() below
##   shaders/sdf/sdf_library.gdshaderinc
##                                      the GLSL mirror of the formulas; the
##                                      generated code calls its functions
##   src/sdf/raymarch_volume.gd         RaymarchVolume calls translate() and
##                                      pastes the result into the template
##                                      shaders/sdf/raymarch.gdshader
##
## Usage:
##   var glsl := SdfGlsl.new()
##   var code := glsl.translate(shape)   # uniform declarations + sdf_map()
##   glsl.bake_noise_textures(0.1)       # one ImageTexture3D per noise
##   # then set glsl.noise_uniforms() on the ShaderMaterial
##
## The generated function has the form
##   float sdf_map(vec3 p0) {
##       float d1 = sdf_ellipsoid_scaled(p0, ...);
##       ...
##       return d7;
##   }
## Every node of the tree writes one or two lines and hands the name of its
## result to its parent. Point variables (p0, p1, ...) are written by nodes
## that move the point: SdfTransform and SdfRepeat.

## Marks the stub function in the template that translate() replaces.
const MAP_BEGIN := "// SDF_MAP_BEGIN"
const MAP_END := "// SDF_MAP_END"

## One entry per distinct FastNoiseLite resource met in the tree.
var noises: Array[FastNoiseLite] = []
## For each noise: the region, in the local frame of its SdfDisplace nodes,
## where the shader may ask for a value.
var noise_regions: Array[AABB] = []
## Filled by bake_noise_textures().
var noise_textures: Array[ImageTexture3D] = []
var noise_cells: PackedFloat32Array = []
var noise_dims: Array[Vector3i] = []
var bake_milliseconds := 0.0
## Classes met in the tree that have no GLSL translation. Empty on success.
var unsupported: PackedStringArray = []
## Number of nodes translated by the last translate().
var node_count := 0

var _lines: PackedStringArray = []
var _counter := 0


## Returns GLSL source: the noise uniforms followed by sdf_map().
func translate(shape: SdfShape) -> String:
	noises.clear()
	noise_regions.clear()
	unsupported.clear()
	node_count = 0
	_lines.clear()
	_counter = 0

	var result := _emit_node(shape, "p0")

	var code := ""
	for k in noises.size():
		code += "uniform sampler3D sdf_noise_%d : filter_linear, repeat_disable;\n" % k
		code += "uniform vec3 sdf_noise_%d_origin;\n" % k
		code += "uniform float sdf_noise_%d_cell;\n" % k
		code += "uniform vec3 sdf_noise_%d_dims;\n" % k
	code += "float sdf_map(vec3 p0) {\n"
	for line in _lines:
		code += "\t" + line + "\n"
	code += "\treturn %s;\n}\n" % result
	return code


## Replaces the stub between MAP_BEGIN and MAP_END in template_code.
static func splice(template_code: String, map_code: String) -> String:
	var begin := template_code.find(MAP_BEGIN)
	var end := template_code.find(MAP_END)
	if begin < 0 or end < begin:
		push_error("SdfGlsl: the template has no %s ... %s block" % [MAP_BEGIN, MAP_END])
		return template_code
	return template_code.substr(0, begin) + MAP_BEGIN + "\n" + map_code + template_code.substr(end)


## Samples each noise on a grid with the given spacing and stores it in a
## single-channel float 3D texture.
func bake_noise_textures(cell: float) -> void:
	var start := Time.get_ticks_usec()
	noise_textures.clear()
	noise_cells.clear()
	noise_dims.clear()
	for k in noises.size():
		var slices := bake_noise_slices(noises[k], noise_regions[k], cell)
		var dims := Vector3i(slices[0].get_width(), slices[0].get_height(), slices.size())
		var texture := ImageTexture3D.new()
		texture.create(Image.FORMAT_RF, dims.x, dims.y, dims.z, false, slices)
		noise_textures.append(texture)
		noise_cells.append(cell)
		noise_dims.append(dims)
	bake_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


## The noise on the grid region.position + (i, j, k) * cell, as one
## single-channel float Image per z layer (the layout ImageTexture3D takes).
static func bake_noise_slices(noise: FastNoiseLite, region: AABB, cell: float) -> Array[Image]:
	# Q: Why ceil(size / cell) + 1 texels per axis?
	# A: Texels sit on the grid points origin + i * cell, both ends
	#    included, like fence posts: n intervals need n + 1 posts.
	var dims := Vector3i(
		ceili(region.size.x / cell) + 1,
		ceili(region.size.y / cell) + 1,
		ceili(region.size.z / cell) + 1)
	var slices: Array[Image] = []
	for k in dims.z:
		var image := Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RF)
		for j in dims.y:
			for i in dims.x:
				var p := region.position + Vector3(i, j, k) * cell
				image.set_pixel(i, j, Color(noise.get_noise_3dv(p), 0, 0))
		slices.append(image)
	return slices


## Uniform name -> value for every baked noise. Set them on the material.
func noise_uniforms() -> Dictionary:
	var uniforms := {}
	for k in noise_textures.size():
		uniforms["sdf_noise_%d" % k] = noise_textures[k]
		uniforms["sdf_noise_%d_origin" % k] = noise_regions[k].position
		uniforms["sdf_noise_%d_cell" % k] = noise_cells[k]
		uniforms["sdf_noise_%d_dims" % k] = Vector3(noise_dims[k])
	return uniforms


## Writes the lines for one node and returns the name (or literal) of its
## distance. p is the name of the point variable in the node's frame.
func _emit_node(shape: SdfShape, p: String) -> String:
	if shape == null:
		return "SDF_FAR"
	node_count += 1

	if shape is SdfSphere:
		var s := shape as SdfSphere
		return _assign("sdf_sphere(%s, %s, %s)" % [p, _v(s.center), _f(s.radius)])

	if shape is SdfBox:
		var b := shape as SdfBox
		return _assign("sdf_box(%s, %s, %s, %s)" % [p, _v(b.center), _v(b.half_extents), _f(b.rounding)])

	if shape is SdfCapsule:
		var c := shape as SdfCapsule
		return _assign("sdf_capsule(%s, %s, %s, %s)" % [p, _v(c.a), _v(c.b), _f(c.radius)])

	if shape is SdfEllipsoid:
		var e := shape as SdfEllipsoid
		# The same matrix SdfEllipsoid stores in _to_local.
		var to_local := Basis.from_euler(e.rotation_degrees * (PI / 180.0)).inverse()
		var function := "sdf_ellipsoid_scaled"
		if e.estimate == SdfEllipsoid.Estimate.GRADIENT:
			function = "sdf_ellipsoid_gradient"
		return _assign("%s(%s, %s, %s, %s)" % [function, p, _v(e.center), _v(e.radii), _m(to_local)])

	if shape is SdfTorus:
		var t := shape as SdfTorus
		return _assign("sdf_torus(%s, %s, %s, %s)" % [p, _v(t.center), _f(t.major_radius), _f(t.minor_radius)])

	# Q: Why is SdfSmoothUnion tested before SdfUnion?
	# A: It is not a subclass of SdfUnion, but the order makes no
	#    difference either way; each class gets its own branch.
	if shape is SdfSmoothUnion:
		var su := shape as SdfSmoothUnion
		# Mirrors evaluate(): d = INF, then d = smin(d, child) for each
		# child, left to right. smin(INF, e) = e, so the first fold is
		# skipped and d starts at the first child.
		var d := ""
		for child in su.shapes:
			if child == null:
				continue
			var e := _emit_node(child, p)
			d = e if d == "" else _assign("sdf_smin(%s, %s, %s)" % [d, e, _f(su.blend)])
		return "SDF_FAR" if d == "" else d

	if shape is SdfUnion:
		var u := shape as SdfUnion
		var d := ""
		for child in u.shapes:
			if child == null:
				continue
			var e := _emit_node(child, p)
			d = e if d == "" else _assign("min(%s, %s)" % [d, e])
		return "SDF_FAR" if d == "" else d

	if shape is SdfIntersection:
		var n := shape as SdfIntersection
		var d := ""
		for child in n.shapes:
			if child == null:
				continue
			var e := _emit_node(child, p)
			d = e if d == "" else _assign("max(%s, %s)" % [d, e])
		return "-SDF_FAR" if d == "" else d

	if shape is SdfSubtraction:
		var sub := shape as SdfSubtraction
		if sub.base == null:
			return "SDF_FAR"
		var base := _emit_node(sub.base, p)
		if sub.cutter == null:
			return base
		var cut := _emit_node(sub.cutter, p)
		return _assign("max(%s, -%s)" % [base, cut])

	if shape is SdfTransform:
		var tr := shape as SdfTransform
		if tr.shape == null:
			return "SDF_FAR"
		# Q: Why rebuild the transform instead of reading _inverse?
		# A: The same two lines as SdfTransform._update_transform(), so the
		#    translation does not depend on a private variable.
		#    evaluate() is shape.evaluate(_inverse * p) * scale.
		var basis := Basis.from_euler(tr.rotation_degrees * (PI / 180.0)).scaled(Vector3.ONE * tr.scale)
		var inverse := Transform3D(basis, tr.translation).affine_inverse()
		var q := _new_point("%s * %s + %s" % [_m(inverse.basis), p, _v(inverse.origin)])
		var inner := _emit_node(tr.shape, q)
		return _assign("%s * %s" % [inner, _f(tr.scale)])

	if shape is SdfRepeat:
		var r := shape as SdfRepeat
		if r.shape == null:
			return "SDF_FAR"
		var q := _new_point(p)
		var axes := "xyz"
		for axis in 3:
			if r.period[axis] > 0.0:
				# Mirrors evaluate(): cell = clamp(round(p / period), -count, count).
				_lines.append("%s.%s = %s.%s - %s * clamp(round(%s.%s / %s), %s, %s);" % [
					q, axes[axis], p, axes[axis], _f(r.period[axis]),
					p, axes[axis], _f(r.period[axis]),
					_f(-r.count[axis]), _f(r.count[axis])])
		return _emit_node(r.shape, q)

	if shape is SdfDisplace:
		var dis := shape as SdfDisplace
		if dis.shape == null:
			return "SDF_FAR"
		var inner := _emit_node(dis.shape, p)
		if dis.noise == null or dis.amplitude == 0.0:
			return inner
		var k := _noise_index(dis.noise, dis.shape.level_bounds(0.0))
		return _assign("%s + %s * sdf_noise(sdf_noise_%d, %s, sdf_noise_%d_origin, sdf_noise_%d_cell, sdf_noise_%d_dims)" % [
			inner, _f(dis.amplitude), k, p, k, k, k])

	# A class without a branch: report it and treat it as empty space.
	var name: String = shape.get_script().get_global_name() if shape.get_script() != null else shape.get_class()
	unsupported.append(name)
	push_error("SdfGlsl: no GLSL translation for " + name)
	return "SDF_FAR"


## Returns the index of the noise, adding it on first use, and grows its
## region by the bounds of the displaced child (plus a margin).
func _noise_index(noise: FastNoiseLite, child_bounds: AABB) -> int:
	# Q: Why a 0.5 m margin?
	# A: The march evaluates f at points up to a few steps outside the
	#    child's bounds. There the sampler clamps to the edge texel; the
	#    margin keeps the clamped zone away from the surface.
	var region := child_bounds.grow(0.5)
	var k := noises.find(noise)
	if k < 0:
		noises.append(noise)
		noise_regions.append(region)
		return noises.size() - 1
	noise_regions[k] = noise_regions[k].merge(region)
	return k


func _assign(expression: String) -> String:
	_counter += 1
	var name := "d%d" % _counter
	_lines.append("float %s = %s;" % [name, expression])
	return name


func _new_point(expression: String) -> String:
	_counter += 1
	var name := "p%d" % _counter
	_lines.append("vec3 %s = %s;" % [name, expression])
	return name


## A float literal that GLSL accepts: always with a decimal point.
static func _f(x: float) -> String:
	var s := String.num(x, 7)
	if not ("." in s or "e" in s):
		s += ".0"
	return s


static func _v(v: Vector3) -> String:
	return "vec3(%s, %s, %s)" % [_f(v.x), _f(v.y), _f(v.z)]


## GLSL's mat3(a, b, c) takes columns; a Godot Basis stores columns x, y, z.
static func _m(b: Basis) -> String:
	return "mat3(%s, %s, %s)" % [_v(b.x), _v(b.y), _v(b.z)]
