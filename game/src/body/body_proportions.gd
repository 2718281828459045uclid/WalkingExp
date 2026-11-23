@tool
class_name BodyProportions
extends Resource
## Lengths and radii of the procedural body (Lesson 11).
##
## How the files relate:
##   data/body/default_proportions.tres   one instance of this class
##   BodyRig (src/body/body_rig.gd)       reads bone_specs() and builds a
##                                        Skeleton3D with capsule meshes
##
## All lengths are in meters. The body stands with its soles at y = 0 and
## faces -z, so its left side is -x and its right side is +x.

@export_group("Legs")
## Hip joint to knee joint.
@export var thigh_length: float = 0.44
## Knee joint to ankle joint.
@export var shin_length: float = 0.42
## Ankle joint to the sole.
@export var ankle_height: float = 0.08
## Heel to toe.
@export var foot_length: float = 0.24
## Distance of each hip joint from the body's middle plane x = 0.
@export var hip_half_width: float = 0.10

@export_group("Torso and head")
@export var spine_length: float = 0.22
@export var chest_length: float = 0.26
@export var neck_length: float = 0.08
## Base of the skull to the top of the head.
@export var head_length: float = 0.24
## Distance of each shoulder joint from the middle plane.
@export var shoulder_half_width: float = 0.19
## Distance of the shoulder joints below the top of the chest.
@export var shoulder_drop: float = 0.04

@export_group("Arms")
@export var upper_arm_length: float = 0.29
@export var forearm_length: float = 0.27

@export_group("Radii")
@export var pelvis_radius: float = 0.11
@export var spine_radius: float = 0.12
@export var chest_radius: float = 0.14
@export var neck_radius: float = 0.05
@export var head_radius: float = 0.11
@export var thigh_radius: float = 0.07
@export var shin_radius: float = 0.055
@export var foot_radius: float = 0.04
@export var upper_arm_radius: float = 0.045
@export var forearm_radius: float = 0.04


## Height of the hip joints above the soles when the legs hang straight.
func hip_height() -> float:
	return thigh_length + shin_length + ankle_height


## Height of the top of the head above the soles in the rest pose.
func standing_height() -> float:
	return hip_height() + spine_length + chest_length + neck_length + head_length


## The bone list, parents before children.
##
## Each entry is a Dictionary:
##   name      StringName of the bone
##   parent    index of the parent bone, -1 for the root
##   offset    Vector3: the bone's joint in its parent's frame (the rest
##             translation). The rest rotation of every bone is the identity.
##   segments  Array of [Vector3 a, Vector3 b, float radius]: capsules drawn
##             in the bone's own frame from a to b
##
## Q: Why do all bones have the identity as rest rotation?
## A: Then a bone's frame, at rest, has the same axes as the body: +y up,
##    -z forward, +x to the right. A rotation about the bone's x axis is a
##    forward or backward swing for every limb, which makes the walk cycle
##    (WalkCycle) readable. Rigs exported from modeling programs usually
##    point each bone's +y along the limb instead; Exercise E4 asks what
##    changes then.
func bone_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var chest_top := Vector3(0.0, chest_length, 0.0)
	var shoulder_y := chest_length - shoulder_drop
	var sole_y := -ankle_height + foot_radius

	# Torso chain: Hips -> Spine -> Chest -> Neck -> Head.
	specs.append(_spec(&"Hips", -1, Vector3(0.0, hip_height(), 0.0), [
		[Vector3(-hip_half_width, 0.0, 0.0), Vector3(hip_half_width, 0.0, 0.0), pelvis_radius],
	]))
	specs.append(_spec(&"Spine", 0, Vector3.ZERO, [
		[Vector3.ZERO, Vector3(0.0, spine_length, 0.0), spine_radius],
	]))
	specs.append(_spec(&"Chest", 1, Vector3(0.0, spine_length, 0.0), [
		[Vector3.ZERO, chest_top, chest_radius],
		[Vector3(-shoulder_half_width, shoulder_y, 0.0), Vector3(shoulder_half_width, shoulder_y, 0.0), upper_arm_radius],
	]))
	specs.append(_spec(&"Neck", 2, chest_top, [
		[Vector3.ZERO, Vector3(0.0, neck_length, 0.0), neck_radius],
	]))
	# The small capsule in front of the face shows which way the body faces,
	# as the "nose" box of the Lesson 00 capsule did.
	specs.append(_spec(&"Head", 3, Vector3(0.0, neck_length, 0.0), [
		[Vector3(0.0, head_radius, 0.0), Vector3(0.0, head_length - head_radius, 0.0), head_radius],
		[Vector3(0.0, 0.5 * head_length, -0.8 * head_radius), Vector3(0.0, 0.5 * head_length, -1.15 * head_radius), 0.025],
	]))

	# Limbs: the left side has sign -1 (x < 0), the right side +1.
	for side in [[&"L", -1.0], [&"R", 1.0]]:
		var suffix: StringName = side[0]
		var sign_x: float = side[1]
		var upper_leg := specs.size()
		specs.append(_spec(StringName("UpperLeg." + suffix), 0, Vector3(sign_x * hip_half_width, 0.0, 0.0), [
			[Vector3.ZERO, Vector3(0.0, -thigh_length, 0.0), thigh_radius],
		]))
		specs.append(_spec(StringName("LowerLeg." + suffix), upper_leg, Vector3(0.0, -thigh_length, 0.0), [
			[Vector3.ZERO, Vector3(0.0, -shin_length, 0.0), shin_radius],
		]))
		# The foot capsule runs from the heel to the toes along -z, with its
		# lowest point on the sole plane y = -ankle_height.
		specs.append(_spec(StringName("Foot." + suffix), upper_leg + 1, Vector3(0.0, -shin_length, 0.0), [
			[Vector3(0.0, sole_y, 0.25 * foot_length - foot_radius), Vector3(0.0, sole_y, -0.75 * foot_length + foot_radius), foot_radius],
		]))
		var upper_arm := specs.size()
		specs.append(_spec(StringName("UpperArm." + suffix), 2, Vector3(sign_x * shoulder_half_width, shoulder_y, 0.0), [
			[Vector3.ZERO, Vector3(0.0, -upper_arm_length, 0.0), upper_arm_radius],
		]))
		specs.append(_spec(StringName("LowerArm." + suffix), upper_arm, Vector3(0.0, -upper_arm_length, 0.0), [
			[Vector3.ZERO, Vector3(0.0, -forearm_length, 0.0), forearm_radius],
		]))
	return specs


func _spec(bone_name: StringName, parent: int, offset: Vector3, segments: Array) -> Dictionary:
	return {"name": bone_name, "parent": parent, "offset": offset, "segments": segments}
