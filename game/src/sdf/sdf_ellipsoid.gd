@tool
class_name SdfEllipsoid
extends SdfShape
## Ellipsoid with semi-axes `radii`, turned by `rotation_degrees`.
##
## An ellipsoid has no closed-form distance function: the nearest point
## on its surface is a root of a sixth-degree polynomial. This script
## offers two cheap estimates instead (Lesson 07, P4 and section 3.2):
##   SCALED_SPHERE  (k0 - 1) * min(radii)            the default
##   GRADIENT       g / |grad g|, with g = k0 - 1     (Inigo Quilez's estimate)
## where k0 = |q / radii| and q is p in the ellipsoid's own frame.
## Both are zero on the surface and nowhere else and have the right sign.
## SCALED_SPHERE never overestimates the distance and has Lipschitz
## bound 1. GRADIENT is closer to the true distance near the surface but
## overestimates the depth inside and has no finite Lipschitz bound: it
## jumps at the center (Lesson 07, O4).

enum Estimate { SCALED_SPHERE, GRADIENT }

@export var center: Vector3 = Vector3.ZERO:
	set(value):
		center = value
		emit_changed()
@export var radii: Vector3 = Vector3(1.5, 1.0, 1.2):
	set(value):
		radii = value
		emit_changed()
## Euler angles in degrees (Godot's YXZ order), applied about `center`.
@export var rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		rotation_degrees = value
		_to_local = Basis.from_euler(rotation_degrees * (PI / 180.0)).inverse()
		emit_changed()
@export var estimate: Estimate = Estimate.SCALED_SPHERE:
	set(value):
		estimate = value
		emit_changed()

# World-to-ellipsoid rotation, cached so evaluate() does not rebuild it.
var _to_local := Basis.IDENTITY


func evaluate(p: Vector3) -> float:
	var q := _to_local * (p - center)
	# k0 = 1 on the surface, < 1 inside, > 1 outside. It is the "radius"
	# of q after squashing the ellipsoid into the unit sphere.
	var k0 := (q / radii).length()

	if estimate == Estimate.SCALED_SPHERE:
		# Q: Why multiply by the smallest radius?
		# A: Squashing by 1/radii stretches distances by at most
		#    1/min(radii). (k0 - 1) is a distance in the squashed space,
		#    so (k0 - 1) * min(radii) never overestimates outside.
		#    It is exact for a sphere and poor for flat ellipsoids.
		return (k0 - 1.0) * minf(radii.x, minf(radii.y, radii.z))

	# Q: Where does k0 * (k0 - 1) / k1 come from?
	# A: Take g(q) = k0 - 1, zero on the surface. Near the surface a
	#    function changes by about |grad g| per meter, so the distance
	#    to its zero set is about g / |grad g|. Differentiating
	#    k0 = |q / radii| gives grad g = (q / radii^2) / k0, whose length
	#    is k1 / k0 with k1 = |q / radii^2|. Then g / |grad g| =
	#    (k0 - 1) * k0 / k1.
	var k1 := (q / (radii * radii)).length()
	# Q: What happens at the center, where q = 0?
	# A: k0 and k1 are both 0 and the ratio is undefined. The depth
	#    there is the smallest radius, so return that.
	if k1 < 1e-9:
		return -minf(radii.x, minf(radii.y, radii.z))
	return k0 * (k0 - 1.0) / k1


## Q: Why INF for GRADIENT?
## A: Near the center the estimate tends to -radii.x along x and to
##    -radii.y along y. Two points 1 mm apart can differ by
##    radii.x - radii.y, so no constant L satisfies the Lipschitz
##    inequality. SCALED_SPHERE has L = 1 (Lesson 07, P4).
func lipschitz_bound() -> float:
	return 1.0 if estimate == Estimate.SCALED_SPHERE else INF


func bounds() -> AABB:
	# The largest radius bounds the ellipsoid in every rotation.
	var r := maxf(radii.x, maxf(radii.y, radii.z))
	return AABB(center - Vector3.ONE * r, Vector3.ONE * 2.0 * r)


## Q: How far out can the field still be below `level`?
## A: Outside the ellipsoid both estimates are at least
##    (k0 - 1) * min(radii) (for GRADIENT, k1 <= k0 / min(radii)).
##    So f <= level forces k0 <= 1 + level / min(radii): the point lies in
##    the ellipsoid scaled by that factor, whose largest radius is
##    max(radii) * (1 + level / min(radii)). The growth is
##    level * max / min, not level: the estimate underestimates distance.
func level_bounds(level: float) -> AABB:
	var small := minf(radii.x, minf(radii.y, radii.z))
	var large := maxf(radii.x, maxf(radii.y, radii.z))
	if small <= 0.0:
		return bounds()
	return bounds().grow(level * large / small)
