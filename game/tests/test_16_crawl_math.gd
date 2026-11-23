extends SceneTree
## Lesson 16: checks the geometry and the gait schedule of the crawl
## without a scene.
##   1. The gait schedule: CrawlController.swing_progress() gives each limb
##      one swing of swing_fraction per cycle; at most one limb is in the
##      air for swing_fraction <= 0.25, two for 0.3; lift_in() over random
##      steps finds every swing start once per cycle, in the lateral
##      sequence leg L, hand L, leg R, hand R, and not the swing that
##      starts at the interval's left end.
##   2. Four contacts: the margin of a point against the polygon of all
##      four and against each triangle of three (support_margin()) agrees
##      with an independent edge-distance formula; the four-contact
##      margin is never below a triangle's; the crossing point of the
##      diagonals lies on the edge of all four triangles (margin 0).
##   3. plane_normal(): up on flat ground, tilted by the slope of the
##      body axis, zero for a short or vertical axis.
##   4. The lean: d tan(theta) up the slope, clamped to max_lean, 0 on
##      flat ground or with slope_lean 0; with the lean, the vertical
##      projection of a point d above the plane lands on the base point.
##   5. kneeling_leg(): bone lengths kept, knee error equal to
##      | |knee target - hip| - thigh |, ankle behind and below the knee.
##   6. PostureController.shape_of() and mode_of().
## Run: Godot --headless --path game -s res://tests/test_16_crawl_math.gd

var _failures := 0


func _initialize() -> void:
	_check_schedule()
	_check_four_contacts()
	_check_plane_normal()
	_check_lean()
	_check_kneeling_leg()
	_check_posture_tables()
	print("test_16_crawl_math: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_schedule() -> void:
	for fraction: float in [0.2, 0.25, 0.3]:
		var most := 0
		var swing_ticks := [0, 0, 0, 0]
		for k in 10000:
			var phi := k / 10000.0
			var in_air := 0
			for limb in 4:
				if CrawlController.swing_progress(limb, phi, fraction) < 1.0:
					in_air += 1
					swing_ticks[limb] += 1
			most = maxi(most, in_air)
		var expected := 1 if fraction <= 0.25 else 2
		_expect(most == expected, "swing fraction %.2f: at most %d limb(s) in the air, got %d" % [fraction, expected, most])
		for limb in 4:
			_expect(absf(swing_ticks[limb] / 10000.0 - fraction) < 2e-4, "limb %d swings %.4f of the cycle" % [limb, swing_ticks[limb] / 10000.0])

	# Random steps through 50 cycles.
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	var phase := 0.96
	var travelled := 0.0
	var order: Array[int] = []
	while travelled < 50.0:
		var step := rng.randf_range(0.001, 0.05)
		var limb := CrawlController.lift_in(phase, step)
		if limb >= 0:
			order.append(limb)
		phase = fposmod(phase + step, 1.0)
		travelled += step
	var lateral := [CrawlController.Limb.LEG_L, CrawlController.Limb.HAND_L, CrawlController.Limb.LEG_R, CrawlController.Limb.HAND_R]
	var in_order := true
	for i in order.size():
		in_order = in_order and order[i] == lateral[i % 4]
	_expect(order.size() >= 199 and order.size() <= 201, "50 cycles: %d lifts (200 expected)" % order.size())
	_expect(in_order, "lifts in the lateral sequence leg L, hand L, leg R, hand R")
	_expect(CrawlController.lift_in(0.25, 0.1) == -1, "a swing that starts at the interval's left end is not found again")
	_expect(CrawlController.lift_in(0.2, 0.05) == CrawlController.Limb.HAND_L, "a swing that starts at the right end is found")
	_expect(CrawlController.lift_in(0.3, 0.0) == -1, "no step, no lift")


## A CrawlController outside the tree, with its four limbs planted at a
## trapezoid: hands 0.32 m apart, knees 0.24 m apart, 0.44 m behind.
func _crawl_on(points: Array) -> CrawlController:
	var crawl := CrawlController.new()
	for i in 4:
		crawl.limbs[i].planted = true
		crawl.limbs[i].contact = points[i]
	return crawl


func _check_four_contacts() -> void:
	var points := [Vector3(-0.16, 0, -0.22), Vector3(0.16, 0, -0.22), Vector3(-0.12, 0, 0.22), Vector3(0.12, 0, 0.22)]
	var crawl := _crawl_on(points)
	var ground: Array[Vector2] = []
	for p: Vector3 in points:
		ground.append(SupportPolygon.ground_point(p))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var never_below := true
	for k in 2000:
		var q := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.35, 0.35))
		var all_four := crawl.support_margin(q, -1)
		var by_hand := _convex_margin(q, [ground[0], ground[1], ground[3], ground[2]])
		worst = maxf(worst, absf(all_four - by_hand) if by_hand > 0.0 else 0.0)
		for except in 4:
			var tri := crawl.support_margin(q, except)
			var others: Array[Vector2] = []
			for i in 4:
				if i != except:
					others.append(ground[i])
			var tri_by_hand := _convex_margin(q, others)
			if tri_by_hand > 0.0:
				worst = maxf(worst, absf(tri - tri_by_hand))
			never_below = never_below and all_four >= tri - 1e-6
	_expect(worst < 1e-5, "margins inside the polygon and the triangles agree with the edge formula: %s" % worst)
	_expect(never_below, "the four-contact margin is never below a triangle's")

	# The diagonals hand L - knee R and hand R - knee L cross at one point.
	var a := ground[0]
	var b := ground[3]
	var c := ground[1]
	var d := ground[2]
	var t := (c - a).cross(d - c) / (b - a).cross(d - c)
	var crossing := a + (b - a) * t
	var on_all := true
	for except in 4:
		on_all = on_all and absf(crawl.support_margin(crossing, except)) < 1e-6
	_expect(on_all, "the crossing of the diagonals %s has margin 0 against all four triangles" % crossing)
	var center := (ground[0] + ground[1] + ground[2] + ground[3]) * 0.25
	var some_negative := false
	for except in 4:
		some_negative = some_negative or crawl.support_margin(center, except) < 0.0
	_expect(some_negative, "the center of the four contacts lies outside at least one triangle")
	crawl.free()


