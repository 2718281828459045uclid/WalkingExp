extends SceneTree
## Lesson 05: checks GaitClock (src/audio/gait_clock.gd) and the slope
## formula of FootstepReporter.
##   1. Walking 3 m/s with 0.75 m steps for 10.1 s gives 40 strikes at 30,
##      60, and 144 Hz ticks; feet alternate, starting with the left.
##   2. Strike times rebuilt from strike_fraction fall on multiples of
##      0.25 s at every tick rate (to 1e-9 s): the timing does not
##      depend on the tick rate.
##   3. A 10 m jump in one call gives one strike, not 13.
##   4. signed_slope_degrees: +30 walking up a 30 degree plane, -30 down,
##      0 across it and at rest.
## Run: Godot --headless --path game -s res://tests/test_05_gait_clock.gd

var _failures := 0


func _initialize() -> void:
	_check_rates()
	_check_jump()
	_check_slope()
	print("test_05_gait_clock: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_rates() -> void:
	var speed := 3.0
	for tick_rate in [30, 60, 144]:
		var delta: float = 1.0 / tick_rate
		var gait := GaitClock.new(0.75)
		var strikes := 0
		var worst := 0.0
		var feet_ok := true
		for i in int(tick_rate * 10.1):
			if gait.advance(speed * delta):
				strikes += 1
				var tick_end: float = (i + 1) * delta
				var strike_time: float = tick_end - (1.0 - gait.strike_fraction) * delta
				worst = maxf(worst, absf(strike_time - strikes * 0.25))
				feet_ok = feet_ok and gait.last_foot() == (strikes - 1) % 2
		# 10.1 s: the 40th strike at 10 s lies inside the run, not on its edge.
		_expect(strikes == 40, "%d Hz: %d strikes in 10.1 s, expected 40" % [tick_rate, strikes])
		_expect(worst < 1e-9, "%d Hz: strike times off by up to %s s" % [tick_rate, worst])
		_expect(feet_ok, "%d Hz: feet do not alternate left, right" % tick_rate)


func _check_jump() -> void:
	var gait := GaitClock.new(0.75)
	_expect(gait.advance(10.0), "a 10 m advance gave no strike")
	_expect(not gait.advance(0.0), "a zero advance gave a strike")
	_expect(gait.phase < 14.0, "phase after a 10 m jump is %f" % gait.phase)


func _check_slope() -> void:
	# A plane rising along -z at 30 degrees: h = -tan(30) z, normal (0, cos, sin).
	var a := deg_to_rad(30.0)
	var n := Vector3(0.0, cos(a), sin(a))
	var up := FootstepReporter.signed_slope_degrees(n, Vector2(0.0, -1.0))
	var down := FootstepReporter.signed_slope_degrees(n, Vector2(0.0, 1.0))
	var across := FootstepReporter.signed_slope_degrees(n, Vector2(1.0, 0.0))
	var rest := FootstepReporter.signed_slope_degrees(n, Vector2.ZERO)
	_expect(absf(up - 30.0) < 1e-4 and absf(down + 30.0) < 1e-4, "slope up %f, down %f, expected +30, -30" % [up, down])
	_expect(absf(across) < 1e-4 and rest == 0.0, "slope across %f, at rest %f, expected 0" % [across, rest])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
