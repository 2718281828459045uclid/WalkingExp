extends SceneTree
## Measures the cost and the image of every lighting preset of the Lesson
## 18 scene. Called by tools/light_perf.sh; runs in a window (the GPU must
## draw).
##
## Arguments after "--":  [frames per measurement] [rounds] [width] [output dir]
##
## For each fixed camera view and each preset of the scene's Lighting node
## (a LightPresetSwitch), the script applies the preset, waits WARMUP
## frames, then records the duration of `frames` frames. The rounds
## repeat all measurements in turn, so that a slow moment of the machine
## spreads over all presets instead of falling on one. At the end it
## prints, per view and preset:
##   - median, 5th and 95th percentile of the frame time (all rounds)
##   - draw calls and triangles of the shadow pass and of the main pass
##   - the quality probes of the view (from an image of the last round,
##     saved to the output dir when one is given)
##
## Q: Why frame time and not GPU time?
## A: viewport_get_measured_render_time_gpu() returns 0 on Godot 4.6's
##    Metal backend (Lesson 10; the script prints it again). With vsync
##    off, a frame takes as long as the slower of CPU and GPU.
##
## Q: Then how does the frame time show the GPU's work?
## A: By making the GPU the slower of the two, in two steps.
##    1. The scene's scripts and physics are stopped once the scene is
##       built (process_mode DISABLED): the CPU's share is then small and
##       the same for every preset.
##    2. The views are drawn into an offscreen SubViewport of `width` x
##       (width * 9 / 16) pixels (default 2560 x 1440, the pixel count of
##       a 1280 x 720 window on a display with two pixels per point); the
##       window itself draws no 3D, only that image scaled down.
##    Measured in Lesson 18: with the scene running and drawn in the
##    1280 x 720 window, frame times of one preset spread from 2 to 9 ms
##    and the medians of the presets did not separate; offscreen at
##    2560 x 1440 the 5th and 95th percentiles lie within 0.4 ms of the
##    median.
##
## Q: What are the quality probes?
## A: Numbers read from the image at points whose world position is known:
##    face   mean screen value (0-255, after tonemapping) of the climbing
##           face's front, which the sun does not reach: it shows the
##           ambient or indirect light alone.
##    gap    the same for the floor under the crawl gap's roof.
##    edge   the shadow of the climbing face's side edge on the ground,
##           read along nine 1.5 m lines across it. Each sample is divided
##           by the same pixel in the preset without sun shadow, which
##           removes the ground's own pattern; what is left is the
##           shadow's profile from lit (1) to shadowed. Printed: the median
##           over the nine lines of the width in centimeters over which the
##           profile goes from 10 % to 90 % of its step, and the contrast
##           1 - shadowed / lit.

const SCENE := "res://scenes/lessons/18_shadows_and_gi.tscn"
const WARMUP := 90
## Each view: [name, eye (x, z), eye height above ground, target (x, z),
## target height above ground, probes]. INF: the player's start camera.
const VIEWS := [
	["start", Vector2.INF, 0.0, Vector2.INF, 0.0, []],
	["face", Vector2(2.5, 41.0), 2.5, Vector2(5.5, 47.5), 1.5, ["face", "edge"]],
	["far", Vector2(-9.9, 9.2), 6.0, Vector2(7.6, 45.2), 0.0, ["edge"]],
	["gap", Vector2(-1.5, 52.0), 1.0, Vector2(-7.0, 52.0), 0.4, ["gap"]],
]
## Samples along one edge line, its length, and the distances of the nine
## lines from the face's corner along the shadow, meters.
const EDGE_SAMPLES := 151
const EDGE_LENGTH := 1.5
const EDGE_OFFSETS: Array[float] = [3.0, 3.25, 3.5, 3.75, 4.0, 4.25, 4.5, 4.75, 5.0]

