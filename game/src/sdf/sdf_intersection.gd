@tool
class_name SdfIntersection
extends SdfShape
## Intersection of child shapes: max of their distances.
## Inside both solids means negative in both, so the larger value decides.

@export var shapes: Array[SdfShape] = []:
	set(value):
		_watch_all(shapes, value)
		shapes = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	var d := -INF
	for shape in shapes:
		if shape != null:
			d = maxf(d, shape.evaluate(p))
	return d


func lipschitz_bound() -> float:
	var bound := 0.0
	for shape in shapes:
		if shape != null:
			bound = maxf(bound, shape.lipschitz_bound())
	return bound


func bounds() -> AABB:
	# Q: Why not intersect the children's boxes?
	# A: AABB.intersection() would be tighter; it is left as Tweak T6.
	#    The merged box is larger but never too small.
	return SdfShape.merged_bounds(shapes)


## max(children) <= level only where every child is <= level.
func level_bounds(level: float) -> AABB:
	return SdfShape.merged_level_bounds(shapes, level)
