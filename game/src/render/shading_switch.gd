class_name ShadingSwitch
extends Node
## Switches the terrain and the rocks between Godot's built-in light and
## the four models of shaders/lighting/custom_light.gdshaderinc
## (Lesson 17, F5 and F6).
##
## How this file relates to the others:
##   LitShader (src/render/lit_shader.gd)   makes the lit copy of each
##                                           target's original material
##   Terrain (Lesson 01), CurvatureMesher /  the targets; each has an
##   ClimbableRock (Lessons 09, 15)          exported `material` whose setter
##                                           only assigns the mesh's
##                                           material_override (no rebuild)
##   src/lessons/writing_light.gd            calls cycle_mode() and
##                                           cycle_term(), reads the names
##                                           for the HUD
##
## Q: Why swap whole materials instead of changing one uniform?
## A: A shader that defines light() always uses it; Godot's own lighting
##    code is not reachable from inside light(). The built-in mode is
##    therefore the original material (no light()), and the four custom
##    modes are one generated material with its light_model uniform set.

signal mode_changed(mode: Mode)

enum Mode {
	BUILT_IN,    ## the original material: Godot's own light code
	LAMBERT,     ## light_model 0
	WRAP,        ## light_model 1
	OREN_NAYAR,  ## light_model 2
	GGX,         ## light_model 3 (Lambert + GGX specular)
}

enum Term {
	ALL,       ## diffuse and specular
	DIFFUSE,   ## diffuse only
	SPECULAR,  ## specular only
}

const MODE_NAMES: Array[String] = ["built-in", "Lambert", "wrap", "Oren-Nayar", "GGX"]
const TERM_NAMES: Array[String] = ["diffuse + specular", "diffuse only", "specular only"]

## The light() to append (shaders/lighting/custom_light.gdshaderinc).
@export var light_include: ShaderInclude
## Nodes whose `material` property is switched. Each must have a
## ShaderMaterial there whose shader has no light() of its own.
@export var targets: Array[Node] = []
## The mode on entering the tree.
@export var start_mode: Mode = Mode.BUILT_IN

var mode: Mode = Mode.BUILT_IN
var term: Term = Term.ALL
## node -> its original material
var originals := {}
## original material -> generated lit material (rocks share one)
var lit_materials := {}


func _ready() -> void:
	for target in targets:
		if target == null or not "material" in target:
			push_error("ShadingSwitch: target without a material property")
			continue
		var original := target.get("material") as ShaderMaterial
		if original == null:
			continue
		originals[target] = original
		if not lit_materials.has(original):
			var lit := LitShader.material(original, light_include)
			if lit != null:
				lit_materials[original] = lit
	set_mode(start_mode)


## The material a target shows in a mode: its original for BUILT_IN,
## else the lit copy with light_model and light_term set.
func material_for(target: Node, which: Mode) -> ShaderMaterial:
	var original: ShaderMaterial = originals.get(target)
	if which == Mode.BUILT_IN or not lit_materials.has(original):
		return original
	var lit: ShaderMaterial = lit_materials[original]
	lit.set_shader_parameter("light_model", int(which) - 1)
	lit.set_shader_parameter("light_term", int(term))
	return lit


func set_mode(which: Mode) -> void:
	for target in originals:
		var shown := target.get("material") as ShaderMaterial
		var next := material_for(target, which)
		# Q: Why copy uniforms on every switch?
		# A: Keys of earlier lessons change uniforms of the material that
		#    is shown at the moment (Tab: debug_view, V: paint_view, C:
		#    contours, U: curvature_view). Copying them to the material
		#    shown next keeps those views across a switch.
		if shown != next:
			LitShader.copy_parameters(shown, next)
			target.set("material", next)
	mode = which
	mode_changed.emit(mode)


func cycle_mode() -> void:
	set_mode(((int(mode) + 1) % Mode.size()) as Mode)


## Diffuse and specular, diffuse only, specular only. Applies to the lit
## materials; the built-in mode has no such switch.
func cycle_term() -> void:
	term = ((int(term) + 1) % Term.size()) as Term
	for lit in lit_materials.values():
		(lit as ShaderMaterial).set_shader_parameter("light_term", int(term))
