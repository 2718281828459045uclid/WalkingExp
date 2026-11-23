class_name CenterOfMass
extends RefCounted
## The whole-body center of mass from segment masses (Lesson 13).
##
##   c = sum_i m_i c_i / sum_i m_i
##
## c_i is the center of mass of segment i, a point on the line from its
## proximal to its distal end:
##
##   c_i = P_i + ratio_i (D_i - P_i)
##
## The masses enter only as fractions of the total, so the body mass
## cancels: c = sum_i f_i c_i / sum_i f_i.
##
## Reads the segment table from SegmentMasses and the bone poses from a
## Skeleton3D. Used by BalanceMonitor (balance_monitor.gd).


## Center of mass of each segment, in the skeleton's frame. Bone poses are
## read with get_bone_global_pose(): call
## skeleton.force_update_all_bone_transforms() first when the pose was set
## in the same frame.
static func segment_centers(skeleton: Skeleton3D, segments: Array[Dictionary]) -> PackedVector3Array:
	var centers := PackedVector3Array()
	for segment in segments:
		var proximal := _point(skeleton, segment.proximal_bone, segment.proximal_point)
		var distal := _point(skeleton, segment.distal_bone, segment.distal_point)
		centers.append(proximal.lerp(distal, segment.ratio))
	return centers


## The weighted mean of the segment centers, in the skeleton's frame.
static func compute(skeleton: Skeleton3D, segments: Array[Dictionary]) -> Vector3:
	var centers := segment_centers(skeleton, segments)
	return weighted_mean(centers, segments)


## sum f_i c_i / sum f_i.
static func weighted_mean(centers: PackedVector3Array, segments: Array[Dictionary]) -> Vector3:
	# Q: Why sum in float (64-bit) instead of Vector3 (32-bit)?
	# A: Thirteen terms in 32 bits are accurate to about 1e-7 m, which is
	#    enough here. The separate sums keep the code the same as the
	#    formula above and leave no doubt about the precision.
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var total := 0.0
	for i in centers.size():
		var f: float = segments[i].fraction
		sx += f * centers[i].x
		sy += f * centers[i].y
		sz += f * centers[i].z
		total += f
	if total <= 0.0:
		return Vector3.ZERO
	return Vector3(sx / total, sy / total, sz / total)


static func _point(skeleton: Skeleton3D, bone: StringName, local_point: Vector3) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		push_error("CenterOfMass: no bone %s" % bone)
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(index) * local_point
