extends SceneTree
## Lesson 13: checks SupportPolygon (src/body/support_polygon.gd).
##   1. convex_hull(): a square with interior, repeated and collinear
##      points gives its four corners, counterclockwise; fewer than three
##      distinct points; all points on a line.
##   2. 200 random point sets: every input point lies inside or on the
##      hull, every corner is an input point, all turns are left turns,
##      and the area equals the brute-force area of the input's hull
##      corners (the hull does not depend on the input order).
##   3. signed_distance(): inside, on an edge, outside beside an edge and
##      beyond a corner; one point; a segment; no points.
##   4. 2000 random points against a random hull: the sign agrees with an
##      independent inside test and the magnitude with the smallest
##      distance to the edges.
##   5. ground_point() maps -z to +y: a polygon counterclockwise seen from
##      above has positive area.
## Run: Godot --headless --path game -s res://tests/test_13_support_polygon.gd

var _failures := 0


func _initialize() -> void:
	_check_hull()
	_check_random_hulls()
	_check_distance()
	_check_random_distance()
	_check_ground()
	print("test_13_support_polygon: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_hull() -> void:
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0.5, 0.5), Vector2(0.2, 0.7),  # inside
		Vector2(1, 1), Vector2(0, 0),          # repeated
		Vector2(0.5, 0), Vector2(1, 0.25),     # on edges
	])
	var hull := SupportPolygon.convex_hull(points)
	_expect(hull.size() == 4, "square hull has 4 corners, got %s" % hull)
	_expect(is_equal_approx(SupportPolygon.area(hull), 1.0), "square area 1 (counterclockwise), got %s" % SupportPolygon.area(hull))
	_expect(hull[0] == Vector2(0, 0), "hull starts at the lowest-x point")

	_expect(SupportPolygon.convex_hull(PackedVector2Array()).is_empty(), "no points: empty hull")
	_expect(SupportPolygon.convex_hull(PackedVector2Array([Vector2(2, 3), Vector2(2, 3)])).size() == 1, "one distinct point")
	var line := SupportPolygon.convex_hull(PackedVector2Array([Vector2(0, 0), Vector2(2, 2), Vector2(1, 1), Vector2(3, 3)]))
	_expect(line.size() == 2 and line[0] == Vector2(0, 0) and line[1] == Vector2(3, 3), "collinear points: the two ends, got %s" % line)


func _check_random_hulls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for trial in 200:
		var points := PackedVector2Array()
		for i in rng.randi_range(3, 40):
			points.append(Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		var hull := SupportPolygon.convex_hull(points)
		var n := hull.size()
		if n < 3:
			_expect(false, "trial %d: hull of %d points has %d corners" % [trial, points.size(), n])
			continue
		for i in n:
			_expect(SupportPolygon.cross(hull[i], hull[(i + 1) % n], hull[(i + 2) % n]) > 0.0, "trial %d: left turn at corner %d" % [trial, i])
			_expect(points.has(hull[i]), "trial %d: corner %d is an input point" % [trial, i])
		for p in points:
			_expect(SupportPolygon.signed_distance(hull, p) >= -1e-6, "trial %d: point %s inside the hull" % [trial, p])
		# The same points in reverse order give the same area.
		var reversed := points.duplicate()
		reversed.reverse()
		var other := SupportPolygon.convex_hull(reversed)
		_expect(absf(SupportPolygon.area(other) - SupportPolygon.area(hull)) < 1e-9, "trial %d: area independent of order" % trial)


func _check_distance() -> void:
	# Counterclockwise rectangle 2 x 1.
	var rect := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1)])
	_expect(is_equal_approx(SupportPolygon.signed_distance(rect, Vector2(1, 0.5)), 0.5), "center: +0.5")
	_expect(is_equal_approx(SupportPolygon.signed_distance(rect, Vector2(1.8, 0.5)), 0.2), "near the right edge: +0.2")
	_expect(is_zero_approx(SupportPolygon.signed_distance(rect, Vector2(1, 0))), "on an edge: 0")
	_expect(is_equal_approx(SupportPolygon.signed_distance(rect, Vector2(1, -0.3)), -0.3), "below the bottom edge: -0.3")
	_expect(is_equal_approx(SupportPolygon.signed_distance(rect, Vector2(2.3, 1.4)), -0.5), "beyond a corner: -0.5")
	var one := PackedVector2Array([Vector2(1, 1)])
	_expect(is_equal_approx(SupportPolygon.signed_distance(one, Vector2(1, 3)), -2.0), "one point: minus the distance")
	var segment := PackedVector2Array([Vector2(0, 0), Vector2(2, 0)])
	_expect(is_equal_approx(SupportPolygon.signed_distance(segment, Vector2(1, 0.25)), -0.25), "segment: minus the distance")
	_expect(is_equal_approx(SupportPolygon.signed_distance(segment, Vector2(3, 0)), -1.0), "segment: beyond its end")
	_expect(SupportPolygon.signed_distance(PackedVector2Array(), Vector2.ZERO) == -INF, "no support: -INF")


func _check_random_distance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1313
	var points := PackedVector2Array()
	for i in 12:
		var angle := rng.randf_range(0.0, TAU)
		points.append(Vector2(cos(angle), sin(angle)) * rng.randf_range(0.3, 1.0))
	var hull := SupportPolygon.convex_hull(points)
	var n := hull.size()
	for trial in 2000:
		var p := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var d := SupportPolygon.signed_distance(hull, p)
		# Independent inside test: the signed areas of the triangles
		# (p, a, b) sum to the polygon's area; p is inside exactly when
		# none of them is negative.
		var inside := true
		var nearest := INF
		for i in n:
			var a := hull[i]
			var b := hull[(i + 1) % n]
			if (a - p).cross(b - p) < 0.0:
				inside = false
			nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
		_expect((d >= 0.0) == inside, "trial %d: sign of %s at %s" % [trial, d, p])
		_expect(absf(absf(d) - nearest) < 1e-5, "trial %d: |d| = %s, nearest edge %s" % [trial, absf(d), nearest])


func _check_ground() -> void:
	# A triangle seen from above: right, then forward (-z), then left.
	var world := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]
	var polygon := PackedVector2Array()
	for p in world:
		polygon.append(SupportPolygon.ground_point(p))
	_expect(SupportPolygon.area(polygon) > 0.0, "right, forward, back: counterclockwise from above")
	_expect(SupportPolygon.world_point(SupportPolygon.ground_point(Vector3(1, 2, 3)), 2.0) == Vector3(1, 2, 3), "ground_point and world_point are inverse")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
