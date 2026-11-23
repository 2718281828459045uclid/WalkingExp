extends "res://src/sandbox.gd"
## Root script of scenes/lessons/03_painting_the_ground.tscn.
##
## Extends src/sandbox.gd, which spawns the player, cycles the terrain
## debug_view uniform (Tab) and the normal method (N), and writes the HUD.
## This script adds keys that change the look of the scene while it runs:
##   V  cycles the paint_view uniform of shaders/terrain_painted.gdshader
##   C  toggles the contour lines (show_contours uniform)
##   M  cycles the Environment's tonemapper
##   F  toggles the Environment's fog
## It also places the ColorStrip (shaders/color_ramp.gdshader) above the
## ground and the RampTower (src/world/ramp_tower.gd, Lesson 02) on it.
## The shader reads the uniforms; this script only writes them.
##
## Q: The material is shared through a .tres file. Do these keys change the file?
## A: No. They change the copy loaded in memory. Nothing is saved, so the
##    .tres file keeps its values when the game stops. Every scene using
##    the same file in the same run sees the change.

const PAINT_VIEW_NAMES: PackedStringArray = ["painted", "triplanar weights", "noise, triplanar", "noise, top-down only"]

# Q: Why list the tonemappers by hand instead of looping 0..4?
# A: The enum values are not guaranteed to stay in this order across Godot
#    versions. Naming them makes the cycle order and the HUD text explicit.
const TONEMAPPERS: Array[Environment.ToneMapper] = [
	Environment.TONE_MAPPER_LINEAR,
	Environment.TONE_MAPPER_REINHARDT,
	Environment.TONE_MAPPER_FILMIC,
	Environment.TONE_MAPPER_ACES,
	Environment.TONE_MAPPER_AGX,
]
const TONEMAPPER_NAMES: PackedStringArray = ["linear", "reinhard", "filmic", "aces", "agx"]

## A RampTower painted with the terrain's material. Its ramps are planes
## steeper than any slope of the terrain, where the triplanar projection
## shows its effect (Lesson 03 O3). May be left empty.
@export var ramp_tower: RampTower

@onready var _environment: Environment = $WorldEnvironment.environment

var _paint_view := 0


func _ready() -> void:
	super()
	# The strip's center hangs 1.5 m above the ground below it, so its
	# lower edge (the quad is 1.5 m tall) clears the ground by 0.75 m.
	var strip: Node3D = $ColorStrip
	strip.position.y = _terrain.height_at(strip.position.x, strip.position.z) + 1.5

	# Q: Why is the tower an exported property, when the strip is found with $ColorStrip?
	# A: A scene whose root script extends this one may have no tower.
	#    An empty property skips the placement; $RampTower would fail
	#    with a missing node.
	if ramp_tower:
		ramp_tower.position.y = _terrain.height_at(ramp_tower.position.x, ramp_tower.position.z)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	var shader_material := _terrain.material as ShaderMaterial
	if event.is_action_pressed("cycle_paint_view"):
		_paint_view = (_paint_view + 1) % PAINT_VIEW_NAMES.size()
		shader_material.set_shader_parameter("paint_view", _paint_view)
	elif event.is_action_pressed("toggle_contours"):
		var shown: bool = shader_material.get_shader_parameter("show_contours")
		shader_material.set_shader_parameter("show_contours", not shown)
	elif event.is_action_pressed("cycle_tonemapper"):
		var i := TONEMAPPERS.find(_environment.tonemap_mode)
		_environment.tonemap_mode = TONEMAPPERS[(i + 1) % TONEMAPPERS.size()]
	elif event.is_action_pressed("toggle_fog"):
		_environment.fog_enabled = not _environment.fog_enabled


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	super()
	var shader_material := _terrain.material as ShaderMaterial
	var interval: float = shader_material.get_shader_parameter("contour_interval")
	var shown: bool = shader_material.get_shader_parameter("show_contours")
	var feet_height := _player.global_position.y
	var tonemapper_name := TONEMAPPER_NAMES[TONEMAPPERS.find(_environment.tonemap_mode)]
	_hud_label.text += "\n\npaint: %s   [V / D-pad left]\ncontours: %s, every %.1f m   [C / D-pad right]\nheight: %.2f m, contour %d\ntonemap: %s   [M / LB]\nfog: %s   [F / RB]" % [
		PAINT_VIEW_NAMES[_paint_view],
		"on" if shown else "off",
		interval,
		feet_height,
		PaintMath.contour_index(feet_height, interval),
		tonemapper_name,
		"on" if _environment.fog_enabled else "off",
	]