var _scene: Node
var _lighting: LightPresetSwitch
var _terrain: Terrain
var _viewport: SubViewport
var _camera: Camera3D
var _frames := 300
var _rounds := 3
var _width := 2560
var _out_dir := ""
## Each job: [view index, preset index, round].
var _jobs: Array = []
var _job := -1
var _frame := 0
var _last_usec := 0
## "view/preset" -> Array of frame times (ms), all rounds.
var _times := {}
## "view/preset" -> [shadow draws, shadow tris, main draws, main tris].
var _render_info := {}
## "view/preset" -> {probe name: value}; edge: Array of nine profiles.
var _probes := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_frames = int(args[0])
	if args.size() > 1:
		_rounds = int(args[1])
	if args.size() > 2:
		_width = int(args[2])
	if args.size() > 3:
		_out_dir = args[3]
		DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_scene.get_node("HUD").visible = false
	_lighting = _scene.get_node("Lighting")
	_terrain = _scene.get_node("Terrain")
	# Q: Why free the raymarched formations before the first measurement?
	# A: The first SDFGI preset frees them anyway (LightPresetSwitch.
	#    free_sdfgi_conflicts()). Freed at the start, they are absent from
	#    every measurement instead of from those after the first SDFGI one.
	_lighting.free_sdfgi_conflicts()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_width, _width * 9 / 16)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	_viewport.add_child(_camera)
	# The window shows the offscreen image, scaled to fit.
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	for r in _rounds:
		for v in VIEWS.size():
			for p in _lighting.presets.size():
				_jobs.append([v, p, r])
	print("driver %s, %s; %d frames x %d rounds per measurement; offscreen %dx%d" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(), _frames, _rounds, _viewport.size.x, _viewport.size.y])


func _process(_delta: float) -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var now := Time.get_ticks_usec()
	# Q: Why wait 30 frames before the first job?
	# A: The scene builds its rocks and gallery in its first frames and
	#    turns the player's camera; the start view is read after that.
	if _job < 0:
		_frame += 1
		if _frame == 30:
			_scene.process_mode = Node.PROCESS_MODE_DISABLED
			root.disable_3d = true
			_next_job()
		_last_usec = now
		return false
	_frame += 1
	if _frame > WARMUP:
		(_times[_key(_jobs[_job])] as Array).append((now - _last_usec) / 1000.0)
	_last_usec = now
	if _frame == WARMUP + _frames:
		_finish_job()
		if _job + 1 == _jobs.size():
			_report()
			quit(0)
			return true
		_next_job()
	return false


func _key(job: Array) -> String:
	return "%s/%d" % [VIEWS[job[0]][0], job[1]]


func _next_job() -> void:
	_job += 1
	_frame = 0
	var job: Array = _jobs[_job]
	if not _times.has(_key(job)):
		_times[_key(job)] = []
	if _lighting.index != job[1]:
		_lighting.apply(job[1])
	var view: Array = VIEWS[job[0]]
	if view[1] == Vector2.INF:
		var player_camera := _scene.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
		_camera.global_transform = player_camera.global_transform
	else:
		_camera.look_at_from_position(_ground(view[1], view[2]), _ground(view[3], view[4]))


func _ground(xz: Vector2, height: float) -> Vector3:
	return Vector3(xz.x, _terrain.height_at(xz.x, xz.y) + height, xz.y)


func _finish_job() -> void:
	var job: Array = _jobs[_job]
	var key := _key(job)
	var rid := _viewport.get_viewport_rid()
	_render_info[key] = [
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
	]
	# Q: Why read the image only in the last round?
	# A: Reading the image back stalls the GPU for one frame; in the last
	#    round the measurement is already over. SDFGI also has had the
	#    most frames to settle by then.
	if job[2] != _rounds - 1:
		return
	var image := _viewport.get_texture().get_image()
	if _out_dir != "":
		image.save_png("%s/%s_%02d.png" % [_out_dir, VIEWS[job[0]][0], job[1]])
	var probes := {}
	for probe in VIEWS[job[0]][5]:
		match probe:
			"face":
				probes["face"] = _mean_value(image, _face_points())
			"gap":
				probes["gap"] = _mean_value(image, _gap_points())
			"edge":
				var profiles := []
				for offset in EDGE_OFFSETS:
					profiles.append(_edge_profile(image, offset))
				probes["edge"] = profiles
	_probes[key] = probes


