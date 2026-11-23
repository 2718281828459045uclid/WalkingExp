@tool
class_name SoundEmitter
extends Node3D
## A point in the world that makes a sound (Lesson 06).
##
## The node holds no audio. It names a SynthDef in
## audio/supercollider/06_spatial_audio.scd (`kind`) and gives it an id.
## SpatialAudioReporter (spatial_audio_reporter.gd) reads the position
## of every emitter, converts it to listener-relative coordinates, and
## sends them to SuperCollider, which runs one synth per emitter.
##
## A small sphere marks the emitter in the editor and in the game. It is
## an internal child: built when the node enters the tree, never saved
## into the .tscn file (CLAUDE.md, "Generated geometry").

## Number that identifies this emitter in OSC messages. Unique per scene.
@export var emitter_id: int = 0
## Name of the SynthDef that SuperCollider plays for this emitter.
@export var kind: StringName = &"crickets"
## Level sent to the synth, before distance attenuation.
@export_range(0.0, 1.0, 0.01) var amp: float = 0.3
## Shows a small sphere at the emitter.
@export var show_marker: bool = true:
	set(value):
		show_marker = value
		if _marker != null:
			_marker.visible = value

var _marker: MeshInstance3D


func _ready() -> void:
	_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.6, 1.0)
	sphere.material = material
	_marker.mesh = sphere
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = show_marker
	add_child(_marker, false, Node.INTERNAL_MODE_FRONT)
