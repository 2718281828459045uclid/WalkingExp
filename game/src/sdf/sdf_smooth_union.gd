@tool
class_name SdfSmoothUnion
extends SdfShape
## Union with a fillet of width `blend` meters where shapes meet.
##
## The children are folded left to right:
##   d = smin(smin(d0, d1), d2) ...
## so the result can depend on the order when three shapes meet
## (Lesson 07, Tweak T4).

@export var shapes: Array[SdfShape] = []:
	set(value):
		_watch_all(shapes, value)
		shapes = value
		emit_changed()
## Width k of the blend region in meters. 0 gives the plain union.
@export var blend: float = 0.5:
	set(value):
		blend = value
		emit_changed()


## Quadratic polynomial smooth minimum (Inigo Quilez, "smooth minimum").
##
## Q: What does it do?
## A: Where |a - b| >= k the two distances are far apart and the result
##    is min(a, b). Where they are within k of each other, it subtracts
##    a parabola: h goes from 0 (|a - b| = k) to 1 (a = b), and the
##    subtracted amount h^2 * k / 4 goes from 0 to k / 4.
##
## Q: Why h^2 and not h?
## A: The correction and its first derivative are both 0 at |a - b| = k,
##    so the blended field joins min(a, b) with no crease.
static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


func evaluate(p: Vector3) -> float:
	var d := INF
	for shape in shapes:
		if shape == null:
			continue
		var e := shape.evaluate(p)
		d = e if d == INF else smin(d, e, blend)
	return d


## Q: Does the blend make the field steeper than its children?
## A: No. The partial derivatives of smin with respect to a and b lie in
##    [0, 1] and sum to 1, so the gradient of the result is a weighted
##    average of the children's gradients: its length is at most the
##    largest child bound. Lesson 07, P5.
func lipschitz_bound() -> float:
	var bound := 0.0
	for shape in shapes:
		if shape != null:
			bound = maxf(bound, shape.lipschitz_bound())
	return bound


func bounds() -> AABB:
	return level_bounds(0.0)


## Q: Where can the blended field be below `level`?
## A: Each fold lowers the field by at most blend / 4, so the result is at
##    least min(children) - folds * blend / 4. A point below `level` has
##    some child below level + folds * blend / 4, so it lies in that
##    child's level box. Growing the merged bounds() by blend / 4 is not
##    enough: a child that underestimates distance (a SCALED_SPHERE
##    ellipsoid) reaches that value farther from its box.
func level_bounds(level: float) -> AABB:
	var folds := maxi(shapes.size() - 1, 0)
	return SdfShape.merged_level_bounds(shapes, level + blend * 0.25 * folds)
