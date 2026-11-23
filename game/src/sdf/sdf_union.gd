@tool
class_name SdfUnion
extends SdfShape
## Union of child shapes: min of their distances.
##
## Q: Is min(d1, d2) the exact distance to the union?
## A: Outside both solids, yes: the nearest surface point of the union
##    is the nearer of the two nearest points. Inside an overlap it is
##    not: the point is inside both, and the true depth may be larger
##    than either child reports. Lesson 07, P3.

@export var shapes: Array[SdfShape] = []:
	set(value):
		_watch_all(shapes, value)
		shapes = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	var d := INF
	for shape in shapes:
		if shape != null:
			d = minf(d, shape.evaluate(p))
	return d


func lipschitz_bound() -> float:
	var bound := 0.0
	for shape in shapes:
		if shape != null:
			bound = maxf(bound, shape.lipschitz_bound())
	return bound


func bounds() -> AABB:
	return level_bounds(0.0)


func level_bounds(level: float) -> AABB:
	return SdfShape.merged_level_bounds(shapes, level)
