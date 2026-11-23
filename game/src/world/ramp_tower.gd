@tool
class_name RampTower
extends BoxCourse
## A square platform with one ramp on each side, each at its own angle.
## Lesson 02 uses it to locate the walkable limit (floor_max_angle) and to
## watch the walker slide down a ramp that is too steep.
##
##   seen from above (+x right, +z down the page)
##
##              ramp -z
##            +---------+
##    ramp -x | platform| ramp +x
##            +---------+
##              ramp +z
##
## Each ramp is a thin box tilted about its own x axis. Its top face runs
## from the platform's upper edge down to the ground, and continues below
## the ground so the foot of the ramp has no exposed edge.

## Height of the platform top above this node's origin, in meters.
@export_range(0.5, 10.0, 0.1) var platform_height: float = 3.0:
	set(value):
		platform_height = value
		_queue_rebuild()
## Width and depth of the platform, and width of each ramp, in meters.
@export_range(1.0, 20.0, 0.5) var platform_size: float = 4.0:
	set(value):
		platform_size = value
		_queue_rebuild()
## Ramp angles in degrees, for the sides facing +z, +x, -z, -x, in that order.
@export var ramp_angles_degrees := PackedFloat32Array([44.0, 30.0, 46.0, 55.0]):
	set(value):
		ramp_angles_degrees = value
		_queue_rebuild()

const RAMP_THICKNESS := 0.5


func _build() -> void:
	var platform_center := Vector3(0.0, (platform_height - BURY_DEPTH) * 0.5, 0.0)
	_add_box(
		Vector3(platform_size, platform_height + BURY_DEPTH, platform_size),
		Transform3D(Basis(), platform_center)
	)
	for side in mini(ramp_angles_degrees.size(), 4):
		var angle := ramp_angles_degrees[side]
		# Q: How does one ramp-building recipe serve all four sides?
		# A: Build the ramp on the +z side, then rotate it about +y by
		#    side * 90 degrees. A rotation of +90 degrees sends +z to +x.
		var side_rotation := Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3.ZERO)
		_add_ramp(angle, side_rotation)


## Adds one ramp on the +z side rising toward -z, then applies side_rotation.
func _add_ramp(angle_degrees: float, side_rotation: Transform3D) -> void:
	var a := deg_to_rad(clampf(angle_degrees, 5.0, 85.0))

	# Q: Which two vectors describe the tilted top face?
	# A: up_slope points along the face toward the platform:
	#    (0, sin a, -cos a). The face normal n is perpendicular to it and
	#    to the x axis: (0, cos a, sin a). Basis(RIGHT, a) sends the box's
	#    local +y to n and its local +z to -up_slope.
	var up_slope := Vector3(0.0, sin(a), -cos(a))
	var n := Vector3(0.0, cos(a), sin(a))

	# The face runs from the platform's top edge down past the ground,
	# until it is BURY_DEPTH below the origin.
	var top_edge := Vector3(0.0, platform_height, platform_size * 0.5)
	var length := (platform_height + BURY_DEPTH) / sin(a)
	var face_center := top_edge - up_slope * (length * 0.5)
	var box_center := face_center - n * (RAMP_THICKNESS * 0.5)

	var ramp_xf := Transform3D(Basis(Vector3.RIGHT, a), box_center)
	_add_box(Vector3(platform_size, RAMP_THICKNESS, length), side_rotation * ramp_xf)

	# Label above the middle of the visible part of the face.
	var visible_middle := top_edge - up_slope * (platform_height / sin(a) * 0.5)
	_add_label("%d°" % roundi(angle_degrees), side_rotation * (visible_middle + n * 0.8))
