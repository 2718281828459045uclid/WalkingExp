@tool
class_name SegmentMasses
extends Resource
## Mass fractions and center-of-mass positions of body segments (Lesson 13).
##
## How the files relate:
##   data/body/winter_segment_masses.tres   assigns this script; the
##                                          defaults below are its values
##   BodyProportions (body_proportions.gd)  gives the joint positions that
##                                          bound each segment
##   CenterOfMass (center_of_mass.gd)       reads segments() and the
##                                          skeleton's pose
##
## Source: D. A. Winter, Biomechanics and Motor Control of Human Movement,
## 4th ed., Table 4.1 (anthropometric data after Dempster). Each segment
## has
##   fraction  segment mass / total body mass
##   ratio     distance of the segment's center of mass from the proximal
##             end, as a fraction of the segment length
## The fractions of the table sum to 1.000 for the whole body, counting
## arms and legs twice. Winter's "forearm and hand" and "head and neck"
## rows are used because the rig has no hand bone and no separate neck
## mass.
##
## Each segment runs between two points given in bone frames (the rig's
## rest frames, BodyProportions.bone_specs()). Where the rig has no joint
## at Winter's landmark, the nearest rig point stands in for it; the
## comments in segments() name each substitute.

@export var body_mass: float = 70.0
@export_group("Head and trunk")
@export var head_neck_fraction: float = 0.081
@export var head_neck_ratio: float = 1.0
@export var trunk_fraction: float = 0.497
@export var trunk_ratio: float = 0.50
@export_group("Arm")
@export var upper_arm_fraction: float = 0.028
@export var upper_arm_ratio: float = 0.436
@export var forearm_hand_fraction: float = 0.022
@export var forearm_hand_ratio: float = 0.682
@export_group("Leg")
@export var thigh_fraction: float = 0.100
@export var thigh_ratio: float = 0.433
@export var shank_fraction: float = 0.0465
@export var shank_ratio: float = 0.433
@export var foot_fraction: float = 0.0145
@export var foot_ratio: float = 0.50


## Sum of all fractions, with arms and legs counted twice. 1.0 for the
## table's values.
func total_fraction() -> float:
	var limbs := upper_arm_fraction + forearm_hand_fraction + thigh_fraction + shank_fraction + foot_fraction
	return head_neck_fraction + trunk_fraction + 2.0 * limbs


## The segment list for a body. Each entry is a Dictionary:
##   name                 String
##   proximal_bone        StringName; proximal_point: Vector3 in its frame
##   distal_bone          StringName; distal_point: Vector3 in its frame
##   fraction, ratio      as in the table
func segments(p: BodyProportions) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var shoulder_y := p.chest_length - p.shoulder_drop
	# Trunk: Winter's landmarks are the greater trochanter and the
	# glenohumeral joint. Here: the Hips joint (midpoint of the hip
	# joints) and the midpoint of the shoulder line in the Chest frame.
	list.append(_segment("Trunk", &"Hips", Vector3.ZERO, &"Chest", Vector3(0.0, shoulder_y, 0.0), trunk_fraction, trunk_ratio))
	# Head and neck: from C7-T1 (the Neck joint) to the ear canal, with
	# ratio 1.0, so the mass sits at the ear canal. Here: the middle of
	# the head's height.
	list.append(_segment("HeadNeck", &"Neck", Vector3.ZERO, &"Head", Vector3(0.0, 0.5 * p.head_length, 0.0), head_neck_fraction, head_neck_ratio))
	for suffix in ["L", "R"]:
		list.append(_segment("UpperArm." + suffix, StringName("UpperArm." + suffix), Vector3.ZERO,
				StringName("LowerArm." + suffix), Vector3.ZERO, upper_arm_fraction, upper_arm_ratio))
		# Forearm and hand: elbow to the ulnar styloid (the wrist), the
		# end of the forearm bone.
		list.append(_segment("ForearmHand." + suffix, StringName("LowerArm." + suffix), Vector3.ZERO,
				StringName("LowerArm." + suffix), Vector3(0.0, -p.forearm_length, 0.0), forearm_hand_fraction, forearm_hand_ratio))
		list.append(_segment("Thigh." + suffix, StringName("UpperLeg." + suffix), Vector3.ZERO,
				StringName("LowerLeg." + suffix), Vector3.ZERO, thigh_fraction, thigh_ratio))
		list.append(_segment("Shank." + suffix, StringName("LowerLeg." + suffix), Vector3.ZERO,
				StringName("Foot." + suffix), Vector3.ZERO, shank_fraction, shank_ratio))
		# Foot: Winter's landmarks are the lateral malleolus (the ankle)
		# and the head of the second metatarsal. Here: the ankle joint and
		# a point on the sole half a foot length ahead of the ankle.
		list.append(_segment("Foot." + suffix, StringName("Foot." + suffix), Vector3.ZERO,
				StringName("Foot." + suffix), Vector3(0.0, -p.ankle_height, -0.5 * p.foot_length), foot_fraction, foot_ratio))
	return list


func _segment(segment_name: String, proximal_bone: StringName, proximal_point: Vector3,
		distal_bone: StringName, distal_point: Vector3, fraction: float, ratio: float) -> Dictionary:
	return {
		"name": segment_name,
		"proximal_bone": proximal_bone,
		"proximal_point": proximal_point,
		"distal_bone": distal_bone,
		"distal_point": distal_point,
		"fraction": fraction,
		"ratio": ratio,
	}
