@tool
class_name SdfCapsule
extends SdfShape
## Capsule: points within `radius` of the segment from a to b. Exact, L = 1.

@export var a: Vector3 = Vector3(0, -0.5, 0):
	set(value):
		a = value
		emit_changed()
@export var b: Vector3 = Vector3(0, 0.5, 0):
	set(value):
		b = value
		emit_changed()
@export var radius: float = 0.5:
	set(value):
		radius = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	var ap := p - a
	var ab := b - a
	# Q: Which point of the segment is nearest to p?
	# A: Project ap onto ab and clamp the parameter to [0, 1]: the
	#    projection may fall beyond an end, and then the end is nearest.
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (ap - ab * t).length() - radius


func bounds() -> AABB:
	var low := a.min(b) - Vector3.ONE * radius
	var high := a.max(b) + Vector3.ONE * radius
	return AABB(low, high - low)
