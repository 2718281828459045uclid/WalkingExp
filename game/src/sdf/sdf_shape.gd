@tool
class_name SdfShape
extends Resource
## Base class of every signed distance function (SDF) in this project.
##
## An SDF answers one question about a point p in 3D space:
##   evaluate(p) -> how far is p from the surface?
## The answer is negative inside the solid, zero on the surface, and
## positive outside. Lesson 07 builds boulders from these functions;
## Lesson 08 turns the zero set { p : evaluate(p) = 0 } into a mesh.
##
## How the files relate:
##   sdf_shape.gd          this file: the API every shape shares
##   sdf_sphere.gd, sdf_box.gd, sdf_ellipsoid.gd, sdf_capsule.gd
##                         primitives: closed-form distance functions
##   sdf_union.gd, sdf_smooth_union.gd, sdf_intersection.gd,
##   sdf_subtraction.gd    operators that combine child shapes
##   sdf_transform.gd, sdf_repeat.gd
##                         operators that move the point before asking a child
##   sdf_displace.gd       adds noise to a child's distance
##   sdf_slice.gd          a Node3D that draws one plane of any SdfShape
## Operators hold their children as exported SdfShape properties, so a
## boulder is a tree of Resources saved in one .tres file (data/rocks/).
##
## Units are meters. Points use Vector3 (32-bit floats); distances are
## float (64-bit). Each shape lives in its own "shape space"; the node
## that draws or meshes it decides where shape space sits in the world.


## Signed distance from p to the surface. Subclasses override this.
func evaluate(_p: Vector3) -> float:
	push_error("%s does not override evaluate()" % resource_path)
	return INF


## An upper bound L on how fast evaluate() can change:
##   |evaluate(a) - evaluate(b)| <= L * |a - b|   for all a, b.
## An exact distance function has L = 1. Subclasses that stretch or add
## to the field report a larger value.
func lipschitz_bound() -> float:
	return 1.0


## A box that contains the whole solid (every p with evaluate(p) <= 0).
## Lesson 08 samples only inside this box.
func bounds() -> AABB:
	return AABB()


## A box that contains every p with evaluate(p) <= level, for level >= 0.
## Operators that lower or offset a child's field (smooth union,
## displacement) ask their children for this box instead of bounds().
##
## Q: Why is bounds().grow(level) enough here?
## A: For an exact distance, evaluate(p) <= level means p lies within
##    `level` meters of the solid, so within `level` of its box. A field
##    that underestimates the distance (SdfEllipsoid) reaches `level`
##    farther out and overrides this method.
func level_bounds(level: float) -> AABB:
	return bounds().grow(level)


## evaluate(p) divided by the Lipschitz bound.
##
## Q: Why divide?
## A: If |f(a) - f(b)| <= L |a - b|, then f(p) / L never exceeds the true
##    distance to the zero set. A value that never overestimates is safe
##    to step by (Lesson 10, sphere tracing), even when f is not exact.
func evaluate_bounded(p: Vector3) -> float:
	return evaluate(p) / lipschitz_bound()


## Gradient by central differences, step h in meters.
##
## Q: Why the default h = 1e-3 and not something much smaller?
## A: p is a Vector3 of 32-bit floats. Near |p| = 10 m the spacing of
##    32-bit numbers is about 1e-6 m. With h = 1e-6 the difference
##    p + h - p would be rounding noise. 1e-3 m keeps that error near
##    1e-3 relative while the truncation error (order h^2) stays small.
func gradient(p: Vector3, h: float = 1e-3) -> Vector3:
	var dx := evaluate(p + Vector3(h, 0, 0)) - evaluate(p - Vector3(h, 0, 0))
	var dy := evaluate(p + Vector3(0, h, 0)) - evaluate(p - Vector3(0, h, 0))
	var dz := evaluate(p + Vector3(0, 0, h)) - evaluate(p - Vector3(0, 0, h))
	return Vector3(dx, dy, dz) / (2.0 * h)


## Re-emits `changed` when a child shape changes, so a drawing of the
## parent (sdf_slice.gd) rebuilds when any part of the tree is edited.
## Operators call this from their setters.
func _watch(old_child: Resource, new_child: Resource) -> void:
	if old_child != null and old_child.changed.is_connected(emit_changed):
		old_child.changed.disconnect(emit_changed)
	if new_child != null and not new_child.changed.is_connected(emit_changed):
		new_child.changed.connect(emit_changed)


## Same as _watch() for an array of children.
func _watch_all(old_children: Array, new_children: Array) -> void:
	for child in old_children:
		_watch(child, null)
	for child in new_children:
		_watch(null, child)


## Union of the bounds of an array of shapes (empty shapes skipped).
static func merged_level_bounds(shapes: Array, level: float) -> AABB:
	var box := AABB()
	var first := true
	for shape in shapes:
		if shape == null:
			continue
		var b: AABB = shape.level_bounds(level)
		box = b if first else box.merge(b)
		first = false
	return box


static func merged_bounds(shapes: Array) -> AABB:
	var box := AABB()
	var first := true
	for shape in shapes:
		if shape == null:
			continue
		var b: AABB = shape.bounds()
		box = b if first else box.merge(b)
		first = false
	return box
