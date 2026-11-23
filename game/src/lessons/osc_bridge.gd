extends "res://src/lessons/painting_the_ground.gd"
## Root script of scenes/lessons/04_osc_bridge.tscn.
##
## Extends src/lessons/painting_the_ground.gd (Lesson 03), so every key of
## Lessons 01-03 still works. This script adds:
##   O  cycles the StateReporter's send rate: off, 10, 30, 60 Hz
## and HUD lines for the OSC destination and the traffic so far.
## The StateReporter node (src/audio/player_state_reporter.gd) does the
## sending through the "Osc" autoload (src/audio/osc_sender.gd).

const SEND_RATES: PackedFloat64Array = [0.0, 10.0, 30.0, 60.0]

@onready var _reporter: PlayerStateReporter = $StateReporter

# Traffic counted over the last full second, for the HUD.
var _window_start_ms := 0
var _window_start_messages := 0
var _window_start_bytes := 0
var _messages_per_second := 0
var _bytes_per_second := 0


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("cycle_osc_rate"):
		var i := SEND_RATES.find(_reporter.send_rate_hz)
		_reporter.send_rate_hz = SEND_RATES[(i + 1) % SEND_RATES.size()]


func _update_hud() -> void:
	super()
	# Q: _update_hud() runs once from sandbox.gd's _ready(). Is $StateReporter ready then?
	# A: Yes. Godot calls _ready() on children before their parent, and
	#    @onready variables are set just before the parent's _ready() runs.
	var osc := _reporter.sender
	if osc == null:
		_hud_label.text += "\n\nosc: no Osc autoload"
		return
	_count_traffic(osc)
	var rate_text := "off" if _reporter.send_rate_hz <= 0.0 else "%d Hz" % int(_reporter.send_rate_hz)
	_hud_label.text += "\n\nosc -> %s:%d   state %s   [O / X]\nsent: %d messages, %d bytes   (%d msg/s, %d B/s)" % [
		osc.host,
		osc.port,
		rate_text,
		osc.messages_sent,
		osc.bytes_sent,
		_messages_per_second,
		_bytes_per_second,
	]


## Updates the per-second counts once every 1000 ms.
func _count_traffic(osc: OscSender) -> void:
	var now := Time.get_ticks_msec()
	# Q: Why start the first window here and not at 0 ms?
	# A: Loading the scene takes time. A window that started at 0 ms would
	#    divide the first second's messages by the load time as well.
	if _window_start_ms == 0:
		_window_start_ms = now
		return
	if now - _window_start_ms < 1000:
		return
	_messages_per_second = osc.messages_sent - _window_start_messages
	_bytes_per_second = osc.bytes_sent - _window_start_bytes
	_window_start_ms = now
	_window_start_messages = osc.messages_sent
	_window_start_bytes = osc.bytes_sent
