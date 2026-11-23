extends SceneTree
## Lesson 17: the shading models of src/render/brdf.gd, by numerical
## integration over the hemisphere ("white furnace" checks).
##   1. Lambert: directional albedo 1 for albedo 1, at four view angles.
##   2. Wrap: hemisphere integral (1 + 2w) / (1 + w), sphere 1 + w.
##   3. Oren-Nayar: sigma 0 equals Lambert; reciprocity f(l, v) = f(v, l);
##      albedo at most 1 and falling with sigma at normal view.
##   4. GGX distribution: the integral of D(h)(n.h) is 1 for alpha 0.02..1.
##   5. Smith: the integral of max(0, v.h) D(h) is (1 + Lambda(v)) cos(theta_v);
##      G2 height-correlated >= G1(l) G1(v).
##   6. GGX specular with f0 = 1: albedo at most 1; 1 - ln 2 at alpha 1
##      and normal view (closed form); importance sampling equals the
##      plain grid; reciprocity; Schlick's end values.
## Run: Godot --headless --path game -s res://tests/test_17_brdf.gd

var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 1717
	_check_lambert()
	_check_wrap()
	_check_oren_nayar()
	_check_distribution()
	_check_smith()
	_check_specular()
	print("test_17_brdf: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_lambert() -> void:
	var p := Brdf.Params.new()
	for degrees in [0.0, 30.0, 60.0, 80.0]:
		var v := Brdf.direction(deg_to_rad(degrees))
		var e := Brdf.directional_albedo(Brdf.Model.LAMBERT, v, p, 128, 64)
		_expect(absf(e - 1.0) < 1e-4, "Lambert albedo at %d deg: %.6f" % [degrees, e])
	p.albedo = 0.4
	var e4 := Brdf.directional_albedo(Brdf.Model.LAMBERT, Vector3.UP, p, 128, 64)
	_expect(absf(e4 - 0.4) < 1e-4, "Lambert albedo with rho 0.4: %.6f" % e4)


func _check_wrap() -> void:
	var p := Brdf.Params.new()
	for w in [0.25, 0.5, 1.0]:
		p.wrap = w
		var hemi := Brdf.directional_albedo(Brdf.Model.WRAP, Vector3.UP, p, 128, 64)
		var sphere := Brdf.directional_albedo(Brdf.Model.WRAP, Vector3.UP, p, 256, 64, -1.0)
		_expect(absf(hemi - (1.0 + 2.0 * w) / (1.0 + w)) < 1e-4, "wrap %.2f hemisphere %.5f" % [w, hemi])
		_expect(absf(sphere - (1.0 + w)) < 1e-3, "wrap %.2f sphere %.5f" % [w, sphere])
	p.wrap = 0.0
	var lambert := Brdf.directional_albedo(Brdf.Model.WRAP, Vector3.UP, p, 128, 64, -1.0)
	_expect(absf(lambert - 1.0) < 1e-4, "wrap 0 is Lambert, also over the sphere: %.5f" % lambert)


func _check_oren_nayar() -> void:
	var worst_zero := 0.0
	var worst_swap := 0.0
	for k in 200:
		var n := Vector3.UP
		var l := _random_upper()
		var v := _random_upper()
		worst_zero = maxf(worst_zero, absf(Brdf.oren_nayar(n, l, v, 1.0, 0.0) - Brdf.lambert(1.0)))
		var s := deg_to_rad(_rng.randf_range(5.0, 60.0))
		worst_swap = maxf(worst_swap, absf(Brdf.oren_nayar(n, l, v, 1.0, s) - Brdf.oren_nayar(n, v, l, 1.0, s)))
	_expect(worst_zero < 1e-12, "Oren-Nayar with sigma 0 equals Lambert: %s" % String.num_scientific(worst_zero))
	_expect(worst_swap < 1e-12, "Oren-Nayar reciprocity: %s" % String.num_scientific(worst_swap))
	var p := Brdf.Params.new()
	var previous := 1.0 + 1e-9
	for degrees in [0.0, 15.0, 30.0, 45.0, 60.0]:
		p.sigma = deg_to_rad(degrees)
		var e0 := Brdf.directional_albedo(Brdf.Model.OREN_NAYAR, Vector3.UP, p, 128, 64)
		_expect(e0 < previous, "Oren-Nayar albedo at normal view falls with sigma: %d deg %.4f" % [degrees, e0])
		previous = e0
		for view in [30.0, 60.0, 80.0]:
			var e := Brdf.directional_albedo(Brdf.Model.OREN_NAYAR, Brdf.direction(deg_to_rad(view)), p, 128, 64)
			_expect(e <= 1.0 + 1e-6, "Oren-Nayar albedo <= 1 (sigma %d, view %d): %.4f" % [degrees, view, e])


func _check_distribution() -> void:
	for alpha in [0.02, 0.05, 0.1, 0.3, 0.6, 1.0]:
		var total := Brdf.ggx_normalization(alpha)
		_expect(absf(total - 1.0) < 1e-3, "GGX D normalized at alpha %.2f: %.6f" % [alpha, total])


func _check_smith() -> void:
	for alpha in [0.1, 0.5, 1.0]:
		for degrees in [0.0, 60.0, 85.0]:
			var v := Brdf.direction(deg_to_rad(degrees))
			var area := Brdf.projected_facet_area(v, alpha, 512, 128)
			var expected := 1.0 + Brdf.smith_lambda(v.y, alpha)
			_expect(absf(area - expected) / expected < 1e-3, "Smith Lambda at alpha %.1f, %d deg: %.5f vs %.5f" % [alpha, degrees, area, expected])
	var worst := INF
	for k in 500:
		var a := _rng.randf_range(0.02, 1.0)
		var nl := _rng.randf_range(0.01, 1.0)
		var nv := _rng.randf_range(0.01, 1.0)
		var separable := Brdf.smith_masking(nl, a) * Brdf.smith_masking(nv, a)
		worst = minf(worst, Brdf.smith_height_correlated(nl, nv, a) - separable)
	_expect(worst >= -1e-12, "height-correlated G2 never below G1 G1: min difference %s" % String.num_scientific(worst))


func _check_specular() -> void:
	for roughness in [0.2, 0.5, 0.92, 1.0]:
		for degrees in [0.0, 30.0, 60.0, 80.0]:
			var e := Brdf.ggx_specular_albedo(Brdf.direction(deg_to_rad(degrees)), roughness, 1.0, 128, 64)
			_expect(e <= 1.0 + 1e-3, "GGX specular albedo <= 1 (roughness %.2f, %d deg): %.4f" % [roughness, degrees, e])
	var smooth := Brdf.ggx_specular_albedo(Vector3.UP, 0.2)
	_expect(smooth > 0.99, "smooth GGX (roughness 0.2) reflects more than 0.99 at normal view: %.4f" % smooth)
	# Q: Why is 1 - ln 2 exact at alpha = 1?
	# A: D = 1 / pi, Lambda(v) = 0 at normal view and
	#    Lambda(l) = (1 / cos(theta_l) - 1) / 2, so the integral reduces to
	#    the integral of mu / (1 + mu) over [0, 1] (README P5).
	var rough := Brdf.ggx_specular_albedo(Vector3.UP, 1.0)
	_expect(absf(rough - (1.0 - log(2.0))) < 1e-3, "GGX alpha 1 at normal view: %.5f vs 1 - ln 2 = %.5f" % [rough, 1.0 - log(2.0)])
	var p := Brdf.Params.new()
	p.albedo = 0.0
	p.f0 = 1.0
	for degrees in [0.0, 60.0]:
		var v := Brdf.direction(deg_to_rad(degrees))
		var grid := Brdf.directional_albedo(Brdf.Model.GGX, v, p, 384, 192)
		var sampled := Brdf.ggx_specular_albedo(v, p.roughness)
		_expect(absf(grid - sampled) < 2e-3, "GGX albedo at %d deg, grid %.4f vs importance %.4f" % [degrees, grid, sampled])
	var worst := 0.0
	for k in 200:
		var l := _random_upper()
		var v := _random_upper()
		var r := _rng.randf_range(0.1, 1.0)
		var forward := Brdf.ggx_specular(Vector3.UP, l, v, r, 0.04)
		var backward := Brdf.ggx_specular(Vector3.UP, v, l, r, 0.04)
		worst = maxf(worst, absf(forward - backward) / maxf(forward, 1e-12))
	# Q: Why a tolerance of 1e-5 and not zero?
	# A: v.h and l.h are equal in exact arithmetic, but Vector3 holds 32-bit
	#    floats, so the two dot products differ in the seventh digit.
	_expect(worst < 1e-5, "GGX reciprocity, relative: %s" % String.num_scientific(worst))
	_expect(absf(Brdf.schlick_fresnel(0.04, 1.0) - 0.04) < 1e-12 and absf(Brdf.schlick_fresnel(0.04, 0.0) - 1.0) < 1e-12, "Schlick: f0 head-on, 1 at grazing")


func _random_upper() -> Vector3:
	var mu := _rng.randf_range(0.02, 1.0)
	var phi := _rng.randf() * TAU
	var s := sqrt(1.0 - mu * mu)
	return Vector3(s * cos(phi), mu, s * sin(phi))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok    " + message)
