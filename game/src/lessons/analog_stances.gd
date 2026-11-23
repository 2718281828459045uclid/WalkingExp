extends "res://src/lessons/balance.gd"
## Root script of scenes/lessons/14_analog_stances.tscn.
##
## Extends src/lessons/balance.gd (Lesson 13), so every key of Lessons
## 01-13 still works. The scene adds the node Stance, a StanceController
## (src/body/stance_controller.gd) placed after BalanceMonitor. This
## script adds:
##   4  toggles the stance: standing, crouched (gamepad: D-pad up)
##   5  shifts the weight left while held (gamepad: left trigger)
##   6  shifts the weight right while held (gamepad: right trigger)
##   7  cycles the smoothing: none, one-pole, spring, spring (Euler)
##   8  swaps the walk stick's deadzone: radial (Lesson 02), axial
##   9  switches the physics tick rate: 60, 120 per second
## and appends five lines to HUD/RockLabel. The last line measures the
## height of the center of mass from the soles: Lesson 13's "above feet"
## is measured in the rig's frame, which the crouch lowers with the body.

const TICK_RATES: Array[int] = [60, 120]

## The walk stick response with an axial deadzone, for key 8.
@export var axial_stick_response: StickResponse

@onready var _stance: StanceController = $Stance

var _radial_stick_response: StickResponse


func _ready() -> void:
	super()
	_radial_stick_response = _player.stick_response


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if _stance == null:
		return
	if event.is_action_pressed("toggle_crouch"):
		_stance.toggle_stance()
	elif event.is_action_pressed("cycle_stance_smoothing"):
		_stance.cycle_smoothing()
	elif event.is_action_pressed("toggle_axial_deadzone"):
		var axial := _player.stick_response == axial_stick_response
		_player.stick_response = _radial_stick_response if axial else axial_stick_response
	elif event.is_action_pressed("cycle_stance_tick_rate"):
		var next := (TICK_RATES.find(Engine.physics_ticks_per_second) + 1) % TICK_RATES.size()
		Engine.physics_ticks_per_second = TICK_RATES[next]


func _update_hud() -> void:
	super()
	if _stance == null:
		return
	var deadzone := "axial" if _player.stick_response is AxialStickResponse else "radial"
	_rock_label.text += "\nstance: %s [4 / D-pad up]   %d Hz [9]\nsmoothing: %s [7]\ntriggers L %.2f -> %.2f   R %.2f -> %.2f   [5 / LT] [6 / RT]\nshift %+.3f %+.3f m   stick %s [8]\ncrouch %.3f m   CoM over soles %.3f m" % [
		StanceController.STANCE_NAMES[_stance.stance],
		Engine.physics_ticks_per_second,
		StanceController.SMOOTHING_NAMES[_stance.smoothing],
		_stance.trigger_raw.x,
		_stance.trigger_shaped.x,
		_stance.trigger_raw.y,
		_stance.trigger_shaped.y,
		_stance.shift.x,
		_stance.shift.y,
		deadzone,
		_stance.crouch,
		_balance.center_of_mass.y - _balance.polygon_height,
	]