## Signed distance of q to a convex polygon given in any order, positive
## inside: the smallest distance to the edge lines, with the sign from the
## side. Valid inside (where it is the true distance).
func _convex_margin(q: Vector2, corners: Array[Vector2]) -> float:
	var hull := SupportPolygon.convex_hull(PackedVector2Array(corners))
	var smallest := INF
	for i in hull.size():
		var p0 := hull[i]
		var p1 := hull[(i + 1) % hull.size()]
		var edge := p1 - p0
		var inward := Vector2(-edge.y, edge.x).normalized()
		smallest = minf(smallest, (q - p0).dot(inward))
	return smallest


func _check_plane_normal() -> void:
	var right := Vector3.RIGHT
	var flat := CrawlController.plane_normal(Vector3(0, 0, -0.44), right)
	_expect(flat.is_equal_approx(Vector3.UP), "flat axis: normal up, got %s" % flat)
	var a := deg_to_rad(48.0)
	var slab := CrawlController.plane_normal(Vector3(0, sin(a), -cos(a)) * 0.6, right)
	_expect(absf(rad_to_deg(slab.angle_to(Vector3.UP)) - 48.0) < 1e-3 and slab.z > 0.0, "48 degree axis: normal tilted 48 degrees, back toward the legs: %s" % slab)
	_expect(CrawlController.plane_normal(Vector3(0, 0, -0.05), right) == Vector3.ZERO, "short axis: no normal")
	_expect(CrawlController.plane_normal(Vector3(0, 0.6, 0), right) == Vector3.ZERO, "vertical axis: no normal")


