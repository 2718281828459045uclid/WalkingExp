@tool
class_name HeightField
extends Resource
## A terrain described as the graph of a function: y = h(x, z).
##
## This file holds math only. It knows nothing about meshes or rendering.
## terrain.gd asks it two questions at each grid point:
##   height(p)   -> how high is the ground here?
##   gradient(p) -> how fast does the height change as I step in x and in z?
##
## Convention: functions take a Vector2 p where p.x is world x and
## p.y is world z. Vector2 has no ".z", so the second slot carries z.
## All distances are in meters.
##
## Because this is a Resource, its values live in a .tres file under
## game/data/. Editing that file (or the Inspector) changes the terrain
## without touching code. Each setter calls emit_changed(), and
## terrain.gd listens for that signal to rebuild the mesh.

@export_group("Tilt")
## Constant slope of the whole terrain: rise per meter along x and along z.
@export var tilt: Vector2 = Vector2(0.04, -0.02):
	set(value):
		tilt = value
		emit_changed()

@export_group("Mound")
## Peak height of the central Gaussian hill, in meters.
@export var mound_height: float = 12.0:
	set(value):
		mound_height = value
		emit_changed()
## Standard deviation (sigma) of the hill, in meters. Larger means wider.
@export_range(1.0, 200.0) var mound_radius: float = 22.0:
	set(value):
		mound_radius = value
		emit_changed()

@export_group("Ripples")
## Amplitude of the sinusoidal ripples, in meters.
@export var ripple_amplitude: float = 1.4:
	set(value):
		ripple_amplitude = value
		emit_changed()
## Wavelength of the ripples along x and along z, in meters.
@export var ripple_wavelength: Vector2 = Vector2(23.0, 17.0):
	set(value):
		ripple_wavelength = value
		emit_changed()


func height(p: Vector2) -> float:
	var plane := tilt.dot(p)

	var sigma_sq := mound_radius * mound_radius
	var mound := mound_height * exp(-p.length_squared() / (2.0 * sigma_sq))

	var k := _wave_numbers()
	var ripples := ripple_amplitude * sin(k.x * p.x) * cos(k.y * p.y)

	return plane + mound + ripples


## Returns (dh/dx, dh/dz): the partial derivatives of height().
##
## Q: Why write these by hand instead of estimating them numerically?
## A: The hand-derived version is exact and costs one evaluation.
##    A numerical estimate needs extra height() calls and carries error
##    that depends on the step size. Lesson 01 compares the two.
##
## Q: How do I check that this function matches height()?
## A: Compare it against a finite-difference estimate at many random
##    points. If the two disagree, one of the derivatives is wrong.
##    (Lesson 01, exercise 1, asks you to write that check.)
func gradient(p: Vector2) -> Vector2:
	# The derivative of a sum is the sum of the derivatives,
	# so each term contributes its own gradient.

	# d/dx (a*x + b*z) = a,  d/dz (a*x + b*z) = b
	var d_plane := tilt

	# Chain rule on A * exp(-|p|^2 / (2 sigma^2)):
	# the inner function has gradient -p / sigma^2,
	# so the whole term has gradient (A * exp(...)) * (-p / sigma^2).
	var sigma_sq := mound_radius * mound_radius
	var mound := mound_height * exp(-p.length_squared() / (2.0 * sigma_sq))
	var d_mound := mound * (-p / sigma_sq)

	# Product rule on R * sin(kx * x) * cos(kz * z).
	var k := _wave_numbers()
	var d_ripples := Vector2(
		ripple_amplitude * k.x * cos(k.x * p.x) * cos(k.y * p.y),
		-ripple_amplitude * k.y * sin(k.x * p.x) * sin(k.y * p.y)
	)

	return d_plane + d_mound + d_ripples


## Unit surface normal at p, derived from the gradient.
##
## Q: Where does (-dh/dx, 1, -dh/dz) come from?
## A: The surface is f(x, z) = (x, h(x, z), z). Its two tangent vectors are
##      df/dx = (1, dh/dx, 0)
##      df/dz = (0, dh/dz, 1)
##    The cross product df/dz x df/dx = (-dh/dx, 1, -dh/dz) is perpendicular
##    to both, and its y component is positive, so it points up.
##    Work the cross product out on paper once to confirm.
func normal(p: Vector2) -> Vector3:
	var g := gradient(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## Converts wavelength (meters per cycle) to angular wave number (radians per meter).
func _wave_numbers() -> Vector2:
	return Vector2(TAU / ripple_wavelength.x, TAU / ripple_wavelength.y)
