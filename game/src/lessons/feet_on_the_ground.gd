extends "res://src/lessons/skeleton_from_code.gd"
## Root script of scenes/lessons/12_feet_on_the_ground.tscn.
##
## Extends src/lessons/skeleton_from_code.gd (Lesson 11), so every key of
## Lessons 01-11 still works. In this scene the node Player is an instance
## of scenes/grounded_player.tscn: a BodyPlayer whose BodyMesh/Rig runs
## FootRig (src/body/foot_rig.gd). The node Footsteps runs
## PlantFootstepReporter, which sends a step when a foot is planted.
## This script adds:
##   Q  cycles the leg solver: own IK, TwoBoneIK3D, walk cycle (Lesson 11)
##   Y  toggles the foot debug lines (rays, plants, swing targets)
## places a StepRow (Lesson 02) on the hillside, and appends two lines to
## HUD/RockLabel (the left label already reaches the bottom of the window).

const SOLVER_NAMES: PackedStringArray = ["walk cycle", "own IK", "TwoBoneIK3D"]
## Order in which Q steps through FootRig.Solver.
const SOLVER_CYCLE: Array[FootRig.Solver] = [FootRig.Solver.OWN, FootRig.Solver.ENGINE, FootRig.Solver.WALK_CYCLE]

@onready var _step_row: StepRow = $StepRow


func _ready() -> void:
	super()
	# Q: Why the height at the front edge of the first step, not at the
	#    node's origin?
	# A: The row stands on a hillside that falls away along -z. Measured
	#    from the front edge, the first riser is step_heights[0] above the
	#    ground the player walks up from; each later riser adds the
	#    difference of two heights, whatever the ground does below. The
	#    row becomes a staircase on a raised walkway that ends in a drop.
	var front := _step_row.position.z + 0.5 * _step_row.step_size.y
	_step_row.position.y = _terrain.height_at(_step_row.position.x, front)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	var rig := _foot_rig()
	if rig == null:
		return
	if event.is_action_pressed("cycle_foot_solver"):
		var next := (SOLVER_CYCLE.find(rig.solver) + 1) % SOLVER_CYCLE.size()
		rig.solver = SOLVER_CYCLE[next]
	elif event.is_action_pressed("toggle_foot_debug"):
		rig.debug_draw = not rig.debug_draw


func _update_hud() -> void:
	super()
	var rig := _foot_rig()
	if rig == null:
		return
	_rock_label.text += "\nlegs: %s [Q]   lines [Y]\npelvis %+.3f m   ankle error %.3f / %.3f m" % [
		SOLVER_NAMES[rig.solver],
		rig.pelvis_offset,
		rig.ankle_errors[0],
		rig.ankle_errors[1],
	]


func _foot_rig() -> FootRig:
	var body := _player as BodyPlayer
	if body == null:
		return null
	return body.rig as FootRig
