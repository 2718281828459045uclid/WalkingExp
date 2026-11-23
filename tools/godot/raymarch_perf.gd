extends SceneTree
## Measures the frame time of the Lesson 10 scene with the raymarched
## formations hidden and with several step budgets. Called by
## tools/raymarch_perf.sh; runs in a window (the GPU must draw).
##
## Arguments after "--":  [frames per measurement]
##
## Q: Why frame time and not GPU time?
## A: viewport_get_measured_render_time_gpu() returns 0 on Godot 4.6's
##    Metal backend. With vsync off, a frame takes as long as the slower of
##    CPU and GPU. The scene's CPU work is the same in every measurement,
##    so differences between measurements are differences in GPU work.

const SCENE := "res://scenes/lessons/10_raymarching.tscn"
const BUDGETS: PackedInt32Array = [16, 32, 64, 96, 192]
## Two camera placements: [name, position, target].
const VIEWS := [
	["overview", Vector3(0, 16, 45), Vector3(0, 4, -10)],
	["close", Vector3(-7, 2.5, 35), Vector3(-9, 1.5, 31)],
]

var _scene: Node
var _camera: Camera3D
## Each job: [view index, max_steps or 0 for hidden].
var _jobs: Array = []
var _job := 0
var _frame := 0
var _frames := 240
var _warmup := 60
var _start_usec := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_frames = int(args[0])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_scene.get_node("HUD").visible = false
	_camera = Camera3D.new()
	root.add_child(_camera)
	for v in VIEWS.size():
		_jobs.append([v, 0])
		for budget in BUDGETS:
			_jobs.append([v, budget])
	_begin_job()


func _process(_delta: float) -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame += 1
	if _frame == _warmup:
		_start_usec = Time.get_ticks_usec()
	elif _frame == _warmup + _frames:
		var ms := (Time.get_ticks_usec() - _start_usec) / 1000.0 / _frames
		var job: Array = _jobs[_job]
		if _job == 0:
			print("view       steps   ms/frame   (%d frames each, window %dx%d)" % [_frames, root.size.x, root.size.y])
		var steps := "hidden" if job[1] == 0 else str(job[1])
		print("%-10s %6s   %8.3f" % [VIEWS[job[0]][0], steps, ms])
		_job += 1
		if _job == _jobs.size():
			quit(0)
			return true
		_begin_job()
	return false


func _begin_job() -> void:
	var job: Array = _jobs[_job]
	var view: Array = VIEWS[job[0]]
	_camera.make_current()
	_camera.look_at_from_position(view[1], view[2])
	var formations: Node3D = _scene.get_node("Formations")
	formations.visible = job[1] != 0
	for volume in formations.get_children():
		if job[1] != 0:
			volume.max_steps = job[1]
	_frame = 0
