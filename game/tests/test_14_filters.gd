extends SceneTree
## Lesson 14: checks the input shaping and the two smoothing filters.
##   1. TriggerResponse: zero inside the deadzone, 1 at the outer edge,
##      monotonic in between.
##   2. AxialStickResponse: a stick 10 degrees off forward snaps to forward;
##      on an axis it equals the radial StickResponse; length at most 1.
##   3. OnePoleFilter: 1 - 1/e of a step after tau; the same values at 30,
##      60, 120 and 240 ticks per second.
##   4. CriticalSpring.step(): equals e0 (1 + w t) exp(-w t), never
##      overshoots, the same values at every tick rate.
##   5. CriticalSpring.step_euler(): depends on the tick rate; grows
##      without bound when w dt is above 2 (sqrt 2 - 1).
## Run: Godot --headless --path game -s res://tests/test_14_filters.gd

var _failures := 0


func _initialize() -> void:
	_check_trigger()
	_check_axial()
	_check_one_pole()
	_check_spring()
	_check_euler()
	print("test_14_filters: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_trigger() -> void:
	var response: TriggerResponse = load("res://data/input/trigger_response.tres")
	_expect(response.apply(0.0) == 0.0 and response.apply(response.inner_deadzone) == 0.0, "trigger: zero in the deadzone")
	_expect(is_equal_approx(response.apply(response.outer_deadzone), 1.0) and response.apply(1.0) == 1.0, "trigger: 1 at the outer edge")
	var last := 0.0
	var monotonic := true
	for i in 101:
		var value := response.apply(i / 100.0)
		monotonic = monotonic and value >= last - 1e-6
		last = value
	_expect(monotonic, "trigger: monotonic")
	var linear := TriggerResponse.new()
	_expect(is_equal_approx(linear.apply(0.5), (0.5 - 0.05) / 0.9), "trigger without a curve is linear")


func _check_axial() -> void:
	var radial: StickResponse = load("res://data/input/walk_stick_response.tres")
	var axial: StickResponse = load("res://data/input/walk_stick_axial.tres")
	_expect(axial is AxialStickResponse, "walk_stick_axial.tres is an AxialStickResponse")
	var off := Vector2(sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0))) * 0.5
	_expect(axial.apply(off).x == 0.0 and radial.apply(off).x > 0.0, "10 degrees off forward: axial x is 0, radial x is not")
	var worst := 0.0
	var longest := 0.0
	for i in 21:
		var m := i / 20.0
		worst = maxf(worst, (axial.apply(Vector2(0.0, -m)) - radial.apply(Vector2(0.0, -m))).length())
		longest = maxf(longest, axial.apply(Vector2(m, m)).length())
	_expect(worst < 1e-6, "on an axis axial = radial (difference %s)" % worst)
	_expect(longest <= 1.0 + 1e-6, "axial length at most 1 (%s)" % longest)


func _check_one_pole() -> void:
	var tau := 0.12
	var filter := OnePoleFilter.new(tau)
	for i in 12:
		filter.step(Vector2(1.0, 0.0), 0.01)
	_expect(absf(filter.value.x - (1.0 - exp(-1.0))) < 1e-5, "one-pole after tau: %s" % filter.value.x)
	var reference := _one_pole_at(60, 0.4)
	for hz in [30, 120, 240]:
		var value := _one_pole_at(hz, 0.4)
		_expect(absf(value - reference) < 1e-5, "one-pole at %d Hz: %s vs %s at 60 Hz" % [hz, value, reference])


func _check_spring() -> void:
	var w := 12.0
	var spring := CriticalSpring.new(w)
	var peak := 0.0
	var worst := 0.0
	var hz := 60
	for i in hz * 2:
		var t := (i + 1) / float(hz)
		var x := spring.step(Vector2(1.0, 0.0), 1.0 / hz).x
		peak = maxf(peak, x)
		var expected := 1.0 - (1.0 + w * t) * exp(-w * t)
		worst = maxf(worst, absf(x - expected))
	_expect(worst < 1e-5, "spring matches the closed form (largest difference %s)" % worst)
	_expect(peak <= 1.0 + 1e-6, "spring does not overshoot (peak %s)" % peak)
	var reference := _spring_at(60, 0.2, false)
	for rate in [30, 120, 240]:
		var value := _spring_at(rate, 0.2, false)
		_expect(absf(value - reference) < 1e-5, "spring at %d Hz: %s vs %s at 60 Hz" % [rate, value, reference])


func _check_euler() -> void:
	var at_60 := _spring_at(60, 0.2, true)
	var at_120 := _spring_at(120, 0.2, true)
	_expect(absf(at_60 - at_120) > 1e-3, "Euler spring depends on the tick rate (%s vs %s)" % [at_60, at_120])
	var limit := 2.0 * (sqrt(2.0) - 1.0)
	_expect(absf(_euler_peak(limit * 0.97)) < 2.0, "Euler stable just below w dt = %.3f" % limit)
	_expect(absf(_euler_peak(limit * 1.03)) > 100.0, "Euler unstable just above w dt = %.3f" % limit)


func _one_pole_at(hz: int, seconds: float) -> float:
	var filter := OnePoleFilter.new(0.12)
	for i in roundi(seconds * hz):
		filter.step(Vector2(1.0, 0.0), 1.0 / hz)
	return filter.value.x


func _spring_at(hz: int, seconds: float, euler: bool) -> float:
	var spring := CriticalSpring.new(12.0)
	for i in roundi(seconds * hz):
		if euler:
			spring.step_euler(Vector2(1.0, 0.0), 1.0 / hz)
		else:
			spring.step(Vector2(1.0, 0.0), 1.0 / hz)
	return spring.value.x


## Largest |x| over 400 Euler steps of a spring released from x = 1, with
## w dt = h (w = h, dt = 1).
func _euler_peak(h: float) -> float:
	var spring := CriticalSpring.new(h)
	spring.value = Vector2(1.0, 0.0)
	var peak := 0.0
	for i in 400:
		peak = maxf(peak, absf(spring.step_euler(Vector2.ZERO, 1.0).x))
	return peak


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