## Mean screen value (0-255, mean of R, G, B) at the given pixels; NAN
## for none.
func _mean_value(image: Image, pixels: Array) -> float:
	if pixels.is_empty():
		return NAN
	var sum := 0.0
	for pixel in pixels:
		var c := image.get_pixelv(pixel)
		sum += (c.r + c.g + c.b) / 3.0 * 255.0
	return sum / pixels.size()


## Q: How does the script know a pixel shows the climbing face?
## A: It casts a physics ray from the camera toward each point of a grid
##    on the face's front (shape space z = 0.6) and keeps the pixel only
##    if the first thing the ray hits belongs to the ClimbFace node, within
##    5 cm of the point. Knobs, the player or the terrain in front of a
##    point drop it.
func _face_points() -> Array:
	var face := _scene.get_node("ClimbFace") as Node3D
	var pixels := []
	for i in 25:
		for j in 37:
			var local := Vector3(-1.2 + 0.1 * i, 0.4 + 0.1 * j, 0.6)
			var pixel: Variant = _visible_pixel(face.global_transform * local, face)
			if pixel != null:
				pixels.append(pixel)
	return pixels


## The floor under the gap's roof: the middle 0.9 m of its width, the
## whole roof length.
func _gap_points() -> Array:
	var gap := _scene.get_node("CrawlGap") as CrawlGap
	var pixels := []
	for i in 10:
		for j in 23:
			var local := Vector3(-0.45 + 0.1 * i, 0.0, -0.5 * gap.gap_length + 0.1 + 0.1 * j)
			var pixel: Variant = _visible_pixel(gap.global_transform * local, gap)
			if pixel != null:
				pixels.append(pixel)
	return pixels


## The pixel of a point, or null when the first hit of the ray from the
## camera toward the point is not part of `owner_node` or lies farther
## than `tolerance` meters from the point.
func _visible_pixel(point: Vector3, owner_node: Node, tolerance: float = 0.05) -> Variant:
	if _camera.is_position_behind(point):
		return null
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + (point - from) * 1.05)
	var hit: Dictionary = _scene.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not owner_node.is_ancestor_of(hit["collider"]) or (hit["position"] as Vector3).distance_to(point) > tolerance:
		return null
	var pixel := _camera.unproject_position(point)
	var size := _viewport.size
	if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x >= size.x or pixel.y >= size.y:
		return null
	return Vector2i(pixel)


## Q: Where do the edge lines lie?
## A: The sun shines along -L, where L (the Sun's basis z) points toward
##    the sun. The shadow of the face's vertical edge at shape-space corner
##    (1.45, 0, 0.6) runs from that corner along the horizontal part d of
##    -L. A line starts `offset` meters along d from the corner and crosses
##    the shadow's edge at right angles, 0.75 m to each side.
## The profile holds one screen value per sample; NAN where the ground is
## hidden or off screen.
func _edge_profile(image: Image, offset: float) -> PackedFloat32Array:
	var face := _scene.get_node("ClimbFace") as Node3D
	var sun := _scene.get_node("Sun") as DirectionalLight3D
	var toward_sun := sun.global_transform.basis.z
	var d := Vector3(-toward_sun.x, 0.0, -toward_sun.z).normalized()
	var across := Vector3(-d.z, 0.0, d.x)
	var corner := face.global_transform * Vector3(1.45, 0.0, 0.6)
	var center := corner + offset * d
	var profile := PackedFloat32Array()
	for k in EDGE_SAMPLES:
		var s := (k / float(EDGE_SAMPLES - 1) - 0.5) * EDGE_LENGTH
		var p := center + s * across
		# Q: Why a 0.15 m tolerance here?
		# A: height_at() evaluates the smooth field; the drawn ground is
		#    the triangle mesh between grid points 1 m apart, which lies a
		#    few centimeters off it on curved ground.
		p.y = _terrain.height_at(p.x, p.z)
		var pixel: Variant = _visible_pixel(p, _terrain, 0.15)
		if pixel == null:
			profile.append(NAN)
		else:
			var c := image.get_pixelv(pixel)
			profile.append((c.r + c.g + c.b) / 3.0 * 255.0)
	return profile


