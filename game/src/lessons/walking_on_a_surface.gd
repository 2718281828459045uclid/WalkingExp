extends "res://src/sandbox.gd"
## Root script of scenes/lessons/02_walking_on_a_surface.tscn.
##
## Extends src/sandbox.gd, which spawns the player on the ground, cycles
## the terrain debug view (Tab) and normal method (N), and writes the HUD.
## This script adds:
##   - placement of the test courses (RampTower, StepRow) on the ground
##   - T cycles the physics tick rate (30, 60, 144 Hz)
##   - B switches the player's blend rule (exponential, linear)
##   - HUD lines for ground state, speed, and stick shaping
## It reads from Player and Engine; the walking itself lives in player.gd.

const TICK_RATES: PackedInt32Array = [30, 60, 144]

@onready var _courses: Array[Node3D] = [$RampTower, $StepRow]


func _ready() -> void:
	super()
	# Q: Why set the course heights here and not in the scene file?
	# A: The same reason as the spawn height in sandbox.gd: the ground
	#    height follows the HeightField, which may be edited.
	for course in _courses:
		course.position.y = _terrain.height_at(course.position.x, course.position.z)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_tick_rate"):
		var i := TICK_RATES.find(Engine.physics_ticks_per_second)
		Engine.physics_ticks_per_second = TICK_RATES[(i + 1) % TICK_RATES.size()]
	elif event.is_action_pressed("toggle_blend_rule"):
		if _player.blend_rule == Player.BlendRule.EXPONENTIAL:
			_player.blend_rule = Player.BlendRule.LINEAR
		else:
			_player.blend_rule = Player.BlendRule.EXPONENTIAL


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	super()
	var ground_name: String = Player.GroundState.keys()[_player.get_ground_state()]
	var blend_name: String = Player.BlendRule.keys()[_player.blend_rule]
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z)
	# Q: Why three decimals for the stick and two for the speed?
	# A: A power-law response leaves zero with zero slope. Near the
	#    deadzone edge the shaped value stays below 0.005 for a few
	#    hundredths of raw travel, so two decimals would hide where it starts.
	_hud_label.text += "\n\nground: %s\nspeed: %.2f m/s (horizontal %.2f)\nstick: %.3f -> %.3f\nticks: %d Hz   [T / D-pad up]\nblend: %s   [B / D-pad down]" % [
		ground_name.to_lower(),
		_player.velocity.length(),
		horizontal.length(),
		_player.stick_raw.length(),
		_player.stick_shaped.length(),
		Engine.physics_ticks_per_second,
		blend_name.to_lower(),
	]
