@tool
class_name SdfTorus
extends SdfShape
## Torus around the y axis through `center` (Lesson 09).
##
## The tube's center line is a circle of radius major_radius (R) in the
## plane y = center.y; the tube has radius minor_radius (r). Exact, L = 1.
##
## Lesson 09 uses the torus as a test surface: its curvature is known in
## closed form and changes sign (outer side K > 0, inner side K < 0), so
## it checks the numerical curvature of ImplicitCurvature where a sphere
## (K constant) cannot.

@export var center: Vector3 = Vector3.ZERO:
	set(value):
		center = value
		emit_changed()
@export var major_radius: float = 1.0:
	set(value):
		major_radius = value
		emit_changed()
@export var minor_radius: float = 0.25:
	set(value):
		minor_radius = value
		emit_changed()


## Q: How far is p from the tube?
## A: Measure in the half-plane through the y axis and p. There, p has
##    coordinates (rho, y) with rho = distance from the axis, and the tube
##    is a disk of radius r around (R, 0). The distance to a disk is the
##    distance to its center minus r.
func evaluate(p: Vector3) -> float:
	var q := p - center
	var rho := Vector2(q.x, q.z).length()
	return Vector2(rho - major_radius, q.y).length() - minor_radius


## The gradient of evaluate() by the chain rule, without differences.
##
## Q: What is the derivative of rho = sqrt(x^2 + z^2)?
## A: (x / rho, 0, z / rho): the unit vector pointing away from the axis.
##    With d = |(rho - R, y)|, f = d - r gives
##      df/dx = (rho - R) / d * x / rho,  df/dy = y / d,
##      df/dz = (rho - R) / d * z / rho.
##    rho = 0 (on the axis) and d = 0 (on the core circle) have no
##    gradient; this function returns ZERO there.
func analytic_gradient(p: Vector3) -> Vector3:
	var q := p - center
	var rho := Vector2(q.x, q.z).length()
	var d := Vector2(rho - major_radius, q.y).length()
	if rho == 0.0 or d == 0.0:
		return Vector3.ZERO
	var radial := (rho - major_radius) / d
	return Vector3(radial * q.x / rho, q.y / d, radial * q.z / rho)


func bounds() -> AABB:
	var reach := major_radius + minor_radius
	var half := Vector3(reach, minor_radius, reach)
	return AABB(center - half, half * 2.0)
