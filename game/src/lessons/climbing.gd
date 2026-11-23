extends "res://src/lessons/analog_stances.gd"
## Root script of scenes/lessons/15_climbing.tscn.
##
## Extends src/lessons/analog_stances.gd (Lesson 14), so every key of
## Lessons 01-14 still works. The scene adds:
##   ClimbFace   a ClimbableRock (src/climb/climbable_rock.gd) built from
##               data/rocks/climbing_face.tres
##   Climb       a ClimbController (src/climb/climb_controller.gd), after
##               Player in the tree
## and swaps the player for scenes/climbing_player.tscn and the
## BalanceMonitor script for ClimbBalanceMonitor. This script adds:
##   0   starts a climb, or lets go (gamepad: Start)
##   F1  shows or hides the holds and the climbing lines
##   F2  switches the arm solver (two-bone, FABRIK)
## While climbing, 5 / 6 (the triggers) reach with the left / right hand,
## and WASD (the left stick) moves the reaching hand. HUD/RockLabel gets
## five lines; "limb error" is the largest distance between a hand or an
## ankle and its target in the last pose.

@onready var _climb: ClimbController = $Climb
@onready var _face: ClimbableRock = $ClimbFace


func _ready() -> void:
	super()
	if _face == null:
		return
	# Q: Where does the rock stand?
	# A: Its shape space has the foot of the face at y = 0, z = 0.6 (the
	#    front of the box). The rock is lowered or raised so that this
	#    point lies on the terrain, as StepRow is in Lesson 12.
	var foot := _face.global_transform * Vector3(0.0, 0.0, 0.6)
	_face.global_position.y += _terrain.height_at(foot.x, foot.z) - foot.y
	# Q: Which camera turn looks at the rock?
	# A: The camera looks along the pivot's -z. A turn by a about +y sends
	#    (0, 0, -1) to (-sin a, 0, -cos a); for the direction d to the
	#    rock, a = atan2(-d.x, -d.z).
	var d := foot - _player.global_position
	_player._rotate_camera(atan2(-d.x, -d.z), 0.0)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if _climb == null:
		return
	if event.is_action_pressed("toggle_climb"):
		if _climb.state == ClimbController.State.WALKING:
			_climb.begin_climb()
		else:
			_climb.let_go()
	elif event.is_action_pressed("toggle_climb_debug"):
		_climb.debug_draw = not _climb.debug_draw
		_face.show_holds = _climb.debug_draw
	elif event.is_action_pressed("cycle_arm_solver"):
		_climb.cycle_arm_solver()


func _update_hud() -> void:
	super()
	if _climb == null:
		return
	var limb_text := PackedStringArray()
	for i in 4:
		limb_text.append("%s %s" % [ClimbController.LIMB_NAMES[i], ClimbController.LIMB_STATE_NAMES[_climb.limbs[i].state]])
	var pull := "-"
	if _balance is ClimbBalanceMonitor:
		var value := (_balance as ClimbBalanceMonitor).hand_pull
		if is_inf(value):
			pull = "hanging"
		elif not is_nan(value):
			pull = "%.2f W" % value
	var status := ClimbController.STATE_NAMES[_climb.state]
	if _climb.state == ClimbController.State.WALKING and _climb.refusal != "":
		status += " (%s)" % _climb.refusal
	var limb_error := 0.0
	for i in 4:
		limb_error = maxf(limb_error, _climb.limb_errors[i])
	_rock_label.text += "\nclimb: %s [0 / Start]   holds %d [F1]\n%s\nascent %.2f m   moves %d hands %d feet   residual %.3f m\nhand pull %s   arms %s [F2]\nlimb error %.3f m   climb tick %.2f ms" % [
		status,
		_face.holds.size(),
		"   ".join(limb_text),
		_climb.ascent,
		_climb.hand_moves,
		_climb.foot_moves,
		_climb.residual,
		pull,
		ClimbController.ARM_SOLVER_NAMES[_climb.arm_solver],
		limb_error,
		_climb.climb_milliseconds,
	]
