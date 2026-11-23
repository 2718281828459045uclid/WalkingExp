class_name HoldFinder
extends RefCounted
## Finds hand and foot holds on an SDF surface (Lesson 15). Static
## functions only.
##
## How the files relate:
##   CurvatureMesher (Lesson 09)  has measured, at every mesh vertex, the
##                                gradient normal n and the mean curvature H
##   ImplicitCurvature (Lesson 09)  measures one point again: n, H, K, k1, k2
##   this file                    vertices -> candidates -> holds
##   ClimbableRock                runs candidates(), suppress() and
##                                refine() in find_holds() after each
##                                rebuild and keeps the holds in world
##                                space; find() runs the same three stages
##                                in one call, for scratch scripts and tests
##   ClimbController              asks for the holds inside a reach sphere
##
## A hold, in this lesson, is a point of the surface that
##   1. bends outward: min_mean <= H (a bump or an edge, not a flat face
##      and not a hollow),
##   2. is a surface at all: H <= max_mean and |grad f| >= min_gradient
##      (a crease of the field is not; Lesson 09, P5 and O4),
##   3. faces up: n . up >= min_up (a hand can pull down on it and a foot
##      can stand on it), and
##   4. faces the climber: n . face >= min_facing, where face is the
##      outward normal of the climbing face (the back and the sides of
##      the rock are out of reach).
## README section 2 (P1-P4) derives the tests.


## What a hold feels like under the hand, from the principal curvatures.
enum Kind {
	KNOB,  ## Both principal curvatures large: a bump to pinch or wrap.
	EDGE,  ## One large, one near zero (or negative): an edge to crimp.
}

const KIND_NAMES: PackedStringArray = ["knob", "edge"]


## The thresholds of the four tests and of the clean-up.
class Criteria:
	## Smallest mean curvature, 1/m. 3 /m is a sphere of radius 0.33 m.
	var min_mean := 3.0
	## Largest mean curvature, 1/m. Above it the point is a crease.
	var max_mean := 40.0
	## Smallest |grad f| after refinement. A distance field has 1.
	var min_gradient := 0.5
	## Smallest upward component of the normal.
	var min_up := 0.3
	## Outward normal of the climbing face; ZERO disables the test.
	var face := Vector3.ZERO
	## Smallest component of the normal along face.
	var min_facing := -1.0
	## Smallest distance between two holds, meters.
	var spacing := 0.2
	## k2 / k1 at or above this ratio makes a KNOB, below it an EDGE.
	var knob_ratio := 0.25


## One hold. Positions and normals are in the frame the caller chose
## (shape space in find() and ClimbableRock.local_holds, world space in
## ClimbableRock.holds).
class Hold:
	var position := Vector3.ZERO
	var normal := Vector3.UP
	## Mean curvature H, 1/m (H = 1/r on a sphere of radius r).
	var mean := 0.0
	## Gaussian curvature K, 1/m^2, and the principal curvatures k1 >= k2.
	var gaussian := 0.0
	var k1 := 0.0
	var k2 := 0.0
	## |grad f| at the hold (1 on an exact distance field).
	var gradient_length := 1.0
	## H times the upward part of the normal: larger is a better hold.
	var score := 0.0
	var kind := Kind.KNOB
	## Whether the top of the rock lies just behind the hold (a mantle).
	var top_out := false
	## True for a contact on the ground, not on the rock.
	var on_ground := false


## The vertex tests 1, 2 (H <= max_mean only), 3 and 4. The gradient half
## of test 2 needs a new measurement and waits for refine().
static func passes(mean: float, normal: Vector3, criteria: Criteria) -> bool:
	if mean < criteria.min_mean or mean > criteria.max_mean:
		return false
	if normal.y < criteria.min_up:
		return false
	return criteria.face == Vector3.ZERO or normal.dot(criteria.face) >= criteria.min_facing


## Candidates from per-vertex data: every vertex that passes the tests.
## Returns the candidates sorted by score, best first.
static func candidates(positions: PackedVector3Array, normals: PackedVector3Array,
		means: PackedFloat32Array, criteria: Criteria) -> Array[Hold]:
	var result: Array[Hold] = []
	for i in positions.size():
		if not passes(means[i], normals[i], criteria):
			continue
		var hold := Hold.new()
		hold.position = positions[i]
		hold.normal = normals[i]
		hold.mean = means[i]
		hold.score = score(means[i], normals[i])
		result.append(hold)
	result.sort_custom(func(a: Hold, b: Hold) -> bool: return a.score > b.score)
	return result


