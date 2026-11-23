extends SceneTree
## Lesson 02: checks StickResponse (src/input/stick_response.gd).
##   1. With its default values it reproduces the mapping Lesson 00 used:
##      Input.get_vector() with the action deadzone of 0.15.
##   2. The walking response in data/input/walk_stick_response.tres is zero
##      inside the inner deadzone, 1 beyond the outer deadzone, monotonic,
##      and keeps the stick direction.
##   3. A Curve, when assigned, replaces the power law.
## Run: Godot --headless --path game -s res://tests/test_02_stick_response.gd

var _failures := 0


func _initialize() -> void:
	_check_lesson00_equivalence()
	_check_walk_response()
	_check_curve_override()
	print("test_02_stick_response: %s" % ("passed" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _set_left_stick(x: float, y: float) -> void:
	for axis_and_value in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var event := InputEventJoypadMotion.new()
		event.device = 0
		event.axis = axis_and_value[0]
		event.axis_value = axis_and_value[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check_lesson00_equivalence() -> void:
	var response := StickResponse.new()
	var worst := 0.0
	var samples := 0
	for i in range(-10, 11):
		for j in range(-10, 11):
			_set_left_stick(i / 10.0, j / 10.0)
			var builtin := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
			worst = maxf(worst, builtin.distance_to(response.apply(raw)))
			samples += 1
	_set_left_stick(0.0, 0.0)
	print("  default StickResponse vs Input.get_vector: %d stick positions, largest difference %s" % [samples, String.num_scientific(worst)])
	_expect(worst < 1e-5, "default StickResponse differs from the Lesson 00 mapping by %f" % worst)


func _check_walk_response() -> void:
	var response: StickResponse = load("res://data/input/walk_stick_response.tres")
	_expect(response != null, "data/input/walk_stick_response.tres did not load")
	if response == null:
		return
	_expect(response.shape(response.inner_deadzone) == 0.0, "output at the inner deadzone is not 0")
	_expect(response.shape(response.inner_deadzone * 0.5) == 0.0, "output inside the inner deadzone is not 0")
	_expect(is_equal_approx(response.shape(response.outer_deadzone), 1.0), "output at the outer deadzone is not 1")
	_expect(is_equal_approx(response.shape(1.0), 1.0), "output at full deflection is not 1")

	var previous := 0.0
	var monotonic := true
	for i in 101:
		var value := response.shape(i / 100.0)
		monotonic = monotonic and value >= previous
		previous = value
	_expect(monotonic, "walk response is not monotonic")

	var raw := Vector2(0.3, -0.5)
	var shaped := response.apply(raw)
	_expect(shaped.normalized().is_equal_approx(raw.normalized()), "apply() changed the stick direction")
	_expect(response.apply(Vector2(2.0, 0.0)).is_equal_approx(Vector2(1.0, 0.0)), "apply() does not saturate at length 1")
	print("  walk response: zero inside %.2f, 1 from %.2f, monotonic on 101 samples, direction kept" % [response.inner_deadzone, response.outer_deadzone])


func _check_curve_override() -> void:
	var response := StickResponse.new()
	response.inner_deadzone = 0.0
	response.exponent = 3.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), 0.0, 1.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), 1.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	_expect(is_equal_approx(response.shape(0.5), 0.125), "power law with exponent 3 gives %f at 0.5" % response.shape(0.5))
	response.curve = curve
	_expect(absf(response.shape(0.5) - 0.5) < 1e-3, "a linear Curve gives %f at 0.5" % response.shape(0.5))
	print("  curve override: exponent 3 -> %.3f at 0.5; linear Curve -> %.3f at 0.5" % [0.125, response.shape(0.5)])
