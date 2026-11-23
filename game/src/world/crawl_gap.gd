@tool
class_name CrawlGap
extends BoxCourse
## A low passage: a flat floor, two walls and a roof (Lesson 16). The roof's
## underside lies roof_height above the floor, so the clearance is exact
## whatever the terrain does.
##
##   side view (the course runs along -z; the entrance is at +z)
##
##              roof
##          +-----------+
##          |           |  roof_height
##   ramp  /-------------------\  ramp
##        /        floor        \
##
## How the files relate:
##   BoxCourse (box_course.gd, Lesson 02)  internal boxes, collision in the
##                                         running game
##   src/lessons/crawling_and_scrambling.gd  sets the height of this node to
##                                         the highest terrain point under
##                                         floor_rect(), so the terrain
##                                         never comes through the floor
##
## The ramps at both ends run down from the floor's edges at
## ramp_angle_degrees until BURY_DEPTH below the origin, as RampTower's do:
## where the terrain is higher, the ramp lies buried in it.

## Free height between the floor and the roof, meters.
@export_range(0.3, 2.5, 0.01) var roof_height: float = 0.9:
	set(value):
		roof_height = value
		_queue_rebuild()
## Free width between the walls, meters.
@export_range(0.5, 4.0, 0.05) var gap_width: float = 1.1:
	set(value):
		gap_width = value
		_queue_rebuild()
## Length of the roof along the course, meters.
@export_range(0.5, 10.0, 0.1) var gap_length: float = 2.4:
	set(value):
		gap_length = value
		_queue_rebuild()
## Floor before and after the roof, meters.
@export_range(0.5, 5.0, 0.1) var apron: float = 1.2:
	set(value):
		apron = value
		_queue_rebuild()
## Slope of the two ramps onto the floor, degrees.
@export_range(5.0, 30.0, 0.5) var ramp_angle_degrees: float = 15.0:
	set(value):
		ramp_angle_degrees = value
		_queue_rebuild()

const WALL_THICKNESS := 0.5
const ROOF_THICKNESS := 0.4
## Floor beyond the outer faces of the walls, on each side, meters.
const FLOOR_MARGIN := 0.4


## The floor in the node's x-z plane: position (x, z) and size.
func floor_rect() -> Rect2:
	var width := gap_width + 2.0 * (WALL_THICKNESS + FLOOR_MARGIN)
	var length := gap_length + 2.0 * apron
	return Rect2(-0.5 * width, -0.5 * length, width, length)


func _build() -> void:
	var rect := floor_rect()
	_add_box(Vector3(rect.size.x, BURY_DEPTH, rect.size.y), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5 * BURY_DEPTH, 0.0)))
	for side in 2:
		var x := (0.5 * gap_width + 0.5 * WALL_THICKNESS) * (-1.0 if side == 0 else 1.0)
		_add_box(Vector3(WALL_THICKNESS, roof_height, gap_length), Transform3D(Basis.IDENTITY, Vector3(x, 0.5 * roof_height, 0.0)))
	var roof_width := gap_width + 2.0 * WALL_THICKNESS
	_add_box(Vector3(roof_width, ROOF_THICKNESS, gap_length), Transform3D(Basis.IDENTITY, Vector3(0.0, roof_height + 0.5 * ROOF_THICKNESS, 0.0)))
	# One ramp at each end: the +z ramp, then the same ramp turned half a
	# turn about +y for the -z end.
	for turn in 2:
		_add_ramp(rect, Transform3D(Basis(Vector3.UP, turn * PI), Vector3.ZERO))
	_add_label("%.2f m" % roof_height, Vector3(0.0, roof_height + ROOF_THICKNESS + 0.6, 0.0))


## Adds the ramp that meets the floor's +z edge, then applies turn.
##
## Q: Which way does the ramp's top face run?
## A: Down and away from the floor, toward +z. RampTower (Lesson 02)
##    derives the frame: the face's up-slope direction is
##    (0, sin a, -cos a) and its normal (0, cos a, sin a); Basis(RIGHT, a)
##    turns a flat box into that frame.
func _add_ramp(rect: Rect2, turn: Transform3D) -> void:
	var a := deg_to_rad(ramp_angle_degrees)
	var up_slope := Vector3(0.0, sin(a), -cos(a))
	var n := Vector3(0.0, cos(a), sin(a))
	var top_edge := Vector3(0.0, 0.0, 0.5 * rect.size.y)
	var length := BURY_DEPTH / sin(a)
	var face_center := top_edge - up_slope * (length * 0.5)
	var thickness := 0.3
	var center := face_center - n * (thickness * 0.5)
	_add_box(Vector3(rect.size.x, thickness, length), turn * Transform3D(Basis(Vector3.RIGHT, a), center))
