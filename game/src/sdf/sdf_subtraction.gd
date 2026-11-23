@tool
class_name SdfSubtraction
extends SdfShape
## `base` with `cutter` removed: max(d_base, -d_cutter).
##
## Q: Why the minus sign?
## A: Negating an SDF swaps inside and outside: -d_cutter is the field of
##    everything except the cutter. Subtraction is then the intersection
##    of the base with that complement.

@export var base: SdfShape:
	set(value):
		_watch(base, value)
		base = value
		emit_changed()
@export var cutter: SdfShape:
	set(value):
		_watch(cutter, value)
		cutter = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	if base == null:
		return INF
	if cutter == null:
		return base.evaluate(p)
	return maxf(base.evaluate(p), -cutter.evaluate(p))


func lipschitz_bound() -> float:
	var bound := 1.0 if base == null else base.lipschitz_bound()
	if cutter != null:
		bound = maxf(bound, cutter.lipschitz_bound())
	return bound


func bounds() -> AABB:
	return AABB() if base == null else base.bounds()


## max(base, -cutter) <= level only where base <= level.
func level_bounds(level: float) -> AABB:
	return AABB() if base == null else base.level_bounds(level)
