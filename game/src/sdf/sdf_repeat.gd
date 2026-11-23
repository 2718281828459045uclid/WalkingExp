@tool
class_name SdfRepeat
extends SdfShape
## Domain repetition: copies of a child on a grid, `count` copies on each
## side of the origin along each axis (Inigo Quilez, "opRepLim").
##
## Q: How can one evaluation of the child draw many copies?
## A: The point is folded into the nearest cell before the child is
##    asked: q = p - period * round(p / period). Every cell then sees the
##    same field. Clamping the cell index to [-count, count] stops the
##    pattern at the edges.
##
## The result is exact only while the child fits inside half a period in
## each direction. A child that reaches into the next cell is cut at the
## cell boundary (Lesson 07, Tweak T5).

@export var shape: SdfShape:
	set(value):
		_watch(shape, value)
		shape = value
		emit_changed()
## Distance between copies along x, y, z. Use 0 on an axis to not repeat.
@export var period: Vector3 = Vector3(4, 0, 4):
	set(value):
		period = value
		emit_changed()
## Copies on each side of the origin per axis: (2, 0, 1) gives 5 x 1 x 3.
@export var count: Vector3i = Vector3i(1, 0, 1):
	set(value):
		count = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	if shape == null:
		return INF
	var q := p
	for axis in 3:
		if period[axis] > 0.0:
			var cell := clampf(roundf(p[axis] / period[axis]), -count[axis], count[axis])
			q[axis] = p[axis] - period[axis] * cell
	return shape.evaluate(q)


func lipschitz_bound() -> float:
	return 1.0 if shape == null else shape.lipschitz_bound()


func bounds() -> AABB:
	return level_bounds(0.0)


func level_bounds(level: float) -> AABB:
	if shape == null:
		return AABB()
	var b := shape.level_bounds(level)
	var spread := Vector3(
		period.x * count.x if period.x > 0.0 else 0.0,
		period.y * count.y if period.y > 0.0 else 0.0,
		period.z * count.z if period.z > 0.0 else 0.0)
	return AABB(b.position - spread, b.size + spread * 2.0)
