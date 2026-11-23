class_name WalkCycle
extends Resource
## A placeholder walk: joint angles as sine functions of a phase (Lesson 11).
##
## How the files relate:
##   data/body/placeholder_walk.tres   one instance of this class
##   BodyRig.advance()                 moves the phase with the distance
##                                     walked and calls sample()
##
## The phase phi runs from 0 to 1 over one stride: two steps, left then
## right. At phi = 0 the left leg is in mid-swing (thigh vertical, knee
## fully bent) and the right leg is in mid-stance. The left heel strikes at
## phi = 0.25 and the right heel at phi = 0.75. The left swing spans
## phi in (-0.25, 0.25), the right swing (0.25, 0.75). Every angle is scaled by
## an amount in [0, 1] (0 standing, 1 full walking speed).
##
## Lesson 12 replaces the leg angles with feet placed on the ground by IK;
## nothing here knows where the ground is.

## Distance the body travels during one full cycle (two steps), in meters.
@export var stride_length: float = 1.4
## Largest swing of the thigh forward and backward from vertical.
@export var hip_swing_degrees: float = 24.0
## Largest bend of the knee, reached in the middle of the swing.
@export var knee_bend_degrees: float = 45.0
## Largest swing of the upper arm, opposite to the leg on the same side.
@export var arm_swing_degrees: float = 18.0
## Constant bend of the elbow while walking.
@export var elbow_bend_degrees: float = 15.0
## Turn of the pelvis about the vertical toward the forward leg.
@export var pelvis_yaw_degrees: float = 6.0
## Turn of the chest relative to the pelvis, opposite to the pelvis turn.
@export var chest_counter_yaw_degrees: float = 10.0
## Rise and fall of the hips, twice per cycle, in meters.
@export var bob_height: float = 0.025


## Joint rotations and the hip offset at one phase.
class Pose:
	## StringName of the bone -> Quaternion in the bone's rest frame.
	var rotations: Dictionary = {}
	## Added to the rest translation of the Hips bone.
	var hips_offset := Vector3.ZERO


## Rotation about the bone's x axis by an angle in degrees.
##
## Q: Which way does a positive angle about +x turn a leg?
## A: The leg points along -y. A rotation by a about +x sends
##    (0, -1, 0) to (0, -cos a, -sin a): toward -z, forward. Positive
##    angles swing a limb forward, negative angles swing it back.
static func pitch(degrees: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg_to_rad(degrees))


static func yaw(degrees: float) -> Quaternion:
	return Quaternion(Vector3.UP, deg_to_rad(degrees))


## The pose at phase phi (any real number; only its fractional part
## counts) with the angles scaled by amount.
func sample(phi: float, amount: float) -> Pose:
	var pose := Pose.new()
	var angle := TAU * phi
	var s := sin(angle)
	var c := cos(angle)

	# Q: Why does the knee use max(0, cos) and the hip use sin?
	# A: The hip angle a sin(2 pi phi) increases while its derivative,
	#    proportional to cos(2 pi phi), is positive: that is the swing, when
	#    the foot moves forward through the air and the knee bends to clear
	#    the ground. During the stance (cos < 0) the leg stays straight.
	var left_hip := amount * hip_swing_degrees * s
	var left_knee := -amount * knee_bend_degrees * maxf(0.0, c)
	var right_hip := -left_hip
	var right_knee := -amount * knee_bend_degrees * maxf(0.0, -c)

	pose.rotations[&"UpperLeg.L"] = pitch(left_hip)
	pose.rotations[&"LowerLeg.L"] = pitch(left_knee)
	pose.rotations[&"UpperLeg.R"] = pitch(right_hip)
	pose.rotations[&"LowerLeg.R"] = pitch(right_knee)

	# Q: Why is the foot angle minus the sum of the hip and knee angles?
	# A: Hip, knee and ankle all turn about parallel x axes, so in the side
	#    view their angles add: the foot's pitch relative to the hips is
	#    hip + knee + ankle. Choosing ankle = -(hip + knee) makes the sum 0
	#    and keeps the sole parallel to the pelvis.
	pose.rotations[&"Foot.L"] = pitch(-(left_hip + left_knee))
	pose.rotations[&"Foot.R"] = pitch(-(right_hip + right_knee))

	# Each arm swings with the opposite leg.
	pose.rotations[&"UpperArm.L"] = pitch(-amount * arm_swing_degrees * s)
	pose.rotations[&"UpperArm.R"] = pitch(amount * arm_swing_degrees * s)
	pose.rotations[&"LowerArm.L"] = pitch(amount * elbow_bend_degrees)
	pose.rotations[&"LowerArm.R"] = pitch(amount * elbow_bend_degrees)

	# Q: Why a negative yaw for the pelvis when the left leg is forward?
	# A: A rotation by b about +y sends the left hip (-w, 0, 0) to
	#    (-w cos b, 0, w sin b). For the left hip to move forward (-z),
	#    sin b must be negative.
	pose.rotations[&"Hips"] = yaw(-amount * pelvis_yaw_degrees * s)
	pose.rotations[&"Chest"] = yaw(amount * chest_counter_yaw_degrees * s)

	# Two bobs per cycle: highest when the legs pass each other (phi = 0
	# and 0.5), lowest when they are spread (phi = 0.25 and 0.75).
	pose.hips_offset = Vector3(0.0, amount * bob_height * cos(2.0 * angle), 0.0)
	return pose
