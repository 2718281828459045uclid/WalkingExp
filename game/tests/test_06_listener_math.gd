extends SceneTree
## Lesson 06: checks ListenerMath (src/audio/listener_math.gd) and
## SpatialAudioReporter.wind_strength_at().
##   1. spherical(): ahead, right, behind, left, overhead, and a diagonal
##      point give the expected azimuth, elevation, and distance.
##   2. spherical_from(): a listener turned 90 degrees and moved; the
##      same point keeps its distance and changes its azimuth.
##   3. direction_azimuth() ignores the listener's position.
##   4. unwrap_angle(): a point circling the listener three times gives
##      a sequence with steps below PI and a total of 6 PI.
##   5. wind_strength_at() is a clamped straight line.
## Run: Godot --headless --path game -s res://tests/test_06_listener_math.gd

const TOLERANCE := 1e-5

var _failures := 0


func _initialize() -> void:
	_check_spherical()
	_check_turned_listener()
	_check_unwrap()
	_check_wind()
	print("test_06_listener_math: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_spherical() -> void:
	_expect_spherical(Vector3(0, 0, -5), Vector3(0, 0, 5), "ahead")
	_expect_spherical(Vector3(3, 0, 0), Vector3(PI / 2, 0, 3), "right")
	_expect_spherical(Vector3(-2, 0, 0), Vector3(-PI / 2, 0, 2), "left")
	_expect_spherical(Vector3(0, 0, 4), Vector3(PI, 0, 4), "behind")
	_expect_spherical(Vector3(0, 5, 0), Vector3(0, PI / 2, 5), "overhead")
	# (1, 1, -1): 45 degrees right, elevation atan(1 / sqrt 2), distance sqrt 3.
	_expect_spherical(Vector3(1, 1, -1), Vector3(PI / 4, atan(1.0 / sqrt(2.0)), sqrt(3.0)), "diagonal")
	_expect(ListenerMath.spherical(Vector3.ZERO) == Vector3.ZERO, "a point at the listener is not zero")


func _check_turned_listener() -> void:
	# Turned +90 degrees about y (counterclockwise seen from above): the
	# listener faces -x, and its right is -z.
	var listener := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(10, 2, 0))
	var ahead := ListenerMath.spherical_from(listener, Vector3(5, 2, 0))
	var right := ListenerMath.spherical_from(listener, Vector3(10, 2, -7))
	_expect(_close(ahead, Vector3(0, 0, 5)), "turned listener, point ahead: %s" % ahead)
	_expect(_close(right, Vector3(PI / 2, 0, 7)), "turned listener, point right: %s" % right)
	var wind := ListenerMath.direction_azimuth(listener, Vector3(0, 0, -1))
	var moved := listener.translated(Vector3(-40, 0, 25))
	_expect(absf(wind - PI / 2) < TOLERANCE, "direction -z is not to the right: %f" % wind)
	_expect(absf(ListenerMath.direction_azimuth(moved, Vector3(0, 0, -1)) - wind) < TOLERANCE, "direction_azimuth depends on position")


func _check_unwrap() -> void:
	# The point circles the listener three times in 360 steps.
	var previous := 0.0
	var largest_step := 0.0
	for i in range(1, 361):
		var angle := TAU * 3.0 * i / 360.0
		var point := Vector3(sin(angle), 0.0, -cos(angle)) * 4.0
		var raw := ListenerMath.spherical(point).x
		var unwrapped := ListenerMath.unwrap_angle(previous, raw)
		largest_step = maxf(largest_step, absf(unwrapped - previous))
		previous = unwrapped
	_expect(largest_step < PI, "unwrapped step of %f" % largest_step)
	_expect(absf(previous - 3.0 * TAU) < 1e-4, "three turns unwrap to %f, not 6 PI" % previous)
	# The case of the Q/A comment: 179 degrees, then -179 degrees.
	var across := ListenerMath.unwrap_angle(deg_to_rad(179.0), deg_to_rad(-179.0))
	_expect(absf(across - deg_to_rad(181.0)) < TOLERANCE, "179 then -179 unwraps to %f deg" % rad_to_deg(across))


func _check_wind() -> void:
	var low := SpatialAudioReporter.wind_strength_at(-10.0, 0.3, 0.05, 0.0)
	var middle := SpatialAudioReporter.wind_strength_at(6.0, 0.3, 0.05, 0.0)
	var high := SpatialAudioReporter.wind_strength_at(30.0, 0.3, 0.05, 0.0)
	_expect(is_equal_approx(low, 0.0) and is_equal_approx(middle, 0.6) and is_equal_approx(high, 1.0), "wind strengths %f %f %f" % [low, middle, high])


func _expect_spherical(point: Vector3, expected: Vector3, label: String) -> void:
	var s := ListenerMath.spherical(point)
	_expect(_close(s, expected), "%s: %s, expected %s" % [label, s, expected])


## Compares two (azimuth, elevation, distance) triples; azimuths that
## differ by 2 PI count as equal.
func _close(a: Vector3, b: Vector3) -> bool:
	var azimuth_error := absf(wrapf(a.x - b.x, -PI, PI))
	return azimuth_error < TOLERANCE and absf(a.y - b.y) < TOLERANCE and absf(a.z - b.z) < TOLERANCE


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
