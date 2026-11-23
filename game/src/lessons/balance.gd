extends "res://src/lessons/feet_on_the_ground.gd"
## Root script of scenes/lessons/13_balance.tscn.
##
## Extends src/lessons/feet_on_the_ground.gd (Lesson 12), so every key of
## Lessons 01-12 still works. The scene adds the node BalanceMonitor, a
## BalanceMonitor (src/body/balance_monitor.gd) that reads the FootRig of
## Player/BodyMesh/Rig. This script adds:
##   1  toggles the balance lines (support polygon, center of mass)
##   2  pushes the body to its right
##   3  pushes the body forward
## and appends two lines to HUD/RockLabel.
## Shift with 2 or 3 pushes the other way.

@onready var _balance: BalanceMonitor = $BalanceMonitor


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if _balance == null:
		return
	# Q: Why read Shift from the event and not from a second action?
	# A: Every letter key is bound (Lesson 12). A modifier on the same key
	#    gives the opposite push without using up two more keys.
	var sign_of_push := -1.0 if event is InputEventWithModifiers and (event as InputEventWithModifiers).shift_pressed else 1.0
	if event.is_action_pressed("toggle_balance_debug"):
		_balance.debug_draw = not _balance.debug_draw
	elif event.is_action_pressed("push_body_side"):
		_balance.push(Vector2(sign_of_push, 0.0))
	elif event.is_action_pressed("push_body_forward"):
		_balance.push(Vector2(0.0, sign_of_push))


func _update_hud() -> void:
	super()
	if _balance == null:
		return
	var margin_text := "%+.3f m" % _balance.margin if is_finite(_balance.margin) else "none"
	var s := _balance.sway()
	_rock_label.text += "\nbalance: %s   margin %s   [1] [2] [3]\nCoM %.3f m above feet   sway %+.3f %+.3f m" % [
		BalanceMonitor.STATE_NAMES[_balance.state],
		margin_text,
		_balance.center_height,
		s.x,
		s.y,
	]
