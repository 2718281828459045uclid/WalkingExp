class_name SpatialAudioReporter
extends Node
## Sends the positions of sound emitters, and the wind, to SuperCollider
## relative to a listener (Lesson 06).
##
## How the files control each other:
##   listener (a Node3D: the camera or the player's head)
##                                     this node reads its transform
##   SoundEmitter (sound_emitter.gd)   children of emitters_root; this
##                                     node reads id, kind, amp, position
##   ListenerMath (listener_math.gd)   world point -> azimuth, elevation,
##                                     distance; angle unwrapping
##   RateClock (rate_clock.gd)         which physics ticks send
##   OscSender.send_bundle (osc_sender.gd)
##                                     one bundle per send, tagged
##                                     "immediately"
##   audio/supercollider/06_spatial_audio.scd
##                                     one synth per emitter, one wind bed
##
## Messages:
##   /emitter/kind  id kind amp        i s f   every announce_interval s
##   /emitter/pos   id az el dist      i f f f send_rate_hz times per s
##   /wind          strength az        f f     with every /emitter/pos
##     az, el   radians, ListenerMath conventions; az is unwrapped, so it
##              may leave (-PI, PI] and changes by less than PI per send
##     dist     meters
##     strength 0..1, from the player's height
##     wind az  direction the wind comes from, seen from the listener

## The node whose transform is the listener. The scene assigns the camera.
@export var listener: Node3D
## The player, whose height sets the wind strength.
@export var player: Player
## Parent of the SoundEmitter nodes.
@export var emitters_root: Node
## Sends of /emitter/pos and /wind per second. 0 stops them.
@export_range(0.0, 240.0) var send_rate_hz: float = 30.0:
	set(value):
		send_rate_hz = value
		_clock.rate_hz = value
## Seconds between two announcements of every emitter's kind. A receiver
## started late learns the emitters within this time (Lesson 04 O3).
@export_range(0.1, 10.0) var announce_interval: float = 1.0

@export_group("Wind")
## Direction the wind comes from, in world space. Need not be unit length.
@export var wind_from: Vector3 = Vector3(1.0, 0.0, -0.5)
## Wind strength at wind_reference_height.
@export_range(0.0, 1.0) var wind_base: float = 0.3
## Strength gained per meter of height above wind_reference_height.
@export var wind_per_meter: float = 0.05
@export var wind_reference_height: float = 0.0

## Where messages go. Left empty, _ready() takes the "Osc" autoload.
var sender: OscSender

## Last values sent, for the HUD and the tests.
## emitter_id -> Vector3(azimuth, elevation, distance)
var last_spherical: Dictionary = {}
var wind_strength := 0.0
var wind_azimuth := 0.0
var sends := 0
var announcements := 0

var _clock := RateClock.new(30.0)
var _announce_timer := 0.0
var _emitters: Array[SoundEmitter] = []


func _ready() -> void:
	_clock.rate_hz = send_rate_hz
	if sender == null:
		sender = get_node_or_null("/root/Osc") as OscSender
	if emitters_root != null:
		for child in emitters_root.get_children():
			if child is SoundEmitter:
				_emitters.append(child)
	# Q: Why start the timer full?
	# A: The first physics tick then announces every emitter at once, so
	#    the receiver knows the kinds before the first positions arrive.
	_announce_timer = announce_interval


func _physics_process(delta: float) -> void:
	if listener == null or sender == null:
		return
	_announce_timer += delta
	if _announce_timer >= announce_interval:
		_announce_timer = 0.0
		_announce()
	if _clock.tick(delta):
		_send_positions()


## Sends /emitter/kind for every emitter, in one bundle.
func _announce() -> void:
	var messages: Array = []
	for emitter in _emitters:
		messages.append(["/emitter/kind", [emitter.emitter_id, String(emitter.kind), float(emitter.amp)]])
	if messages.is_empty():
		return
	# A time of 0 makes the tag "immediately" (OscBundle, Lesson 05).
	sender.send_bundle(0.0, messages)
	announcements += 1


## Sends /emitter/pos for every emitter and /wind, in one bundle.
func _send_positions() -> void:
	var view := listener.global_transform
	var messages: Array = []
	for emitter in _emitters:
		var s := ListenerMath.spherical_from(view, emitter.global_position)
		# Q: What is the previous azimuth on the first send?
		# A: There is none, so the azimuth is used as computed. From then
		#    on each azimuth is unwrapped toward the one sent before it.
		if last_spherical.has(emitter.emitter_id):
			var previous: Vector3 = last_spherical[emitter.emitter_id]
			s.x = ListenerMath.unwrap_angle(previous.x, s.x)
		last_spherical[emitter.emitter_id] = s
		messages.append(["/emitter/pos", [emitter.emitter_id, float(s.x), float(s.y), float(s.z)]])

	var height := player.global_position.y if player != null else wind_reference_height
	wind_strength = wind_strength_at(height, wind_base, wind_per_meter, wind_reference_height)
	var azimuth := ListenerMath.direction_azimuth(view, wind_from)
	wind_azimuth = azimuth if sends == 0 else ListenerMath.unwrap_angle(wind_azimuth, azimuth)
	messages.append(["/wind", [float(wind_strength), float(wind_azimuth)]])

	sender.send_bundle(0.0, messages)
	sends += 1


## Wind strength in [0, 1] at a height: a straight line, clamped.
static func wind_strength_at(height: float, base: float, per_meter: float, reference_height: float) -> float:
	return clampf(base + (height - reference_height) * per_meter, 0.0, 1.0)
