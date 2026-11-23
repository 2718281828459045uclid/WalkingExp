extends "res://src/lessons/osc_bridge.gd"
## Root script of scenes/lessons/05_footsteps.tscn.
##
## Extends src/lessons/osc_bridge.gd (Lesson 04), so every key of Lessons
## 01-04 still works. This script adds:
##   K  toggles the FootstepReporter's timing: time-tagged bundles or
##      immediate messages
## and HUD lines for the last footstep. The Footsteps node
## (src/audio/footstep_reporter.gd) detects and sends the steps.

const TIMING_NAMES: PackedStringArray = ["immediate", "time-tagged"]

@onready var _footsteps: FootstepReporter = $Footsteps


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_action_pressed("toggle_step_timing"):
		if _footsteps.timing == FootstepReporter.Timing.TIMETAGGED:
			_footsteps.timing = FootstepReporter.Timing.IMMEDIATE
		else:
			_footsteps.timing = FootstepReporter.Timing.TIMETAGGED


func _update_hud() -> void:
	super()
	var timing_text := TIMING_NAMES[_footsteps.timing]
	if _footsteps.timing == FootstepReporter.Timing.TIMETAGGED:
		timing_text += " +%d ms" % roundi(_footsteps.latency_seconds * 1000.0)
	_hud_label.text += "\n\nsteps: %d   timing: %s   [K / B]\nclock lag %.1f ms   resets %d" % [
		_footsteps.steps_sent,
		timing_text,
		_footsteps.clock_lag * 1000.0,
		_footsteps.clock_resets,
	]
	var a := _footsteps.last_arguments
	if a.is_empty():
		return
	# a = [foot, impact, slope, grass, dirt, rock]
	var weights := Vector3(a[3], a[4], a[5])
	_hud_label.text += "\nlast: %s  %s  impact %.2f m/s  slope %+.1f deg\n      grass %.2f  dirt %.2f  rock %.2f" % [
		["left", "right", "both"][a[0]],
		SurfaceClassifier.SURFACE_NAMES[SurfaceClassifier.dominant(weights)],
		a[1],
		a[2],
		a[3],
		a[4],
		a[5],
	]
