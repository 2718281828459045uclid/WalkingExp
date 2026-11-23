@tool
class_name SdfTransform
extends SdfShape
## Moves, turns, and scales a child shape.
##
## Q: To move a shape by +t, why does evaluate() subtract t from p?
## A: The child only knows its own space. Asking "how far is p from the
##    moved shape?" is the same as asking "how far is (p - t) from the
##    unmoved shape?". Every domain operator works this way: it applies
##    the inverse transform to the point, never the forward transform
##    to the shape.

@export var shape: SdfShape:
	set(value):
		_watch(shape, value)
		shape = value
		emit_changed()
@export var translation: Vector3 = Vector3.ZERO:
	set(value):
		translation = value
		_update_transform()
@export var rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		rotation_degrees = value
		_update_transform()
## Uniform scale. A non-uniform scale would bend distances (P6).
@export var scale: float = 1.0:
	set(value):
		scale = value
		_update_transform()

var _forward := Transform3D.IDENTITY
var _inverse := Transform3D.IDENTITY


func _update_transform() -> void:
	var basis := Basis.from_euler(rotation_degrees * (PI / 180.0)).scaled(Vector3.ONE * scale)
	_forward = Transform3D(basis, translation)
	_inverse = _forward.affine_inverse()
	emit_changed()


func evaluate(p: Vector3) -> float:
	if shape == null:
		return INF
	# Q: Why multiply by scale at the end?
	# A: The child measures distance in its own units. A shape scaled by
	#    s is s times larger, so its distances are s times longer.
	return shape.evaluate(_inverse * p) * scale


func lipschitz_bound() -> float:
	return 1.0 if shape == null else shape.lipschitz_bound()


func bounds() -> AABB:
	return AABB() if shape == null else _forward * shape.bounds()


## f = child * scale, so f <= level where child <= level / scale.
func level_bounds(level: float) -> AABB:
	if shape == null or scale <= 0.0:
		return bounds()
	return _forward * shape.level_bounds(level / scale)
