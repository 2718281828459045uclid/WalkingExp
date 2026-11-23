extends "res://src/lessons/climbing.gd"
## Root script of scenes/lessons/16_crawling_and_scrambling.tscn.
##
## Extends src/lessons/climbing.gd (Lesson 15), so every key of Lessons
## 01-15 still works. The scene swaps three scripts and adds three nodes:
##   Player          scenes/crawling_player.tscn (CrawlingPlayer)
##   Stance          PostureController (src/crawl/posture_controller.gd)
##   BalanceMonitor  CrawlBalanceMonitor (src/crawl/crawl_balance_monitor.gd)
##   Crawl           a CrawlController (src/crawl/crawl_controller.gd), after
##                   Player in the tree
##   CrawlGap        a CrawlGap (src/world/crawl_gap.gd): a passage 0.9 m high
##   Slab            a RampTower (Lesson 02) with a 48 degree side
## This script adds:
##   F3   crawl, or back up (gamepad: Guide)
##   F4   shows or hides the collision shape and the crawl lines
## and key 4 (Lesson 14) now steps between standing and crouched, and from
## a crawl up to crouched, through PostureController.toggle_stance(); while
## climbing it pulls the hips in, as in Lesson 15.
## Scrambling starts and ends by itself (PostureController). Key 0 (Lesson
## 15) starts a climb only from an upright posture. HUD/RockLabel gets
## four lines.

@onready var _posture: PostureController = $Stance
@onready var _crawl: CrawlController = $Crawl
@onready var _gap: CrawlGap = $CrawlGap
@onready var _slab: RampTower = $Slab


func _ready() -> void:
	super()
	_place_gap()
	_place_slab()
	# Turn the camera toward the gap's entrance instead of the climbing face
	# (the same formula as in climbing.gd).
	var entrance := _gap.global_transform * Vector3(0.0, 0.0, _gap.floor_rect().end.y)
	var d := entrance - _player.global_position
	var pivot := _player.get_node("CameraPivot") as Node3D
	_player._rotate_camera(atan2(-d.x, -d.z) - pivot.rotation.y, 0.0)


## Q: How high does the gap's floor sit?
## A: At the highest terrain point under the floor (sampled on a 9 x 9
##    grid), so that no part of the terrain comes up through it. The floor
##    then stands above the terrain by up to the height range of its
##    footprint, and the ramps lead onto it.
func _place_gap() -> void:
	var rect := _gap.floor_rect()
	var highest := -INF
	for i in 9:
		for j in 9:
			var local := Vector3(rect.position.x + rect.size.x * i / 8.0, 0.0, rect.position.y + rect.size.y * j / 8.0)
			var world := _gap.global_transform * local
			highest = maxf(highest, _terrain.height_at(world.x, world.z))
	_gap.global_position.y = highest


## Q: How high does the slab stand?
## A: Its origin goes to the terrain height at the foot of its first ramp
##    (the +z side in its own frame), so that the slope starts at the
##    ground and rises platform_height to the top.
func _place_slab() -> void:
	var a := deg_to_rad(_slab.ramp_angles_degrees[0])
	var foot := _slab.global_transform * Vector3(0.0, 0.0, 0.5 * _slab.platform_size + _slab.platform_height / tan(a))
	_slab.global_position.y += _terrain.height_at(foot.x, foot.z) - foot.y


func _unhandled_input(event: InputEvent) -> void:
	# Q: Why intercept key 0 here, before the Lesson 15 handler?
	# A: The climb takes the body from the posture it is in. Lying on the
	#    ground, with the crawl shape, begin_climb() would start from a
	#    body whose shoulders are half a meter lower than its test
	#    assumes. The climb is refused, with a reason on the HUD.
	if event.is_action_pressed("toggle_climb") and _posture != null and _climb != null:
		var upright := _posture.posture == PostureController.Posture.STAND or _posture.posture == PostureController.Posture.CROUCH
		if not upright and _climb.state == ClimbController.State.WALKING:
			_climb.refusal = "not upright"
			return
	super(event)
	if _posture == null:
		return
	if event.is_action_pressed("toggle_crawl"):
		_posture.toggle_crawl()
	elif event.is_action_pressed("toggle_crawl_debug"):
		_crawl.debug_draw = not _crawl.debug_draw


func _update_hud() -> void:
	super()
	if _posture == null or not _player is CrawlingPlayer:
		return
	var body := _player as CrawlingPlayer
	var status := PostureController.POSTURE_NAMES[_posture.posture]
	if _posture.refusal != "":
		status += " (%s)" % _posture.refusal
	var air := _crawl.swinging_limb()
	var air_text := "-" if air < 0 else CrawlController.LIMB_NAMES[air]
	if _crawl.holding:
		air_text = "waits"
	var support := 0
	if _balance is CrawlBalanceMonitor:
		support = (_balance as CrawlBalanceMonitor).support_count
	var under := "-" if is_nan(body.floor_angle_degrees) else "%.0f°" % body.floor_angle_degrees
	var ahead := "-" if is_nan(_posture.slope_ahead_degrees) else "%.0f°" % _posture.slope_ahead_degrees
	var crawl_error := 0.0
	for i in 4:
		crawl_error = maxf(crawl_error, _crawl.limb_errors[i])
	# Q: Why four short lines?
	# A: RockLabel already holds the lines of Lessons 08-15 and reaches the
	#    bottom of a 720-pixel window; each line stays under about 52
	#    characters so that it ends inside the label. The slope is shown
	#    under the body / ahead of it; the margin is on the Lesson 13 line.
	#    "crawl error" is CrawlController's largest limb error; the climb
	#    line of Lesson 15 keeps its own "limb error".
	_rock_label.text += "\nposture: %s [4] [F3 / Guide]\nshape %s %.2f m   headroom %.2f m   slope %s / %s\ngait %.2f   air %s   shift %+.3f m   support %d\nlifts %d (%d unstable)   crawl error %.3f m   [F4]" % [
		status,
		CrawlingPlayer.SHAPE_NAMES[body.body_shape],
		body.shape_height(body.body_shape),
		body.headroom(),
		under,
		ahead,
		_crawl.phase,
		air_text,
		_crawl.shift,
		support,
		_crawl.lifts,
		_crawl.unstable_lifts,
		crawl_error,
	]
