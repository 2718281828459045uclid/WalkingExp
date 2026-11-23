class_name LitShader
extends RefCounted
## Makes a copy of a spatial shader with a light() function appended
## (Lesson 17).
##
## How this file relates to the others:
##   shaders/lighting/custom_light.gdshaderinc  the light() that is appended;
##                                              arrives here as a
##                                              ShaderInclude resource
##   ShadingSwitch, ShadingGallery              call material() for the
##                                              terrain's and the rocks'
##                                              materials
##
## Q: Why generate a shader instead of writing a lit copy by hand?
## A: light() is independent of fragment(): fragment() decides what the
##    surface is (color, roughness, normal), light() decides how one light
##    reflects from it. Appending light() to the unchanged code of
##    Lesson 03's and Lesson 09's shaders gives a shader whose fragment()
##    is the original, line for line. Any difference on screen between the
##    original material and the generated one comes from light() alone.
##    A hand-made copy could drift from its original; this one cannot.
##    Lesson 10's SdfGlsl.splice() builds shaders from text the same way.

## Generated shaders, one per (base shader, include) pair, so that every
## material made from the same base shares one shader and one compilation.
static var _cache := {}


## Q: How is the include named in the generated code?
## A: By the resource path of the ShaderInclude given to this function,
##    which a scene assigns through an exported property. The shader
##    preprocessor resolves "#include" when the new code is compiled.
static func make(base: Shader, light_include: ShaderInclude) -> Shader:
	if base == null or light_include == null:
		return null
	var key := "%d|%s" % [base.get_instance_id(), light_include.resource_path]
	if _cache.has(key):
		return _cache[key]
	if has_light_function(base.code):
		push_error("LitShader: %s already defines light()" % base.resource_path)
		return null
	var shader := Shader.new()
	shader.code = base.code + "\n\n// Appended by LitShader.make() (Lesson 17).\n#include \"%s\"\n" % light_include.resource_path
	_cache[key] = shader
	return shader


## A copy of base whose shader has the light() of light_include, with
## every uniform value of base copied over.
static func material(base: ShaderMaterial, light_include: ShaderInclude) -> ShaderMaterial:
	var shader := make(base.shader, light_include)
	if shader == null:
		return null
	var lit := ShaderMaterial.new()
	lit.shader = shader
	lit.render_priority = base.render_priority
	copy_parameters(base, lit)
	return lit


## Copies the value of every uniform of from's shader that to's shader
## also declares. Returns the number copied.
##
## Q: Why copy by name?
## A: The generated shader declares the base shader's uniforms plus the
##    light_* uniforms of the include. Copying by name moves the base
##    uniforms in either direction (base to lit, lit to base) and skips
##    the ones the other side does not have.
static func copy_parameters(from: ShaderMaterial, to: ShaderMaterial) -> int:
	if from == null or to == null or from.shader == null or to.shader == null:
		return 0
	var accepted := {}
	for uniform in to.shader.get_shader_uniform_list():
		accepted[uniform["name"]] = true
	var copied := 0
	for uniform in from.shader.get_shader_uniform_list():
		var uniform_name: String = uniform["name"]
		if accepted.has(uniform_name):
			to.set_shader_parameter(uniform_name, from.get_shader_parameter(uniform_name))
			copied += 1
	return copied


## Does the code define a light() function? A regular expression for
## "void light(" with any spacing.
static func has_light_function(code: String) -> bool:
	var pattern := RegEx.create_from_string("\\bvoid\\s+light\\s*\\(")
	return pattern.search(code) != null
