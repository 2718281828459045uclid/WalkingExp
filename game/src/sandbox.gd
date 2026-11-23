extends Node3D
## Root script of scenes/sandbox.tscn.
## Places the player on the ground at startup and handles debug keys.
## It reads from Terrain and Player but owns no game logic of its own.

const DEBUG_VIEW_NAMES: PackedStringArray = ["lit", "normals", "slope"]

@onready var _terrain: Terrain = $Terrain
@onready var _player: Player = $Player
@onready var _hud_label: Label = $HUD/Label

var _debug_view := 0


func _ready() -> void:
	# Q: Why compute the spawn height instead of typing a number into the scene?
	# A: The height depends on HeightField parameters. Asking the field keeps
	#    the spawn point correct after you change the terrain.
	var spawn := _player.global_position
	_player.global_position.y = _terrain.height_at(spawn.x, spawn.z) + 1.0
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_debug_view"):
		_debug_view = (_debug_view + 1) % DEBUG_VIEW_NAMES.size()
		var shader_material := _terrain.material as ShaderMaterial
		shader_material.set_shader_parameter("debug_view", _debug_view)
		_update_hud()
	elif event.is_action_pressed("cycle_normal_method"):
		var next_method: int = (_terrain.normal_method + 1) % Terrain.NormalMethod.size()
		_terrain.normal_method = next_method as Terrain.NormalMethod
		_update_hud()


func _update_hud() -> void:
	var method_name: String = Terrain.NormalMethod.keys()[_terrain.normal_method]
	_hud_label.text = "view: %s   [Tab / Select]\nnormals: %s   [N / Y]\nEsc releases mouse" % [
		DEBUG_VIEW_NAMES[_debug_view],
		method_name.to_lower(),
	]
