@tool
class_name SdfBox
extends SdfShape
## Axis-aligned box with optional rounded edges. Exact, L = 1.
## Formula after Inigo Quilez, "distance functions".

@export var center: Vector3 = Vector3.ZERO:
	set(value):
		center = value
		emit_changed()
## Half the size along x, y, z (meters), rounding included.
@export var half_extents: Vector3 = Vector3.ONE:
	set(value):
		half_extents = value
		emit_changed()
## Radius of the rounded edges and corners. 0 gives sharp edges.
@export var rounding: float = 0.0:
	set(value):
		rounding = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	# Q: Why abs()?
	# A: The box is symmetric about its center in x, y and z, so every
	#    point can be folded into the positive octant first.
	#    q then measures how far past each face the point lies
	#    (negative: still behind that face).
	var q := (p - center).abs() - (half_extents - Vector3.ONE * rounding)

	# Q: Why two terms?
	# A: Outside: only the faces the point is past count, so clamp q at 0
	#    and take the length (face, edge, or corner distance in one line).
	#    Inside: every q component is negative; the nearest face is the
	#    one with the largest (least negative) q. One of the two terms is
	#    always zero.
	var outside := q.max(Vector3.ZERO).length()
	var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

	# Subtracting a constant moves the zero set outward by that much:
	# a sharp box of size (half_extents - rounding) grown by `rounding`.
	return outside + inside - rounding


func bounds() -> AABB:
	return AABB(center - half_extents, half_extents * 2.0)