## Q: How are the width and the contrast read from two profiles?
## A: r = profile / reference profile (the preset without sun shadow).
##    The shadowed level is the median of r over the outer fifth of the
##    line on one side, the lit level over the outer fifth on the other.
##    The width runs from the last sample still within 10 % of the step
##    above the shadowed level to the first later sample within 10 % of
##    the lit level. Returns (width in cm, contrast); width NAN when the
##    contrast is below 0.05 (no shadow on the line).
static func edge_numbers(profile: PackedFloat32Array, reference: PackedFloat32Array) -> Vector2:
	var r := PackedFloat32Array()
	for k in profile.size():
		r.append(profile[k] / reference[k] if reference[k] > 0.0 else NAN)
	var n := r.size()
	var fifth := n / 5
	var start_level := _median(r.slice(0, fifth))
	var end_level := _median(r.slice(n - fifth, n))
	if is_nan(start_level) or is_nan(end_level):
		return Vector2(NAN, NAN)
	# Order the samples from the shadowed side to the lit side.
	if start_level > end_level:
		r.reverse()
		var t := start_level
		start_level = end_level
		end_level = t
	var contrast := 1.0 - start_level / end_level
	if contrast < 0.05:
		return Vector2(NAN, contrast)
	var low := -1
	for k in n:
		if not is_nan(r[k]) and (r[k] - start_level) / (end_level - start_level) <= 0.1:
			low = k
	var high := n - 1
	for k in range(n - 1, low, -1):
		if not is_nan(r[k]) and (r[k] - start_level) / (end_level - start_level) >= 0.9:
			high = k
	var spacing := EDGE_LENGTH / (EDGE_SAMPLES - 1)
	return Vector2((high - low) * spacing * 100.0, contrast)


static func _median(values: PackedFloat32Array) -> float:
	var kept := PackedFloat32Array()
	for v in values:
		if not is_nan(v):
			kept.append(v)
	if kept.is_empty():
		return NAN
	kept.sort()
	return kept[kept.size() / 2]


func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	return sorted[mini(int(q * sorted.size()), sorted.size() - 1)]


func _report() -> void:
	var reference := -1
	for p in _lighting.presets.size():
		if not _lighting.presets[p].shadows_enabled:
			reference = p
	print("VoxelGI bake: %.0f ms" % _lighting.voxel_bake_milliseconds)
	print("GPU time reported by the renderer: %.3f ms" % RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid()))
	for v in VIEWS.size():
		var view: Array = VIEWS[v]
		print("")
		print("view %s (frame time in ms; draw calls and triangles of the shadow pass and the main pass)" % view[0])
		print("%-3s %-16s %7s %7s %7s %6s %8s %6s %8s %s" % ["#", "preset", "p05", "median", "p95", "sh.dc", "sh.tris", "dc", "tris", "probes"])
		for p in _lighting.presets.size():
			var key := "%s/%d" % [view[0], p]
			var times := PackedFloat32Array(_times[key])
			times.sort()
			var info: Array = _render_info[key]
			var probe_text := PackedStringArray()
			var probes: Dictionary = _probes.get(key, {})
			if probes.has("face"):
				probe_text.append("face %.1f" % probes["face"])
			if probes.has("gap"):
				probe_text.append("gap %.1f" % probes["gap"])
			if probes.has("edge") and reference >= 0:
				var widths := PackedFloat32Array()
				var contrasts := PackedFloat32Array()
				for line in EDGE_OFFSETS.size():
					var numbers := edge_numbers(probes["edge"][line], _probes["%s/%d" % [view[0], reference]]["edge"][line])
					widths.append(numbers.x)
					contrasts.append(numbers.y)
				probe_text.append("edge %.1f cm, contrast %.2f" % [_median(widths), _median(contrasts)])
			print("%-3d %-16s %7.3f %7.3f %7.3f %6d %8d %6d %8d %s" % [p, _lighting.presets[p].title, _percentile(times, 0.05), _percentile(times, 0.5), _percentile(times, 0.95), info[0], info[1], info[2], info[3], "  ".join(probe_text)])
