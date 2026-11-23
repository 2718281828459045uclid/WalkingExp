extends SceneTree
## Lesson 10: checks SphereTracer (src/sdf/sphere_tracer.gd), the CPU copy
## of the shader's march loop.
##   1. A head-on ray at a sphere hits at the closed-form distance, in two
##      steps (an exact SDF jumps straight to the surface).
##   2. A ray that passes the sphere misses.
##   3. A field scaled by 2 (Lipschitz bound 2) tunnels through a thin
##      sphere when stepped by f, and hits when stepped by f / 2.
##   4. box_interval() returns the slab-test interval and reports misses.
## Run: Godot --headless --path game -s res://tests/test_10_sphere_tracer.gd

var _failures := 0


## A sphere whose field is twice the distance: same zero set, L = 2.
class DoubledSphere extends SdfShape:
	var radius := 0.25

	func evaluate(p: Vector3) -> float:
		return 2.0 * (p.length() - radius)

	func lipschitz_bound() -> float:
		return 2.0


func _initialize() -> void:
	var sphere := SdfSphere.new()
	sphere.radius = 1.0

	# 1. Head-on hit.
	var hit := SphereTracer.trace(sphere, Vector3(0, 0, 5), Vector3(0, 0, -1), 64, 1e-4, 0.0, 10.0)
	_expect(hit.hit, "head-on ray hits")
	_expect(absf(hit.t - 4.0) < 1e-4, "t = %f, expected 4" % hit.t)
	_expect(hit.steps == 2, "steps %d, expected 2" % hit.steps)

	# 2. Miss.
	var miss := SphereTracer.trace(sphere, Vector3(0, 1.5, 5), Vector3(0, 0, -1), 64, 1e-4, 0.0, 10.0)
	_expect(not miss.hit, "offset ray misses")

	# 3. Lipschitz bound.
	var doubled := DoubledSphere.new()
	var careless := SphereTracer.trace(doubled, Vector3(0, 0, 5), Vector3(0, 0, -1), 64, 1e-4, 0.0, 10.0, 1.0)
	_expect(not careless.hit, "stepping by f tunnels through (t = %f)" % careless.t)
	var careful := SphereTracer.trace(doubled, Vector3(0, 0, 5), Vector3(0, 0, -1), 64, 1e-4, 0.0, 10.0, doubled.lipschitz_bound())
	_expect(careful.hit and absf(careful.t - 4.75) < 1e-3, "stepping by f / L hits at 4.75 (t = %f)" % careful.t)

	# 4. Box interval.
	var box := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var span := SphereTracer.box_interval(box, Vector3(0, 0, 5), Vector3(0, 0, -1))
	_expect(span.is_equal_approx(Vector2(4, 6)), "interval %s, expected (4, 6)" % span)
	var inside := SphereTracer.box_interval(box, Vector3.ZERO, Vector3(1, 0, 0))
	_expect(inside.is_equal_approx(Vector2(-1, 1)), "from inside %s, expected (-1, 1)" % inside)
	var outside := SphereTracer.box_interval(box, Vector3(0, 3, 5), Vector3(0, 0, -1))
	_expect(outside.x > outside.y, "a ray beside the box misses it: %s" % outside)

	print("test_10_sphere_tracer: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
