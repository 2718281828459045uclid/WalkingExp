@tool
class_name SdfSphere
extends SdfShape
## Sphere: the set of points at distance <= radius from center.
## Exact: evaluate(p) is the true signed distance, L = 1.

@export var center: Vector3 = Vector3.ZERO:
	set(value):
		center = value
		emit_changed()
@export var radius: float = 1.0:
	set(value):
		radius = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	return (p - center).length() - radius


func bounds() -> AABB:
	return AABB(center - Vector3.ONE * radius, Vector3.ONE * 2.0 * radius)
