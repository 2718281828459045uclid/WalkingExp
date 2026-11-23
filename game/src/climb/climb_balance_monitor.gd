class_name ClimbBalanceMonitor
extends BalanceMonitor
## BalanceMonitor (Lesson 13) with the hands as support (Lesson 15).
##
## How the files relate:
##   BalanceMonitor     measures the center of mass and the polygon of the
##                      feet (unchanged; this class calls it first)
##   ClimbController    contact_points(): every limb in HOLD
##   this file          while climbing, rebuilds the polygon from all
##                      contacts and adds the hand pull
##
## Two measures while climbing:
##   margin      the signed distance of Lesson 13, with the hands' ground
##               points added to the polygon. On a vertical face every
##               contact projects near one line, and the margin is about
##               minus the distance of the center of mass from the face.
##   hand_pull   F / W: the horizontal pull the hands must hold, as a
##               fraction of the body's weight, from the balance of
##               moments about the line of the feet (README P9):
##                 F h = W d   ->   F / W = d / h
##               d  the distance of the center of mass in front of the
##                  feet, along the face normal
##               h  the height of the hands above the feet

## The climb to read. The scene assigns it.
@export var climb: ClimbController

## F / W while climbing with hands and feet on holds. INF while hanging
## from the hands alone; NAN when not climbing.
var hand_pull := NAN
## d and h of the last measurement, meters.
var lever_distance := 0.0
var lever_height := 0.0


func measure() -> void:
	super()
	if climb == null or climb.state != ClimbController.State.CLIMBING:
		hand_pull = NAN
		return
	var hands := PackedVector3Array()
	var feet := PackedVector3Array()
	var corners := PackedVector2Array()
	var height_sum := 0.0
	for contact in climb.contact_points():
		var point: Vector3 = contact[0]
		if contact[1]:
			hands.append(point)
		else:
			feet.append(point)
		corners.append(SupportPolygon.ground_point(point))
		height_sum += point.y
	polygon = SupportPolygon.convex_hull(corners)
	polygon_height = height_sum / corners.size() if corners.size() > 0 else center_of_mass.y - center_height
	margin = SupportPolygon.signed_distance(polygon, SupportPolygon.ground_point(center_of_mass))
	state = next_state(state, margin, not polygon.is_empty(), marginal_margin, hysteresis)
	hand_pull = pull_ratio(center_of_mass, hands, feet, climb.face_normal())
	lever_distance = 0.0 if feet.is_empty() else (center_of_mass - _mean(feet)).dot(climb.face_normal())
	lever_height = 0.0 if feet.is_empty() or hands.is_empty() else _mean(hands).y - _mean(feet).y


## F / W from the moments about the feet.
##
## Q: Why the moments about the feet?
## A: The feet push on the rock and the hands pull. About the line
##    through the feet, the foot forces have no lever arm and drop out of
##    the equation. What is left: the weight W at horizontal distance d
##    turns the body away from the rock; the hand pull F at height h
##    turns it back. In balance F h = W d.
## Q: What does this leave out?
## A: The vertical part V of the hand force. Its lever arm about the line
##    of the feet is e, the distance of the hands in front of the feet
##    along the normal: W d = F h + V e. The ratio d / h assumes e = 0,
##    hand and foot holds in one vertical plane. The code measures d from
##    the feet and does not read the hands' depth; on this face the holds
##    differ in depth by up to the 0.11 m that a knob protrudes.
## Q: What if there are no feet on holds?
## A: The hands carry everything, and the ratio is not defined by this
##    model: INF. With no hands, or with the hands at the feet's height,
##    the ratio is NAN.
static func pull_ratio(com: Vector3, hands: PackedVector3Array, feet: PackedVector3Array, normal: Vector3) -> float:
	if hands.is_empty():
		return NAN
	if feet.is_empty():
		return INF
	var h := _mean(hands).y - _mean(feet).y
	if h < 0.05:
		return NAN
	var d := (com - _mean(feet)).dot(normal)
	return maxf(d, 0.0) / h


static func _mean(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / points.size()
