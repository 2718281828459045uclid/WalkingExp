extends "res://src/lessons/raymarching.gd"
## Root script of scenes/lessons/11_skeleton_from_code.tscn.
##
## Extends src/lessons/raymarching.gd (Lesson 10), so every key of
## Lessons 01-10 still works. In this scene the node Player is an instance
## of scenes/body_player.tscn (BodyPlayer, a subclass of Player), so the
## earlier root scripts, which type it as Player, run unchanged.
## This script adds:
##   E  cycles the body view: rig, rig and capsule, capsule
## and appends the walk phase, amount and speed to HUD/Label.

const BODY_VIEW_NAMES: PackedStringArray = ["rig", "rig + capsule", "capsule"]


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("toggle_body_view"):
		var body := _player as BodyPlayer
		body.body_view = ((body.body_view + 1) % BODY_VIEW_NAMES.size()) as BodyPlayer.BodyView


func _update_hud() -> void:
	super()
	# Q: Why the null check?
	# A: sandbox.gd calls _update_hud() from its _ready(), before this
	#    node's children have run theirs; the rig may not exist yet.
	var body := _player as BodyPlayer
	if body == null or body.rig == null:
		return
	_hud_label.text += "\nbody: %s [E]   phase %.2f   amount %.2f   %.2f m/s" % [
		BODY_VIEW_NAMES[body.body_view],
		body.rig.phase,
		body.rig.amount,
		body.ground_speed,
	]
