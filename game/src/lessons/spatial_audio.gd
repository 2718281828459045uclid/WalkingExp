extends "res://src/lessons/footsteps.gd"
## Root script of scenes/lessons/06_spatial_audio.tscn.
##
## Extends src/lessons/footsteps.gd (Lesson 05), so every key of Lessons
## 01-05 still works. This script adds:
##   L  switches the listener between the camera and the player's head
##      (the CameraPivot node: head height, the camera's direction)
## and HUD lines for the wind and each emitter. The SpatialReporter node
## (src/audio/spatial_audio_reporter.gd) does the sending.

@onready var _spatial: SpatialAudioReporter = $SpatialReporter
@onready var _camera: Node3D = $Player/CameraPivot/SpringArm3D/Camera3D
@onready var _head: Node3D = $Player/CameraPivot


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("toggle_listener"):
		_spatial.listener = _head if _spatial.listener == _camera else _camera


func _update_hud() -> void:
	super()
	var listener_name := "camera" if _spatial.listener == _camera else "head"
	# Q: The azimuth is unwrapped and may read 540 degrees. Why wrap it here?
	# A: The HUD is for a person, who expects -180..180. The unwrapped
	#    value matters only to the Lag in SuperCollider.
	_hud_label.text += "\n\nlistener: %s   [L / L3]\nwind %.2f   from %+4.0f deg" % [
		listener_name,
		_spatial.wind_strength,
		rad_to_deg(wrapf(_spatial.wind_azimuth, -PI, PI)),
	]
	for emitter in $Emitters.get_children():
		if not emitter is SoundEmitter or not _spatial.last_spherical.has(emitter.emitter_id):
			continue
		var s: Vector3 = _spatial.last_spherical[emitter.emitter_id]
		_hud_label.text += "\n%d %-9s az %+4.0f  el %+3.0f  %5.1f m" % [
			emitter.emitter_id,
			emitter.kind,
			rad_to_deg(wrapf(s.x, -PI, PI)),
			rad_to_deg(s.y),
			s.z,
		]
