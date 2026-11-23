class_name SphereTracer
extends RefCounted
## Sphere tracing on the CPU (Lesson 10): the loop of
## shaders/sdf/raymarch.gdshader, written in GDScript.
##
## The shader is the one that draws. This copy exists to be read, tested and
## measured step by step: a fragment shader cannot print its step count, a
## GDScript function can. tests/test_10_sphere_tracer.gd checks it on shapes
## whose hit distance is known in closed form.


## The outcome of one trace.
class Result:
	var hit := false
	## Distance along the (unit) direction where the march stopped.
	var t := 0.0
	## Number of field evaluations made.
	var steps := 0
	## The field value at the last point, divided by the Lipschitz bound.
	var last_value := 0.0


## Marches from `origin` along the unit vector `direction`.
##   t_start, t_end   the part of the ray to search (the proxy box interval)
##   tolerance        epsilon per meter of distance: the march stops when
##                    f / L < tolerance * t (the shader's epsilon_pixels *
##                    pixel_angle); a fixed floor keeps t = 0 meaningful
static func trace(shape: SdfShape, origin: Vector3, direction: Vector3,
		max_steps: int, tolerance: float, t_start: float, t_end: float,
		lipschitz: float = 1.0, floor_tolerance: float = 1e-5) -> Result:
	var result := Result.new()
	var t := t_start
	for i in max_steps:
		var d := shape.evaluate(origin + direction * t) / lipschitz
		result.steps = i + 1
		result.last_value = d
		if d < maxf(tolerance * t, floor_tolerance):
			result.hit = true
			break
		t += d
		if t > t_end:
			break
	result.t = t
	return result


## The slab test of the shader's box_interval(): (t_enter, t_exit) of the
## ray inside `box`. t_enter > t_exit means the ray misses the box.
static func box_interval(box: AABB, origin: Vector3, direction: Vector3) -> Vector2:
	var t_enter := -INF
	var t_exit := INF
	for axis in 3:
		if direction[axis] == 0.0:
			# Q: Why test a zero component before dividing?
			# A: The ray is parallel to this slab. It is inside the slab for
			#    every t or for none. Dividing would give +-inf, or NaN (0/0)
			#    when the origin lies on a face, and NaN spoils min and max.
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]:
				return Vector2(INF, -INF)
			continue
		var t0 := (box.position[axis] - origin[axis]) / direction[axis]
		var t1 := (box.end[axis] - origin[axis]) / direction[axis]
		t_enter = maxf(t_enter, minf(t0, t1))
		t_exit = minf(t_exit, maxf(t0, t1))
	return Vector2(t_enter, t_exit)
