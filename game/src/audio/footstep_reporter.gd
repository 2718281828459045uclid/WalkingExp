class_name FootstepReporter
extends Node
## Sends footstep events to SuperCollider, stamped with the time they
## should sound (Lesson 05).
##
## How the files control each other:
##   Player (src/player/player.gd)        moves; this node only reads it
##   GaitClock (gait_clock.gd)            distance -> foot strikes
##   SurfaceClassifier (surface_classifier.gd)
##                                        position, normal -> grass/dirt/rock
##   OscSender.send_bundle (osc_sender.gd) + OscBundle (osc_bundle.gd)
##                                        message + time tag -> UDP
##   audio/supercollider/05_footsteps.scd plays the step at the time tag
##
## Message (one per strike):
##   /foot/step  foot impact slope grass dirt rock     i f f f f f
##     foot    0 left, 1 right, 2 both (landing after air)
##     impact  m/s: horizontal speed for a step, falling speed for a landing
##     slope   degrees along the direction of travel; + uphill, - downhill
##     grass dirt rock   surface weights, sum 1
##
## Timing:
##   IMMEDIATE   plain message, sent in the tick that detected the strike.
##               SuperCollider plays it when it arrives (Lesson 04 style).
##   TIMETAGGED  bundle with time tag = strike time + latency_seconds.
##               SuperCollider plays it at the tag, not at arrival.

enum Timing { IMMEDIATE, TIMETAGGED }

const FOOT_BOTH := 2

## The player to listen to. The scene assigns it.
@export var player: Player
## The painted terrain material (terrain_painted.gdshader). Its rule
## parameters and noise texture drive the surface weights. Empty: every
## step reports grass.
@export var surface_material: ShaderMaterial
@export var timing: Timing = Timing.TIMETAGGED
## Seconds added to each strike time. Must exceed the largest delay
## between a strike and its arrival in sclang, or steps arrive late.
@export_range(0.0, 0.5, 0.001) var latency_seconds: float = 0.05
## Meters per step for the gait clock.
@export_range(0.2, 2.0, 0.01) var step_length: float = 0.75
## Distance from the capsule center down to the soles, in meters.
@export var foot_offset: float = 0.9
## If the simulated clock drifts more than this from the wall clock, it
## is reset to the wall clock (after a long pause or a debugger break).
@export var max_clock_drift: float = 0.25

## Where messages go. Left empty, _ready() takes the "Osc" autoload.
var sender: OscSender

## Values of the last event, for the HUD and the tests.
var steps_sent := 0
var last_arguments: Array = []
var last_event_time := 0.0
## Wall clock minus simulated clock at the last tick, in seconds.
var clock_lag := 0.0
var clock_resets := 0

var gait := GaitClock.new()
var classifier := SurfaceClassifier.new()

var _anchor := 0.0
var _simulated := 0.0
var _last_position := Vector3.ZERO
var _last_vertical_speed := 0.0
var _was_on_floor := false
var _started := false


func _ready() -> void:
	if sender == null:
		sender = get_node_or_null("/root/Osc") as OscSender
	if surface_material != null:
		classifier.read_material(surface_material)


func _physics_process(delta: float) -> void:
	if player == null or sender == null:
		return
	gait.step_length = step_length
	var tick_end := _advance_clock(delta)

	var position := player.global_position
	var on_floor := player.get_ground_state() == Player.GroundState.FLOOR
	if not _started:
		_started = true
		_last_position = position
		_was_on_floor = on_floor
		_last_vertical_speed = player.velocity.y
		return

	if on_floor and not _was_on_floor:
		# Q: Why the vertical speed of the previous tick?
		# A: move_and_slide() sets velocity.y to about 0 when the body
		#    lands. The speed it hit the ground with is the one before.
		_emit(FOOT_BOTH, maxf(-_last_vertical_speed, 0.0), tick_end)
		# Start the next stride half a step in, so the first footfall
		# after landing comes after half a step length.
		gait.phase = floorf(gait.phase) + 0.5
	elif on_floor:
		var travelled := position.distance_to(_last_position)
		if gait.advance(travelled):
			# Q: When inside this tick did the foot strike?
			# A: The tick covers [tick_end - delta, tick_end]. The gait
			#    clock reports the fraction f of the tick at the strike.
			var strike_time := tick_end - (1.0 - gait.strike_fraction) * delta
			var speed := Vector2(player.velocity.x, player.velocity.z).length()
			_emit(gait.last_foot(), speed, strike_time)

	_last_position = position
	_was_on_floor = on_floor
	_last_vertical_speed = player.velocity.y