func _check_lean() -> void:
	var crawl := CrawlController.new()
	crawl.slope_lean = 1.0
	crawl.max_lean = 10.0
	var d := 0.5 * (crawl.crawl_hip_height + crawl.crawl_shoulder_height)
	var base := Vector3(1, 2, 3)
	_expect(crawl._lean(Vector3.UP, base).length() < 1e-9, "flat ground: no lean")
	var worst := 0.0
	var worst_projection := 0.0
	for degrees: float in [10.0, 16.0, 30.0, 48.0, 55.0]:
		var theta := deg_to_rad(degrees)
		# A slope that rises toward -z: n tilts toward +z.
		var n := Vector3(0, cos(theta), sin(theta))
		var lean := crawl._lean(n, base)
		worst = maxf(worst, absf(lean.length() - d * tan(theta)))
		var uphill := Vector3(0, sin(theta), -cos(theta))
		_expect(lean.normalized().dot(uphill) > 0.999999 and absf(lean.dot(n)) < 1e-6, "%.0f degrees: lean along the plane, uphill" % degrees)
		# Without the lean, the point d above the base projects d tan(theta)
		# down the slope; with it, onto the base.
		var c := base + n * d
		worst_projection = maxf(worst_projection, absf(_project_down(c, base, n).distance_to(base) - d * tan(theta)))
		worst_projection = maxf(worst_projection, _project_down(c + lean, base, n).distance_to(base))
	_expect(worst < 1e-6, "lean length d tan(theta): largest error %s" % worst)
	_expect(worst_projection < 1e-6, "vertical projection: drift d tan(theta), none after the lean: %s" % worst_projection)
	crawl.max_lean = 0.3
	var steep := crawl._lean(Vector3(0, cos(deg_to_rad(55.0)), sin(deg_to_rad(55.0))), base)
	_expect(absf(steep.length() - 0.3) < 1e-6, "lean clamped to max_lean: %f" % steep.length())
	crawl.slope_lean = 0.0
	_expect(crawl._lean(Vector3(0, cos(0.5), sin(0.5)), base) == Vector3.ZERO, "slope_lean 0: no lean")
	crawl.free()


## The point of the plane (base, n) straight below c.
func _project_down(c: Vector3, base: Vector3, n: Vector3) -> Vector3:
	var t := (c - base).dot(n) / Vector3.UP.dot(n)
	return c - Vector3.UP * t


func _check_kneeling_leg() -> void:
	var q := BodyProportions.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst_bone := 0.0
	var worst_error := 0.0
	var behind := true
	for k in 500:
		var theta := rng.randf_range(0.0, 0.5)
		var n := Vector3(0, cos(theta), sin(theta))
		var forward := Vector3(0, sin(theta), -cos(theta))
		var contact := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.3, 0.3))
		var hip := contact + n * rng.randf_range(0.4, 0.55) + forward * rng.randf_range(-0.2, 0.2) + Vector3.RIGHT * rng.randf_range(-0.1, 0.1)
		var leg := CrawlController.kneeling_leg(hip, contact, n, forward, q)
		worst_bone = maxf(worst_bone, absf(leg.root.distance_to(leg.middle) - q.thigh_length))
		worst_bone = maxf(worst_bone, absf(leg.middle.distance_to(leg.end) - q.shin_length))
		var knee_target := contact + n * q.thigh_radius
		worst_error = maxf(worst_error, absf(leg.middle.distance_to(knee_target) - absf(hip.distance_to(knee_target) - q.thigh_length)))
		behind = behind and (leg.end - leg.middle).dot(forward) < 0.0 and (leg.end - leg.middle).dot(n) < 0.0
	_expect(worst_bone < 1e-5, "thigh and shin keep their lengths: %s" % worst_bone)
	_expect(worst_error < 1e-5, "knee error = | |knee target - hip| - thigh |: %s" % worst_error)
	_expect(behind, "the ankle lies behind and below the knee")


func _check_posture_tables() -> void:
	var P := PostureController.Posture
	var S := CrawlingPlayer.BodyShape
	var M := CrawlingPlayer.Mode
	_expect(PostureController.shape_of(P.STAND) == S.STAND and PostureController.shape_of(P.CROUCH) == S.CROUCH \
			and PostureController.shape_of(P.CRAWL) == S.CRAWL and PostureController.shape_of(P.SCRAMBLE) == S.CROUCH, "shape of each posture")
	_expect(PostureController.mode_of(P.STAND) == M.UPRIGHT and PostureController.mode_of(P.CROUCH) == M.UPRIGHT \
			and PostureController.mode_of(P.CRAWL) == M.CRAWL and PostureController.mode_of(P.SCRAMBLE) == M.SCRAMBLE, "movement mode of each posture")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
