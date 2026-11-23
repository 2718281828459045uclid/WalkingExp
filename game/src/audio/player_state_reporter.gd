class_name PlayerStateReporter
extends Node
## Sends the player's state to SuperCollider (Lesson 04).
##
## Reads the Player node, builds two kinds of OSC message, and hands them
## to the "Osc" autoload (src/audio/osc_sender.gd):
##
##   /player/state  x y z speed ground   floats, floats, ..., int
##                  continuous, send_rate_hz times per second
##   /player/ground name                 string: "floor", "steep", "air"
##                  on change only, and once at startup
##
## x y z is the capsule's center in meters; speed is the horizontal
## speed in m/s; ground is Player.GroundState as an int (0 floor,
## 1 steep, 2 air). audio/supercollider/04_player_state.scd receives both.

const GROUND_NAMES: PackedStringArray = ["floor", "steep", "air"]

## The player to report. The scene assigns it.
@export var player: Player

## Rate of /player/state in messages per second. 0 stops the stream;
## /player/ground still goes out on change.
@export_range(0.0, 240.0) var send_rate_hz: float = 30.0:
	set(value):
		send_rate_hz = value
		_clock.rate_hz = value

## Where messages go. Left empty, _ready() takes the "Osc" autoload.
## Tests assign their own OscSender here.
var sender: OscSender

var _clock := RateClock.new(30.0)
var _last_ground := -1


func _ready() -> void:
	_clock.rate_hz = send_rate_hz
	if sender == null:
		sender = get_node_or_null("/root/Osc") as OscSender


func _physics_process(delta: float) -> void:
	if player == null or sender == null:
		return

	# Q: Why send from _physics_process() and not _process()?
	# A: The player moves in physics ticks (Lesson 02). Between two ticks
	#    its position does not change, so a render frame would only repeat
	#    the last state, and at 144 fps it would repeat it often.
	var ground := int(player.get_ground_state())
	if ground != _last_ground:
		_last_ground = ground
		sender.send("/player/ground", [GROUND_NAMES[ground]])

	if _clock.tick(delta):
		sender.send("/player/state", state_arguments(player))


## The arguments of one /player/state message, in address order.
static func state_arguments(body: Player) -> Array:
	var p := body.global_position
	var horizontal_speed := Vector2(body.velocity.x, body.velocity.z).length()
	# Q: Why float(p.x) when p.x is already a number?
	# A: p.x is a float, and the encoder tags floats "f". The explicit
	#    conversions make the type of every argument visible at the place
	#    where the message layout is defined. int() for ground does the
	#    same for "i": an enum value passed as is would also be an int,
	#    but the reader should not have to know that.
	return [float(p.x), float(p.y), float(p.z), float(horizontal_speed), int(body.get_ground_state())]
