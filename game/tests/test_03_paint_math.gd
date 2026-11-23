extends SceneTree
## Lesson 03: checks PaintMath (src/render/paint_math.gd), the CPU copies
## of the shader formulas.
##   1. srgb_to_linear() and linear_to_srgb() agree with Godot's Color
##      conversions and invert each other.
##   2. triplanar_weights() sums to 1; with sharpness 4 the side weight is
##      0.1 at 30 degrees, 0.5 at 45 degrees, 0.9 at 60 degrees.
##   3. contour_distance() is 0 on lines and 0.5 between them, also below 0.
## Run: Godot --headless --path game -s res://tests/test_03_paint_math.gd

var _failures := 0


func _initialize() -> void:
	for i in 256:
		var c := i / 255.0
		var expected_linear := Color(c, c, c).srgb_to_linear().r
		_expect(absf(PaintMath.srgb_to_linear(c) - expected_linear) < 1e-5,
				"srgb_to_linear(%.4f) = %.6f, Color gives %.6f" % [c, PaintMath.srgb_to_linear(c), expected_linear])
		var expected_srgb := Color(c, c, c).linear_to_srgb().r
		_expect(absf(PaintMath.linear_to_srgb(c) - expected_srgb) < 1e-5,
				"linear_to_srgb(%.4f) = %.6f, Color gives %.6f" % [c, PaintMath.linear_to_srgb(c), expected_srgb])
		_expect(absf(PaintMath.linear_to_srgb(PaintMath.srgb_to_linear(c)) - c) < 1e-9, "round trip fails at %.4f" % c)
	_expect(absf(PaintMath.srgb_to_linear(0.5) - 0.2140) < 1e-4, "sRGB 0.5 should decode to 0.2140")

	for degrees_and_weight in [[30.0, 0.1], [45.0, 0.5], [60.0, 0.9]]:
		var a := deg_to_rad(degrees_and_weight[0])
		var w := PaintMath.triplanar_weights(Vector3(sin(a), cos(a), 0.0), 4.0)
		_expect(absf(w.x - degrees_and_weight[1]) < 1e-6, "side weight at %.0f degrees is %.6f" % [degrees_and_weight[0], w.x])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var w := PaintMath.triplanar_weights(n, rng.randf_range(1.0, 16.0))
		# Vector3 holds 32-bit floats, so the sum is exact to about 1e-7, not 1e-15.
		_expect(absf(w.x + w.y + w.z - 1.0) < 1e-6, "weights of %s sum to %.9f" % [n, w.x + w.y + w.z])

	for case in [[3.0, 1.0, 0.0], [3.5, 1.0, 0.5], [3.25, 1.0, 0.25], [-0.25, 1.0, 0.25], [-2.0, 1.0, 0.0], [7.5, 5.0, 0.5], [9.0, 2.0, 0.5]]:
		var d := PaintMath.contour_distance(case[0], case[1])
		_expect(absf(d - case[2]) < 1e-9, "contour_distance(%.2f, %.1f) = %.6f, expected %.2f" % [case[0], case[1], d, case[2]])
	_expect(PaintMath.contour_index(-0.5, 1.0) == -1, "contour_index(-0.5, 1) should be -1")
	_expect(PaintMath.contour_index(7.9, 2.0) == 3, "contour_index(7.9, 2) should be 3")

	print("test_03_paint_math: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
