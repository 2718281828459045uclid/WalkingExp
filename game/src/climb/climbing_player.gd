class_name ClimbingPlayer
extends BodyPlayer
## A BodyPlayer that hands its body to a ClimbController (Lesson 15).
##
## How the files relate:
##   Player (Lesson 00-02)        walks, falls, turns the camera
##   BodyPlayer (Lesson 11)       feeds the rig with the distance walked
##   this file                    while `climbing` is true, only turns the
##                                camera and reads the stick
##   ClimbController              moves this node and poses the rig
##   scenes/climbing_player.tscn  a copy of grounded_player.tscn with this
##                                script

## Set by ClimbController. While true, the capsule does not move by
## itself: no walking, no gravity, no move_and_slide().
var climbing := false:
	set(value):
		climbing = value
		velocity = Vector3.ZERO
		# Q: Why reset the last position here?
		# A: BodyPlayer turns the distance moved since the last tick into
		#    walk phase. The climb moves the capsule by meters; the first
		#    walking tick afterward would count them as steps.
		_last_position = global_position
		ground_speed = 0.0


func _physics_process(delta: float) -> void:
	if not climbing:
		super(delta)
		return
	# The two lines of Player._physics_process() that do not move the body.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_rotate_camera(-look.x * stick_look_speed * delta, -look.y * stick_look_speed * delta)
	_read_stick()


## The node the controller turns toward the rock.
func body_mesh() -> Node3D:
	return _body_mesh