## Advances the simulated clock by one tick and returns the Unix time at
## the end of the tick.
##
## Q: Why not read the wall clock (Time.get_unix_time_from_system()) here?
## A: Godot runs physics ticks at the start of a render frame, several in
##    a row after a slow frame. The wall clock at a tick therefore
##    scatters by milliseconds (Lesson 04 O5). The simulated clock counts
##    exact ticks: anchor + n * delta. Strikes stamped with it keep the
##    rhythm of the simulation, and the scatter stays out of the tags.
func _advance_clock(delta: float) -> float:
	var wall := Time.get_unix_time_from_system()
	if _anchor == 0.0:
		_anchor = wall
	_simulated += delta
	var tick_end := _anchor + _simulated
	clock_lag = wall - tick_end
	# Q: What if the simulation falls far behind the wall clock?
	# A: Godot drops physics ticks when it cannot catch up (more than
	#    max_physics_steps_per_frame per frame), or the game was paused.
	#    Then anchor + n * delta lies in the past, and every tag would be
	#    late. Re-anchoring moves the simulated clock to the wall clock.
	# Q: What if the simulated clock runs ahead of the wall clock?
	# A: A tick cannot happen before its own time; Godot runs a tick only
	#    after real time has passed it. A negative lag means the anchor was
	#    taken late (the first tick came after a slow scene load, and the
	#    catch-up ticks that followed overtook it). Moving the anchor back
	#    keeps the simulated clock on the earliest consistent time.
	if clock_lag < 0.0:
		_anchor = wall - _simulated
		tick_end = wall
		clock_lag = 0.0
	elif clock_lag > max_clock_drift:
		_anchor = wall - _simulated
		tick_end = wall
		clock_lag = 0.0
		clock_resets += 1
	return tick_end


func _emit(foot: int, impact: float, event_time: float) -> void:
	var feet := player.global_position + Vector3.DOWN * foot_offset
	var n := player.get_floor_normal()
	var direction := Vector2(player.velocity.x, player.velocity.z)
	var weights := classifier.weights_at(feet, n)
	var arguments := step_arguments(foot, impact, signed_slope_degrees(n, direction), weights)
	last_arguments = arguments
	last_event_time = event_time
	steps_sent += 1
	if timing == Timing.TIMETAGGED:
		sender.send_bundle(event_time + latency_seconds, [["/foot/step", arguments]])
	else:
		sender.send("/foot/step", arguments)


## The arguments of one /foot/step message, in address order.
static func step_arguments(foot: int, impact: float, slope: float, weights: Vector3) -> Array:
	return [int(foot), float(impact), float(slope), float(weights.x), float(weights.y), float(weights.z)]


## Slope of the ground along a horizontal direction, in degrees:
## positive uphill, negative downhill, 0 across the slope or at rest.
##
## Q: How does the normal give the slope along a direction?
## A: On a graph y = h(x, z) the normal is proportional to
##    (-h_x, 1, -h_z) (Lesson 01). So h_x = -n.x / n.y and h_z = -n.z / n.y.
##    The directional derivative along the unit vector d (Lesson 02) is
##      D_d h = h_x d.x + h_z d.y = -(n.x d.x + n.z d.y) / n.y
##    the rise per meter walked. atan turns the rise into an angle.
static func signed_slope_degrees(n: Vector3, direction: Vector2) -> float:
	if direction.length() < 1e-4 or n.y <= 1e-4:
		return 0.0
	var d := direction.normalized()
	var rise := -(n.x * d.x + n.z * d.y) / n.y
	return rad_to_deg(atan(rise))
