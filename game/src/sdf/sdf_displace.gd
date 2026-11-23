@tool
class_name SdfDisplace
extends SdfShape
## Adds noise to a child's distance: d(p) = d_child(p) + amplitude * n(p).
##
## The noise is a FastNoiseLite Resource (data/rocks/granite_noise.tres)
## whose get_noise_3dv() returns values in about [-1, 1]. A positive
## noise value raises the field, which moves the surface inward; a
## negative value moves it outward. The surface therefore shifts by up
## to `amplitude` meters (for a child with L = 1).
##
## Q: What does the noise do to the Lipschitz bound?
## A: If the noise changes by at most S per meter, then
##    |d(a) - d(b)| <= L_child |a - b| + amplitude * S |a - b|,
##    so L = L_child + amplitude * S. S is not printed in the FastNoiseLite
##    documentation; Lesson 07 measures it and stores it in
##    `noise_slope_per_frequency`, the slope per unit of frequency.

@export var shape: SdfShape:
	set(value):
		_watch(shape, value)
		shape = value
		emit_changed()
@export var noise: FastNoiseLite:
	set(value):
		_watch(noise, value)
		noise = value
		emit_changed()
## Largest shift of the surface in meters.
@export var amplitude: float = 0.1:
	set(value):
		amplitude = value
		emit_changed()
## Largest |grad n| divided by noise.frequency, measured by sampling
## (Lesson 07, section 3.4). Used only by lipschitz_bound().
@export var noise_slope_per_frequency: float = 3.0:
	set(value):
		noise_slope_per_frequency = value
		emit_changed()


func evaluate(p: Vector3) -> float:
	if shape == null:
		return INF
	var d := shape.evaluate(p)
	if noise == null:
		return d
	return d + amplitude * noise.get_noise_3dv(p)


func lipschitz_bound() -> float:
	var child := 1.0 if shape == null else shape.lipschitz_bound()
	if noise == null:
		return child
	return child + amplitude * noise_slope_per_frequency * noise.frequency


func bounds() -> AABB:
	return level_bounds(0.0)


## Q: Where can child + amplitude * noise be below `level`?
## A: Noise lies in [-1, 1], so only where the child is below
##    level + amplitude. The child's level box covers that region even
##    when the child underestimates distance; bounds().grow(amplitude)
##    would not.
func level_bounds(level: float) -> AABB:
	return AABB() if shape == null else shape.level_bounds(level + absf(amplitude))
