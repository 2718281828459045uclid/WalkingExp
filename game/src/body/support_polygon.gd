class_name SupportPolygon
extends RefCounted
## The support polygon and the signed distance of a point to it (Lesson 13).
##
## The support polygon is the convex hull of the contact points, projected
## onto the ground plane. A standing body is statically balanced when the
## ground projection of its center of mass lies inside it. The signed
## distance below is the balance margin:
##
##   margin > 0   inside, distance to the nearest edge
##   margin < 0   outside, minus the distance to the polygon
##
## Ground coordinates: a world point (x, y, z) becomes (x, -z). Seen from
## above (+y) with x to the right, -z points up the page, so a polygon
## that turns counterclockwise in these coordinates turns counterclockwise
## on the screen of a top view.
##
##        -z (forward)
##          ^
##          |
##          +----> x (right)
##
## Used by BalanceMonitor (balance_monitor.gd).


## The ground coordinates of a world point.
static func ground_point(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)


## The world point of ground coordinates q at height y.
static func world_point(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, -q.y)


## z component of (b - a) x (c - a): positive when a, b, c turn
## counterclockwise, zero when they are collinear.
static func cross(a: Vector2, b: Vector2, c: Vector2) -> float:
	# The inputs are 32-bit; the products are formed in 64-bit floats.
	var abx := float(b.x) - float(a.x)
	var aby := float(b.y) - float(a.y)
	var acx := float(c.x) - float(a.x)
	var acy := float(c.y) - float(a.y)
	return abx * acy - aby * acx


## Convex hull by Andrew's monotone chain. Returns the hull's corners in
## counterclockwise order, without repeating the first, and without
## collinear points. Fewer than three distinct points give those points
## (one or two corners).
static func convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var sorted := points.duplicate()
	sorted.sort()
	# Q: What does sort() do with Vector2?
	# A: It orders by x, and by y where x is equal: the order the monotone
	#    chain needs. Equal points end up next to each other; the loop
	#    below drops repeats.
	var unique := PackedVector2Array()
	for p in sorted:
		if unique.is_empty() or not unique[unique.size() - 1].is_equal_approx(p):
			unique.append(p)
	if unique.size() < 3:
		return unique

	# Lower chain, left to right. A point that does not make a left turn
	# with the last two is removed: it lies on or inside the hull.
	var lower := PackedVector2Array()
	for p in unique:
		while lower.size() >= 2 and cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(p)
	# Upper chain, right to left, with the same rule.
	var upper := PackedVector2Array()
	for i in range(unique.size() - 1, -1, -1):
		var p := unique[i]
		while upper.size() >= 2 and cross(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(p)

	# Q: Why drop the last point of each chain?
	# A: Each chain ends where the other begins (the leftmost and the
	#    rightmost point). Without the drop those two points would appear
	#    twice.
	lower.remove_at(lower.size() - 1)
	upper.remove_at(upper.size() - 1)
	lower.append_array(upper)
	# All input points collinear: both chains reduce to the two ends.
	if lower.size() < 3:
		return PackedVector2Array([unique[0], unique[unique.size() - 1]])
	return lower


## Distance from p to the segment from a to b.
static func distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := Vector2(b - a)
	var length_squared := float(ab.dot(ab))
	# Q: Which point of the segment is nearest to p?
	# A: The projection a + t (b - a) with t = (p - a).(b - a) / |b - a|^2,
	#    clamped to [0, 1]: beyond the ends, the end itself is nearest.
	var t := 0.0
	if length_squared > 0.0:
		t = clampf(float((p - a).dot(ab)) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance from p to a convex polygon given counterclockwise
## (as convex_hull() returns it). Positive inside.
##   0 corners: -INF (no support)
##   1 or 2:    minus the distance to the point or segment
static func signed_distance(polygon: PackedVector2Array, p: Vector2) -> float:
	var n := polygon.size()
	if n == 0:
		return -INF
	if n == 1:
		return -p.distance_to(polygon[0])
	if n == 2:
		return -distance_to_segment(p, polygon[0], polygon[1])

	var nearest := INF
	var inside := true
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		nearest = minf(nearest, distance_to_segment(p, a, b))
		# Q: How does one edge tell inside from outside?
		# A: Each edge of a counterclockwise convex polygon has the interior
		#    on its left. p is inside when it lies on the left of every
		#    edge: cross(a, b, p) >= 0 for all edges.
		if cross(a, b, p) < 0.0:
			inside = false
	return nearest if inside else -nearest


## Area of a polygon (shoelace formula); positive when counterclockwise.
static func area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		sum += float(a.x) * float(b.y) - float(b.x) * float(a.y)
	return 0.5 * sum
