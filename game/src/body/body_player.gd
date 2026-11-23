class_name BodyPlayer
extends Player
## The Lesson 00 capsule walker with a procedural body (Lesson 11).
##
## Scene layout (scenes/body_player.tscn, inherited from scenes/player.tscn):
##   BodyPlayer (CharacterBody3D, this script)
##     CollisionShape3D     unchanged: physics still moves a capsule
##     BodyMesh             turned toward the direction of travel by Player
##       Capsule, Nose      hidden
##       Rig                BodyRig (src/body/body_rig.gd)
##     CameraPivot/...      unchanged
##
## The body follows the capsule: it adds no physics of its own. Every
## physics tick it measures how far the capsule moved on the ground plane
## and passes that distance to the rig, which turns it into a walk phase.
## Rig sits inside BodyMesh, so it inherits the facing rotation.

## Which of the two bodies is drawn.
enum BodyView {
	RIG,          ## The skeleton's capsules only.
	RIG_CAPSULE,  ## The skeleton and the old capsule, for comparison.
	CAPSULE,      ## The Lesson 00 capsule only.
}

var body_view := BodyView.RIG:
	set(value):
		body_view = value
		_apply_body_view()
## Horizontal speed of the last physics tick, in meters per second.
var ground_speed := 0.0

@onready var rig: BodyRig = $BodyMesh/Rig
@onready var _old_capsule: Node3D = $BodyMesh/Capsule
@onready var _old_nose: Node3D = $BodyMesh/Nose

var _last_position := Vector3.ZERO


func _ready() -> void:
	super()
	_last_position = global_position
	_apply_body_view()


func _physics_process(delta: float) -> void:
	super(delta)
	# Q: Why measure the motion instead of reading velocity?
	# A: velocity is the intended motion. move_and_slide() can shorten it
	#    against a wall or turn it along a slope. The change in position is
	#    what the feet would have to cover. Only the part in the ground
	#    plane counts; falling does not move the legs.
	var moved := global_position - _last_position
	_last_position = global_position
	moved.y = 0.0
	var distance := moved.length()
	ground_speed = distance / delta
	# Q: What about a teleport (a respawn, or a scene root setting the
	#    position after _ready)?
	# A: A jump of many meters would advance the phase by many cycles in
	#    one tick. Since only the fractional part of the phase is used, the
	#    pose stays valid; the walk amount ignores it below because the
	#    speed is clamped to walk_speed.
	rig.advance(distance, ground_speed / walk_speed, delta)


func _apply_body_view() -> void:
	if rig == null:
		return
	rig.visible = body_view != BodyView.CAPSULE
	_old_capsule.visible = body_view != BodyView.RIG
	_old_nose.visible = body_view == BodyView.CAPSULE
