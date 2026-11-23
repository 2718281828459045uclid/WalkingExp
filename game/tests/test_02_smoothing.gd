extends SceneTree
## Lesson 02: checks Player.blend_factor() (src/player/player.gd).
##   1. EXPONENTIAL: after one second the remaining distance to the target
##      is exp(-k) at every tick rate (frame-rate independence).
##   2. LINEAR: the remaining distance depends on the tick rate, and
##      k * dt = 2 makes the velocity oscillate without settling.
## Run: Godot --headless --path game -s res://tests/test_02_smoothing.gd

const RATE := 8.0
const TICK_RATES: PackedInt32Array = [30, 60, 144, 240]

var _failures := 0


func _initialize() -> void:
	var exact := exp(-RATE)
	var linear_results: Array[float] = []
	for hz in TICK_RATES:
		var exponential := _remaining_after_one_second(RATE, hz, Player.BlendRule.EXPONENTIAL)
		var linear := _remaining_after_one_second(RATE, hz, Player.BlendRule.LINEAR)
		linear_results.append(linear)
		print("  %3d Hz: exponential leaves %.8f, linear leaves %.8f (exact %.8f)" % [hz, exponential, linear, exact])
		_expect(absf(exponential - exact) < 1e-9, "exponential rule at %d Hz leaves %.10f, expected %.10f" % [hz, exponential, exact])
	_expect(linear_results[0] < linear_results[-1] * 0.5, "linear rule does not depend on the tick rate as expected")

	# k * dt = 2: v -> v + 2 (1 - v) = 2 - v, so v alternates 0, 2, 0, 2.
	var v := 0.0
	for i in 10:
		v = lerpf(v, 1.0, Player.blend_factor(60.0, 1.0 / 30.0, Player.BlendRule.LINEAR))
	print("  linear rule, k dt = 2, after 10 ticks: v = %.3f (target 1)" % v)
	_expect(is_equal_approx(v, 0.0), "linear rule with k dt = 2 did not oscillate")

	print("test_02_smoothing: %s" % ("passed" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _remaining_after_one_second(rate: float, hz: int, rule: Player.BlendRule) -> float:
	var v := 0.0
	var dt := 1.0 / float(hz)
	for i in hz:
		v = lerpf(v, 1.0, Player.blend_factor(rate, dt, rule))
	return 1.0 - v


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
