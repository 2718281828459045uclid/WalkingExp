extends SceneTree
## Opens one scene in a window, waits a number of frames, saves a
## screenshot, and quits. Called by tools/render_check.sh.
##
## Headless runs draw nothing and have no GPU device. This windowed run
## shows the rendered result and can run compute shaders.
##
## Arguments after "--":  <res:// scene path> <output .png path> [frames]

var _frames_left := 60
var _output := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -s capture.gd -- <scene> <output.png> [frames]")
		quit(2)
		return
	_output = args[1]
	if args.size() > 2:
		_frames_left = int(args[2])

	var packed := load(args[0]) as PackedScene
	if packed == null:
		push_error("cannot load scene: " + args[0])
		quit(2)
		return
	root.add_child(packed.instantiate())
	_release_mouse()


func _process(_delta: float) -> bool:
	_release_mouse()
	_frames_left -= 1
	if _frames_left == 0:
		var error := root.get_texture().get_image().save_png(_output)
		quit(0 if error == OK else 1)
	return false


## Q: Why release the mouse on every frame?
## A: Player scripts capture the mouse in _ready(). During an automated run
##    that capture would take the pointer away from the person at the desk.
func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