## The score of a hold: H (n . up).
##
## Q: Why multiply?
## A: A sharp edge that faces sideways is a poor hold, and so is a flat
##    ledge. The product is large only when both are large, and zero when
##    either is zero.
static func score(mean: float, normal: Vector3) -> float:
	return mean * maxf(normal.y, 0.0)


## Keeps the best candidate of each neighborhood (non-maximum suppression).
## `sorted` must be sorted best first, as candidates() returns it.
##
## Q: Why is one bump many candidates?
## A: Every mesh vertex on the top of a bump passes the tests. A hand
##    needs one point per bump. Walking the list from the best score
##    down and dropping every candidate within `spacing` of a kept one
##    leaves the best point of each bump. The cost is O(candidates x kept).
static func suppress(sorted: Array[Hold], spacing: float) -> Array[Hold]:
	var kept: Array[Hold] = []
	var spacing_squared := spacing * spacing
	for hold in sorted:
		var crowded := false
		for other in kept:
			if hold.position.distance_squared_to(other.position) < spacing_squared:
				crowded = true
				break
		if not crowded:
			kept.append(hold)
	return kept


## Moves a hold onto the zero set of the field, measures it again and
## tests it again. Returns false when the hold fails at the new point.
##
## Q: How does a point near the surface find the surface?
## A: One Newton step for f(p) = 0 along the gradient:
##      p <- p - f(p) g / |g|^2
##    For an exact distance |g| = 1 and the step is the distance itself.
##    Two steps bring a mesh vertex (within a cell of the surface) to
##    within rounding of it.
## Q: Why test |grad f| here and not at the vertex?
## A: CurvatureMesher keeps only the normalized gradient. The sample below
##    has the gradient itself. Where two shapes of a union or an
##    intersection meet, the central differences straddle a kink and the
##    gradient shrinks (Lesson 09 measured 1.2e-5); the "curvature" there
##    is a number without a surface behind it.
static func refine(shape: SdfShape, hold: Hold, criteria: Criteria, steps: int = 2) -> bool:
	var p := hold.position
	for i in steps:
		var g := shape.gradient(p)
		var len2 := g.length_squared()
		if len2 < 1e-12:
			return false
		p -= g * (shape.evaluate(p) / len2)
	var s := ImplicitCurvature.sample(shape, p)
	hold.position = p
	hold.normal = s.normal
	hold.mean = s.mean
	hold.gaussian = s.gaussian
	hold.k1 = s.k1
	hold.k2 = s.k2
	hold.gradient_length = s.gradient.length()
	hold.score = score(s.mean, s.normal)
	hold.kind = classify(s.k1, s.k2, criteria.knob_ratio)
	return hold.gradient_length >= criteria.min_gradient and passes(s.mean, s.normal, criteria)


## KNOB when the smaller principal curvature is at least knob_ratio of
## the larger one, EDGE otherwise.
##
## Q: Why do the principal curvatures tell a knob from an edge?
## A: On a sphere of radius r, k1 = k2 = 1/r: the surface bends away in
##    every direction, and a hand can wrap it. Along the rounded edge of a
##    box, k1 = 1/r across the edge and k2 = 0 along it: a line to hook
##    the fingers on. K = k1 k2 is positive on the first and zero on the
##    second (DDG section 3.4.1).
static func classify(k1: float, k2: float, knob_ratio: float) -> Kind:
	if k1 > 0.0 and k2 >= knob_ratio * k1:
		return Kind.KNOB
	return Kind.EDGE


## All three stages: candidates, suppression, refinement. Holds that fail
## after refinement are dropped. ClimbableRock does not call this: it runs
## the stages itself and tests each refined hold for a top-out. Scratch
## scripts (exercise E2) and the tests use it.
static func find(shape: SdfShape, positions: PackedVector3Array, normals: PackedVector3Array,
		means: PackedFloat32Array, criteria: Criteria) -> Array[Hold]:
	var kept: Array[Hold] = []
	for hold in suppress(candidates(positions, normals, means, criteria), criteria.spacing):
		if refine(shape, hold, criteria):
			kept.append(hold)
	return kept


## The holds inside a reach sphere, nearest to `aim` first.
##   center, radius   the sphere: a shoulder or a hip and the limb's reach
##   exclude          holds already in use
static func in_reach(holds: Array[Hold], center: Vector3, radius: float,
		aim: Vector3, exclude: Array = []) -> Array[Hold]:
	var result: Array[Hold] = []
	for hold in holds:
		if hold in exclude:
			continue
		if hold.position.distance_to(center) <= radius:
			result.append(hold)
	result.sort_custom(func(a: Hold, b: Hold) -> bool:
		return a.position.distance_squared_to(aim) < b.position.distance_squared_to(aim))
	return result
