class_name StanceController
extends Node
## Shifts the body's weight from the triggers and the stick, and switches
## between a standing and a crouched stance (Lesson 14).
##
## How the files relate:
##   TriggerResponse (src/input/trigger_response.gd)  raw trigger -> shaped
##   Player.stick_shaped (Lesson 02 StickResponse)     forward lean
##   OnePoleFilter, CriticalSpring (src/input/)        smoothing
##   BalanceMonitor (Lesson 13)                        sets rig.position to
##                                                     rest + sway each tick
##   this node                                         adds the weight shift
##                                                     and the crouch
##   FootRig (Lesson 12)                               holds the planted feet
##                                                     and bends the legs
##
## Order inside one physics tick:
##   BalanceMonitor (priority -1, earlier in the tree)  rig = rest + sway
##   StanceController (priority -1, later in the tree)  rig += shift, crouch
##   Player (priority 0)                                moves, solves the legs
##
## The weight shift, in the body's ground frame (x right, y forward):
##   x = (right trigger - left trigger) * side_range
##   y = |shaped stick| * forward_lean
## Keyboard fallback: keys 5 and 6 press the left and right trigger
## actions at full strength; the filter turns the step into a ramp.

## The two stances.
enum Stance {
	STANDING,
	CROUCHED,
}

## How the raw targets become the applied offsets.
enum Smoothing {
	NONE,            ## The target is applied as read.
	ONE_POLE,        ## OnePoleFilter with time_constant.
	CRITICAL,        ## CriticalSpring, exact step.
	CRITICAL_EULER,  ## CriticalSpring, semi-implicit Euler (tick-rate dependent).
}

const STANCE_NAMES: PackedStringArray = ["standing", "crouched"]
const SMOOTHING_NAMES: PackedStringArray = ["none", "one-pole", "critical spring", "spring (Euler)"]

## The monitor whose rig this node moves. The scene assigns it.
@export var monitor: BalanceMonitor
## The player whose shaped stick leans the body forward.
@export var player: Player
## Shapes both triggers. Empty: the raw value is used.
@export var trigger_response: TriggerResponse
@export_group("Weight shift")
## Sideways shift of the rig at full trigger, in meters.
@export var side_range: float = 0.10
## Forward shift of the rig at full stick, in meters.
@export var forward_lean: float = 0.04
## Lowering of the rig in the crouched stance, in meters.
@export var crouch_depth: float = 0.25
@export_group("Smoothing")
@export var smoothing: Smoothing = Smoothing.CRITICAL:
	set(value):
		smoothing = value
		# Q: Why start the new filter where the old one stopped?
		# A: Each filter keeps its own state. Without the copy, switching
		#    would jump the body to wherever the other filter last was.
		_shift_pole.reset(shift)
		_shift_spring.reset(shift)
		_crouch_pole.reset(Vector2(crouch, 0.0))
		_crouch_spring.reset(Vector2(crouch, 0.0))
## Time constant of the one-pole filter, in seconds.
@export var time_constant: float = 0.12
## Angular frequency of the spring, in radians per second.
@export var spring_frequency: float = 12.0

var stance := Stance.STANDING
## Raw triggers of the last tick: x left, y right.
var trigger_raw := Vector2.ZERO
## Shaped triggers of the last tick: x left, y right.
var trigger_shaped := Vector2.ZERO
## Weight shift before smoothing, meters (x right, y forward).
var shift_target := Vector2.ZERO
## Weight shift applied to the rig, meters.
var shift := Vector2.ZERO
## Crouch depth applied to the rig, meters (positive is lower).
var crouch := 0.0

var _shift_pole := OnePoleFilter.new()
var _shift_spring := CriticalSpring.new()
var _crouch_pole := OnePoleFilter.new()
var _crouch_spring := CriticalSpring.new()


func _ready() -> void:
	# Q: Why the same priority as BalanceMonitor and not a lower one?
	# A: The monitor sets rig.position to its rest position plus the sway;
	#    this node adds to that. It must run after the monitor and before
	#    the player. With equal priorities Godot runs nodes in tree order,
	#    and the scene places this node after BalanceMonitor.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	read_input()
	update(delta)
	apply_to_rig()


## Reads the triggers and the stick into shift_target.
func read_input() -> void:
	# Q: Why the raw strength?
	# A: The actions have deadzone 0, so the raw and the plain strength
	#    agree. Reading raw states the intent: the shaping is the
	#    TriggerResponse's job, not the InputMap's.
	trigger_raw = Vector2(
		Input.get_action_raw_strength("shift_weight_left"),
		Input.get_action_raw_strength("shift_weight_right")
	)
	trigger_shaped = trigger_raw
	if trigger_response != null:
		trigger_shaped = Vector2(trigger_response.apply(trigger_raw.x), trigger_response.apply(trigger_raw.y))
	var stick := player.stick_shaped.length() if player != null else 0.0
	shift_target = Vector2((trigger_shaped.y - trigger_shaped.x) * side_range, stick * forward_lean)


## Steps the filters by delta seconds toward the targets.
func update(delta: float) -> void:
	_shift_pole.time_constant = time_constant
	_crouch_pole.time_constant = time_constant
	_shift_spring.frequency = spring_frequency
	_crouch_spring.frequency = spring_frequency
	var crouch_target := Vector2(crouch_depth if stance == Stance.CROUCHED else 0.0, 0.0)
	match smoothing:
		Smoothing.NONE:
			shift = shift_target
			crouch = crouch_target.x
		Smoothing.ONE_POLE:
			shift = _shift_pole.step(shift_target, delta)
			crouch = _crouch_pole.step(crouch_target, delta).x
		Smoothing.CRITICAL:
			shift = _shift_spring.step(shift_target, delta)
			crouch = _crouch_spring.step(crouch_target, delta).x
		Smoothing.CRITICAL_EULER:
			shift = _shift_spring.step_euler(shift_target, delta)
			crouch = _crouch_spring.step_euler(crouch_target, delta).x


## Adds the shift and the crouch to the rig's position inside BodyMesh.
func apply_to_rig() -> void:
	if monitor == null or monitor.rig == null:
		return
	# BodyMesh's frame has -z forward, as in BalanceMonitor._sway().
	monitor.rig.position += Vector3(shift.x, -crouch, -shift.y)


func toggle_stance() -> void:
	stance = Stance.CROUCHED if stance == Stance.STANDING else Stance.STANDING


func cycle_smoothing() -> void:
	smoothing = ((smoothing + 1) % Smoothing.size()) as Smoothing
