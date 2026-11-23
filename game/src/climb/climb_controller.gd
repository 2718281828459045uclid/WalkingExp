class_name ClimbController
extends Node3D
## Climbing: a state machine for the body and one for each limb
## (Lesson 15).
##
## How the files relate:
##   ClimbableRock (climbable_rock.gd)  the holds, the face normal
##   HoldFinder (hold_finder.gd)        reach-sphere queries
##   ReachSolver (reach_solver.gd)      places the pelvis so the holding
##                                      limbs reach their holds
##   TwoBoneIk (Lesson 12), Fabrik      solve each arm and each leg
##   CriticalSpring (Lesson 14)         smooths the hand that reaches
##   StanceController (Lesson 14)       optional: its crouch pulls the
##                                      hips toward the rock
##   ClimbingPlayer (climbing_player.gd)  gives up its capsule while
##                                      `climbing` is true
##   ClimbBalanceMonitor                reads contact_points() and the
##                                      face normal for the hand load
##   src/lessons/climbing.gd            key 0 starts and ends a climb
##
## Body states:
##   WALKING   ClimbingPlayer walks; this node waits for begin_climb()
##   CLIMBING  four limbs, each HOLD, REACH or MOVE (below)
##   MANTLING  both hands hold top-out holds: the body moves onto the top
##             of the rock and walks again
##
## Limb states:
##   HOLD   the limb is on its hold (a foot may stand on the ground)
##   REACH  a hand has let go; the stick moves it over the face; the
##          nearest hold within the reach sphere is the candidate
##   MOVE   the limb travels to a hold along an arc in move_time seconds
##
## One limb moves at a time; the other three hold (README P7).
##
## Control while climbing (keyboard / gamepad):
##   5 / left trigger, held    the left hand reaches; release grabs
##   6 / right trigger, held   the right hand reaches
##   WASD / left stick         moves the reaching hand
##   4 / D-pad up              (Lesson 14 crouch) pulls the hips in
##   0 / Start                 lets go (src/lessons/climbing.gd)
##   F2                        switches the arm solver
## The feet follow by themselves after each hand move.
## The Lesson 14 weight shift (also read from the triggers) still moves
## the rig inside BodyMesh; _pose() writes every joint relative to the
## rig, so the shift does not move the climbing body.
##
## Order inside one physics tick:
##   BalanceMonitor, StanceController (priority -1)  measure, rig.position
##   Player (priority 0, earlier in the tree)        camera and stick only
##   this node (priority 0, after Player)            limbs, pelvis, pose

## A limb reached a hold (for sound and the HUD).
signal limb_placed(limb: int, hold: HoldFinder.Hold)
## The body state changed.
signal state_changed(state: int)

enum State {
	WALKING,
	CLIMBING,
	MANTLING,
}

enum Limb {
	HAND_L,
	HAND_R,
	FOOT_L,
	FOOT_R,
}

enum LimbState {
	HOLD,
	REACH,
	MOVE,
}

## Which solver turns the arms (the legs always use TwoBoneIk).
enum ArmSolver {
	TWO_BONE,  ## Law of cosines and a pole (Lesson 12).
	FABRIK,    ## Iterative, no pole, warm-started from the last pose.
}

const STATE_NAMES: PackedStringArray = ["walking", "climbing", "mantling"]
const LIMB_NAMES: PackedStringArray = ["hand L", "hand R", "foot L", "foot R"]
const LIMB_STATE_NAMES: PackedStringArray = ["hold", "reach", "move"]
const ARM_SOLVER_NAMES: PackedStringArray = ["two-bone", "FABRIK"]
const REACH_ACTIONS: PackedStringArray = ["shift_weight_left", "shift_weight_right"]

## The player to move. The scene assigns it.
@export var player: ClimbingPlayer
## The rock to climb. The scene assigns it.
@export var rock: ClimbableRock
## Optional. Its crouch (0 to crouch_depth) moves the hips from
## wall_clearance to min_clearance.
@export var stance: StanceController
@export_group("Reach")
## Fraction of the full limb length that counts as reach.
@export_range(0.8, 1.0, 0.005) var reach_fraction: float = 0.98
## Speed of the reaching hand at full stick, m/s.
@export var reach_speed: float = 0.9
## Frequency of the spring that smooths the reaching hand, rad/s.
@export var reach_spring_frequency: float = 14.0
## A trigger above this raw value starts a reach; below it, the hand grabs.
@export_range(0.05, 0.95, 0.05) var trigger_threshold: float = 0.3
## Largest distance from the reaching hand to a candidate hold, meters.
@export var snap_radius: float = 0.3
## Time a limb takes to travel to its hold, seconds.
@export var move_time: float = 0.35
## Height of the travel arc away from the face, meters.
@export var move_lift: float = 0.08
@export_group("Feet")
## A foot hold lies at least this far below the hip, meters.
@export var foot_hip_gap: float = 0.4
## A foot hold lies at least this far below the lower hand, meters.
@export var foot_hand_gap: float = 0.6
## A foot moves only to a hold this much higher than its own, meters.
@export var foot_step_threshold: float = 0.1
## Height given up per meter of sideways distance from the hip.
@export var foot_lateral_cost: float = 0.5
@export_group("Body")
## Largest distance from the pelvis to the face for begin_climb(), meters.
@export var grab_distance: float = 0.9
## Preferred distance of the pelvis in front of the holds, meters.
@export var wall_clearance: float = 0.3
## Smallest distance of the pelvis in front of the holds, meters.
@export var min_clearance: float = 0.2
## Preferred drop of the shoulders below the hands, as a fraction of the
## arm's reach.
@export_range(0.0, 1.0, 0.05) var arm_hang: float = 0.8
## Preferred height of the pelvis above the feet, fraction of the leg.
@export_range(0.0, 1.0, 0.05) var leg_stand: float = 0.75
## Time constant of the pelvis, seconds.
@export var pelvis_time_constant: float = 0.18
## Time of the mantle onto the top, seconds.
@export var mantle_time: float = 1.2
@export_group("Arms")
@export var arm_solver := ArmSolver.TWO_BONE
## FABRIK: iterations per tick and the end distance that stops them.
@export var fabrik_iterations: int = 10
@export var fabrik_tolerance: float = 1e-4
@export_group("")
## Draws the reach spheres, the candidate, the pelvis and the contacts.
@export var debug_draw := true:
	set(value):
		debug_draw = value
		if _debug_instance != null:
			_debug_instance.visible = value
			if not value:
				_debug_mesh.clear_surfaces()


## The state of one limb. Points are world space.
class LimbData:
	var state := LimbState.HOLD
	## The hold, or null for a foot that hangs free.
	var hold: HoldFinder.Hold
	## Where the end of the limb is this tick (hand or ankle).
	var point := Vector3.ZERO
	## MOVE: start point, destination hold, progress in [0, 1].
	var from_point := Vector3.ZERO
	var to_hold: HoldFinder.Hold
	var progress := 0.0
	## REACH: the stick's offset from the hold in the face plane
	## (x right, y up), meters, and the spring that smooths it.
	var aim := Vector2.ZERO
	var spring := CriticalSpring.new()


var state := State.WALKING
var limbs: Array[LimbData] = [LimbData.new(), LimbData.new(), LimbData.new(), LimbData.new()]
## The pelvis (the Hips joint), world space, smoothed.
var pelvis := Vector3.ZERO
## The pelvis the reach solver asked for this tick.
var pelvis_target := Vector3.ZERO
## ReachSolver residual and sweeps of this tick.
var residual := 0.0
var sweeps := 0
## Distance from each limb's end to its target after the pose, meters.
var limb_errors := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## FABRIK iterations of the last tick, per arm.
var fabrik_iteration_counts := PackedInt32Array([0, 0])
## The hold the reaching hand would grab now, or null.
var candidate: HoldFinder.Hold
## Height of the pelvis above its height at begin_climb(), meters.
var ascent := 0.0
## Limb moves completed since begin_climb() (hands, feet).
var hand_moves := 0
var foot_moves := 0
## Time of the last climbing tick, milliseconds.
var climb_milliseconds := 0.0
## Why the last begin_climb() refused, or "" after a start.
var refusal := ""

var _rig: FootRig
var _start_height := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_progress := 0.0
var _saved_solver := FootRig.Solver.OWN
## Rest offsets in the body frame (x right, y up, z back), from the skeleton.
var _shoulder_offsets: Array[Vector3] = []
var _hip_offsets: Array[Vector3] = []
## FABRIK warm start: [shoulder, elbow, hand] per arm, world space.
var _arm_joints: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _debug_instance: MeshInstance3D
var _debug_mesh: ImmediateMesh


func _ready() -> void:
	if player != null:
		_rig = player.rig as FootRig
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "ClimbDebug"
	_debug_instance.mesh = _debug_mesh
	_debug_instance.top_level = true
	_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.vertex_color_use_as_albedo = true
	lines.no_depth_test = true
	_debug_instance.material_override = lines
	add_child(_debug_instance, false, Node.INTERNAL_MODE_FRONT)
	_debug_instance.visible = debug_draw


func _physics_process(delta: float) -> void:
	if _rig == null or rock == null:
		return
	var start := Time.get_ticks_usec()
	match state:
		State.CLIMBING:
			_climb_tick(delta)
		State.MANTLING:
			_mantle_tick(delta)
	if state != State.WALKING:
		climb_milliseconds = (Time.get_ticks_usec() - start) / 1000.0
	_draw_debug()


# --- Geometry of the body and the face ---------------------------------

## The outward normal of the face, world space.
func face_normal() -> Vector3:
	return rock.face_normal_world()


## The basis of a body that faces the rock: x right, y up, z = the face
## normal (the body's back, since the body faces -z).
func body_basis() -> Basis:
	var n := face_normal()
	var right := Vector3.UP.cross(n).normalized()
	return Basis(right, Vector3.UP, right.cross(Vector3.UP))


## A point on the plane of the holds.
func face_point() -> Vector3:
	var sum := Vector3.ZERO
	for hold in rock.holds:
		sum += hold.position
	return sum / maxi(rock.holds.size(), 1)


## Signed distance of a point in front of the plane of the holds, meters.
func face_distance(p: Vector3) -> float:
	return (p - face_point()).dot(face_normal())


## Shoulder (hands) or hip joint (feet) of a limb, for a pelvis at p.
func limb_root(limb: int, p: Vector3) -> Vector3:
	return p + body_basis() * _root_offset(limb)


## Reach of a limb: reach_fraction of its two bones.
func limb_reach(limb: int) -> float:
	var q := _rig.proportions
	var length := q.upper_arm_length + q.forearm_length if _is_hand(limb) else q.thigh_length + q.shin_length
	return reach_fraction * length


## Where the end of a limb goes on a hold: the hand a little in front of
## the surface, the ankle above it and back from the face, so that the
## toes stand on the hold.
func limb_target(limb: int, hold: HoldFinder.Hold) -> Vector3:
	if _is_hand(limb):
		return hold.position + hold.normal * 0.03
	var up := Vector3.UP * _rig.proportions.ankle_height
	if hold.on_ground:
		return hold.position + up
	return hold.position + up + face_normal() * 0.1


## Points that carry the body: [point, is_hand] for every limb in HOLD.
func contact_points() -> Array:
	var result := []
	for i in 4:
		var limb := limbs[i]
		if limb.state == LimbState.HOLD and limb.hold != null:
			result.append([limb.hold.position, _is_hand(i)])
	return result


## The preferred distance of the pelvis from the face this tick.
##
## Q: How does the Lesson 14 crouch enter?
## A: As a fraction: crouch / crouch_depth runs from 0 (standing) to 1
##    (crouched). The clearance slides from wall_clearance to
##    min_clearance by that fraction: crouching on the wall brings the
##    hips in.
func clearance() -> float:
	var fraction := 0.0
	if stance != null and stance.crouch_depth > 0.0:
		fraction = clampf(stance.crouch / stance.crouch_depth, 0.0, 1.0)
	return lerpf(wall_clearance, min_clearance, fraction)


## Switches the arm solver between TwoBoneIk and Fabrik.
func cycle_arm_solver() -> void:
	arm_solver = ((arm_solver + 1) % ArmSolver.size()) as ArmSolver
	# A fresh FABRIK start: the next tick seeds it from the two-bone pose.
	_arm_joints = [PackedVector3Array(), PackedVector3Array()]


# --- Entering and leaving ----------------------------------------------

## Starts a climb if the face is close and each hand has a hold in reach.
## Returns whether it started.
func begin_climb() -> bool:
	if state != State.WALKING:
		return false
	if _rig == null or rock == null or rock.holds.is_empty():
		refusal = "no holds"
		return false
	_cache_offsets()
	var n := face_normal()
	var p := _rig.global_transform * Vector3(0.0, _rig.proportions.hip_height(), 0.0)
	# Q: How far is the pelvis from the face?
	# A: The signed distance to the plane through face_point() with
	#    normal n: (p - face_point) . n. It is negative behind the plane:
	#    on top of the rock, or beside it and past the face.
	var distance := face_distance(p)
	if distance > grab_distance:
		refusal = "face too far"
		return false
	if distance < 0.0:
		refusal = "behind the face"
		return false
	# The capsule keeps the standing body 0.35 m or more from the rock.
	# Grabbing, the body steps in to wall_clearance; reach is tested there.
	p -= n * (distance - wall_clearance)

	var used: Array = []
	var hands: Array[HoldFinder.Hold] = []
	for i in 2:
		var root := limb_root(i, p)
		var aim := root + Vector3.UP * 0.4
		var found := HoldFinder.in_reach(rock.holds, root, limb_reach(i), aim, used)
		if found.is_empty():
			refusal = "no hold in reach"
			return false
		hands.append(found[0])
		used.append(found[0])

	for i in 4:
		var limb := limbs[i]
		limb.state = LimbState.HOLD
		limb.hold = hands[i] if i < 2 else _ground_hold(i, p)
		limb.to_hold = null
	pelvis = p
	pelvis_target = p
	_start_height = p.y
	ascent = 0.0
	hand_moves = 0
	foot_moves = 0
	candidate = null
	_arm_joints = [PackedVector3Array(), PackedVector3Array()]
	player.climbing = true
	# Q: Why switch FootRig to its own solver?
	# A: With the ENGINE solver (Lesson 12, key Q) a TwoBoneIK3D modifier
	#    turns the legs after every pose is written, and it would undo the
	#    climbing legs. It is switched back when the climb ends.
	_saved_solver = _rig.solver
	_rig.solver = FootRig.Solver.OWN
	# Q: Why release the walking feet?
	# A: FootRig keeps its planted points while it is not advanced. After
	#    the climb they would be meters away; unplanted, FootRig plants
	#    them again under the hips on the first walking tick.
	for foot in _rig.feet:
		foot.planted = false
	refusal = ""
	_set_state(State.CLIMBING)
	return true


## Lets go of the rock. The capsule steps back from the face, falls and
## walks again.
func let_go() -> void:
	if state == State.WALKING:
		return
	var n := face_normal()
	# The capsule (radius 0.35 m) must not start inside the rock.
	var depth := maxf(0.0, 0.45 - face_distance(player.global_position))
	player.global_position += n * depth
	_end_climb()


## A foot's first hold: the ground under its hip, or null.
func _ground_hold(limb: int, p: Vector3) -> HoldFinder.Hold:
	var hit := _rig.ground_ray(limb_root(limb, p))
	if hit.is_empty():
		return null
	var ground := HoldFinder.Hold.new()
	ground.position = hit.position
	ground.normal = hit.normal
	ground.on_ground = true
	return ground


func _end_climb() -> void:
	player.climbing = false
	_rig.solver = _saved_solver
	candidate = null
	_set_state(State.WALKING)


# --- One climbing tick -------------------------------------------------

func _climb_tick(delta: float) -> void:
	var moving := _moving_limb()
	if moving < 0:
		moving = _start_reach()
	if moving >= 0:
		_update_limb(moving, delta)
	elif _both_hands_top_out():
		_start_mantle()
		return
	else:
		_plan_feet()

	_solve_pelvis(delta)
	_clamp_reaching_hand()
	_place_body()
	_pose()
	ascent = pelvis.y - _start_height


## The limb in REACH or MOVE, or -1.
func _moving_limb() -> int:
	for i in 4:
		if limbs[i].state != LimbState.HOLD:
			return i
	return -1


## Starts a reach when a trigger is pressed. Returns the hand, or -1.
func _start_reach() -> int:
	for i in 2:
		if Input.get_action_raw_strength(REACH_ACTIONS[i]) > trigger_threshold:
			var limb := limbs[i]
			limb.state = LimbState.REACH
			limb.aim = Vector2.ZERO
			limb.point = limb_target(i, limb.hold)
			limb.spring.frequency = reach_spring_frequency
			limb.spring.reset()
			return i
	return -1


func _update_limb(i: int, delta: float) -> void:
	var limb := limbs[i]
	if limb.state == LimbState.REACH:
		_update_reach(i, delta)
	elif limb.state == LimbState.MOVE:
		_update_move(i, delta)


## REACH: the stick moves the aim; the spring moves the hand toward it.
func _update_reach(i: int, delta: float) -> void:
	var limb := limbs[i]
	var basis := body_basis()
	var stick := player.stick_shaped
	# Q: Why does the stick change the aim's velocity, not its position?
	# A: A stick returns to the center when released. As a position, the
	#    hand would spring back to the hold each time the thumb lets go.
	#    As a velocity, the hand stays where the stick left it, and a small
	#    deflection moves it at a low speed: analog control of a point on
	#    the face.
	#    Stick y is negative when pushed forward (Lesson 02), which is up.
	limb.aim += Vector2(stick.x, -stick.y) * reach_speed * delta
	var base := limb_target(i, limb.hold)
	var root := limb_root(i, pelvis)
	var reach := limb_reach(i)
	var wanted := base + basis.x * limb.aim.x + basis.y * limb.aim.y
	# Keep the aim inside the reach sphere: project, then read the offset
	# back in face coordinates.
	wanted = ReachSolver.project_to_ball(wanted, root, reach)
	limb.aim = Vector2((wanted - base).dot(basis.x), (wanted - base).dot(basis.y))
	var offset := limb.spring.step(limb.aim, delta)
	limb.point = base + basis.x * offset.x + basis.y * offset.y + face_normal() * move_lift

	candidate = null
	var found := HoldFinder.in_reach(rock.holds, root, reach, limb.point, _used_holds(i))
	if not found.is_empty() and found[0].position.distance_to(limb.point) <= snap_radius:
		candidate = found[0]

	if Input.get_action_raw_strength(REACH_ACTIONS[i]) <= trigger_threshold:
		# Released: grab the candidate, or go back to the old hold.
		_start_move(i, candidate if candidate != null else limb.hold)
		candidate = null


## Keeps a reaching hand inside its reach sphere after the pelvis moved.
##
## Q: _update_reach() already kept the aim inside the sphere. Why again?
## A: It used the shoulder of the last tick. _solve_pelvis() then moves the
##    pelvis, and the reaching hand is not one of its balls (it holds
##    nothing). The new shoulder can be a few centimeters farther from
##    the hand than the arm is long. Projecting once more onto the ball
##    around the new shoulder puts the hand where the arm can be.
func _clamp_reaching_hand() -> void:
	for i in 2:
		var limb := limbs[i]
		if limb.state == LimbState.REACH:
			limb.point = ReachSolver.project_to_ball(limb.point, limb_root(i, pelvis), limb_reach(i))


func _start_move(i: int, hold: HoldFinder.Hold) -> void:
	var limb := limbs[i]
	limb.from_point = _end_of(i)
	# Q: Why set the point here and not wait for _update_move()?
	# A: _plan_feet() starts a foot's move late in the tick, after the
	#    limbs were updated; _pose() runs next and reads limb.point. Left
	#    unset, it would still hold the point of the limb's last move (or
	#    the world origin before the first one) for one tick.
	limb.point = limb.from_point
	limb.to_hold = hold
	limb.progress = 0.0
	limb.state = LimbState.MOVE


## MOVE: along an arc from from_point to the hold.
func _update_move(i: int, delta: float) -> void:
	var limb := limbs[i]
	limb.progress = minf(limb.progress + delta / move_time, 1.0)
	var u := limb.progress
	var target := limb_target(i, limb.to_hold)
	# FootRig.swing_ease (Lesson 12): zero speed at both ends.
	limb.point = limb.from_point.lerp(target, FootRig.swing_ease(u)) + face_normal() * move_lift * sin(PI * u)
	if u >= 1.0:
		var changed := limb.to_hold != limb.hold
		limb.hold = limb.to_hold
		limb.to_hold = null
		limb.state = LimbState.HOLD
		if changed:
			if _is_hand(i):
				hand_moves += 1
			else:
				foot_moves += 1
			limb_placed.emit(i, limb.hold)


## Moves one foot up when a higher hold keeps every limb in reach.
##
## Q: Which hold does a foot want?
## A: The highest one it can stand on while the three other limbs keep
##    theirs. The search runs in three steps:
##    1. a high pelvis that the other three limbs allow: ReachSolver,
##       started 1 m above the pelvis, returns a point of their feasible
##       set reached from above (in most cases a high one); and the hip
##       at that pelvis;
##    2. holds at least foot_hip_gap below that hip and foot_hand_gap
##       below the lower hand, higher than the foot's own hold by
##       foot_step_threshold;
##    3. of those, the ones for which all four balls still meet: the
##       foot's ball is added and ReachSolver must end with a residual
##       below 1 mm.
##       The highest wins, less foot_lateral_cost per meter of sideways
##       distance from the hip.
##    The lower foot is tried first.
func _plan_feet() -> void:
	var lowest_hand := minf(limbs[Limb.HAND_L].hold.position.y, limbs[Limb.HAND_R].hold.position.y)
	var order := [Limb.FOOT_L, Limb.FOOT_R]
	if _limb_height(Limb.FOOT_R) < _limb_height(Limb.FOOT_L):
		order = [Limb.FOOT_R, Limb.FOOT_L]
	var n := face_normal()
	var plane_point := face_point() + n * min_clearance
	for i: int in order:
		var others := _balls(i)
		var high := ReachSolver.solve(pelvis + Vector3.UP, others[0], others[1], plane_point, n).position
		var hip := limb_root(i, high)
		var reach := limb_reach(i)
		var floor_height := _limb_height(i) + foot_step_threshold
		var best: HoldFinder.Hold
		var best_value := -INF
		var used := _used_holds(i)
		for hold in rock.holds:
			if hold in used:
				continue
			var y := hold.position.y
			if y < floor_height or y > hip.y - foot_hip_gap or y > lowest_hand - foot_hand_gap:
				continue
			var lateral := absf((hold.position - hip).dot(body_basis().x))
			var value := y - foot_lateral_cost * lateral
			if value <= best_value:
				continue
			var centers: PackedVector3Array = others[0].duplicate()
			var radii: PackedFloat32Array = others[1].duplicate()
			centers.append(limb_target(i, hold) - body_basis() * _root_offset(i))
			radii.append(reach)
			if ReachSolver.solve(pelvis, centers, radii, plane_point, n).residual < 1e-3:
				best = hold
				best_value = value
		if best != null:
			_start_move(i, best)
			return


## The pelvis the contacts would like, before the reach solver.
##
## Q: Where would a climber hang?
## A: Below the hands, with the arms almost straight (arm_hang of the
##    arm's reach below the shoulders' holds), and above the feet with the
##    legs bent (leg_stand of the leg). The two guesses are averaged.
##    While a hand reaches, the pelvis is drawn toward the reaching hand
##    instead: the body follows the reach. Then the point is set
##    clearance() in front of the face.
func _preferred_pelvis() -> Vector3:
	var basis := body_basis()
	var guesses := PackedVector3Array()
	var reaching := -1
	for i in 2:
		if limbs[i].state == LimbState.REACH:
			reaching = i
	if reaching >= 0:
		guesses.append(limbs[reaching].point - basis * _root_offset(reaching))
	else:
		var hand_sum := Vector3.ZERO
		var hand_count := 0
		for i in 2:
			var hold := _destination(i)
			if hold != null:
				hand_sum += limb_target(i, hold) - basis * _root_offset(i)
				hand_count += 1
		if hand_count > 0:
			guesses.append(hand_sum / hand_count + Vector3.DOWN * arm_hang * limb_reach(Limb.HAND_L))
		var foot_sum := Vector3.ZERO
		var foot_count := 0
		for i: int in [Limb.FOOT_L, Limb.FOOT_R]:
			var hold := _destination(i)
			if hold != null:
				foot_sum += limb_target(i, hold) - basis * _root_offset(i)
				foot_count += 1
		if foot_count > 0:
			guesses.append(foot_sum / foot_count + Vector3.UP * leg_stand * limb_reach(Limb.FOOT_L))
	var p := Vector3.ZERO
	for guess in guesses:
		p += guess / guesses.size()
	return p + face_normal() * (clearance() - face_distance(p))


## Places the pelvis where every holding limb reaches (ReachSolver).
##
## Q: Why solve twice?
## A: The first solve gives the target, a point of the feasible set (the
##    intersection of the balls and the half-space) near the preferred
##    pelvis. The pelvis follows the target with a one-pole filter
##    (Lesson 14), so it moves on the segment from its old position to
##    the target. While the balls stay the same, both ends of the
##    segment lie in the set, and so does the segment: the set is
##    convex. When a limb takes a new hold, its ball moves, and the old
##    position may lie outside the new set. The second solve, started at
##    the filtered point, moves it back into the set: every limb reaches
##    on every tick.
func _solve_pelvis(delta: float) -> void:
	var balls := _balls(-1)
	var n := face_normal()
	var plane_point := face_point() + n * min_clearance
	var result := ReachSolver.solve(_preferred_pelvis(), balls[0], balls[1], plane_point, n)
	pelvis_target = result.position
	var filtered := pelvis.lerp(pelvis_target, OnePoleFilter.blend(delta, pelvis_time_constant))
	var settled := ReachSolver.solve(filtered, balls[0], balls[1], plane_point, n)
	pelvis = settled.position
	residual = settled.residual
	sweeps = result.sweeps + settled.sweeps


## One ball per limb that holds or moves to a hold, except the limb
## `except`: [centers, radii].
##
## Q: Where is the center of limb i's ball?
## A: Limb i reaches its hold when its joint p + o_i lies within R_i of
##    the hold's target t_i. In terms of the pelvis p: |p - (t_i - o_i)|
##    <= R_i. The center is t_i - o_i.
## Q: Why does a moving limb count with the hold it moves to?
## A: The pelvis then starts toward a place from which that hold is in
##    reach while the limb travels. Without the ball, the pelvis stays
##    where the old holds put it, and the arm or leg arrives short of its
##    new hold.
func _balls(except: int) -> Array:
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	var basis := body_basis()
	for i in 4:
		var hold := _destination(i)
		if i == except or hold == null:
			continue
		centers.append(limb_target(i, hold) - basis * _root_offset(i))
		radii.append(limb_reach(i))
	return [centers, radii]


## The hold a limb is on (HOLD) or travels to (MOVE); null while a hand
## reaches or a foot hangs free.
func _destination(i: int) -> HoldFinder.Hold:
	var limb := limbs[i]
	match limb.state:
		LimbState.HOLD:
			return limb.hold
		LimbState.MOVE:
			return limb.to_hold
	return null


## Moves the capsule under the pelvis and turns the body to the face.
func _place_body() -> void:
	player.global_position = pelvis + Vector3.DOWN * _rig.proportions.hip_height()
	var n := face_normal()
	# Q: Which turn about +y makes the body face the rock?
	# A: The body faces its -z axis, so +z must point along n. A turn by a
	#    sends (0, 0, 1) to (sin a, 0, cos a): a = atan2(n.x, n.z).
	player.body_mesh().rotation.y = atan2(n.x, n.z)


## Solves the four limbs and writes the pose (in the rig's frame).
func _pose() -> void:
	var q := _rig.proportions
	var to_local := _rig.global_transform.affine_inverse()
	var pose := WalkCycle.Pose.new()
	var hips := to_local * pelvis
	pose.hips_offset = hips - Vector3(0.0, q.hip_height(), 0.0)
	for i in 4:
		var limb := limbs[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		var suffix := FootRig.SIDE_NAMES[i % 2]
		var root := hips + _root_offset(i)
		var target := to_local * _end_of(i)
		if _is_hand(i):
			# Elbows point down, out to the side and away from the face.
			var pole := root + Vector3(side * 0.5, -1.0, 0.4)
			var arm := TwoBoneIk.solve(root, target, pole, q.upper_arm_length, q.forearm_length)
			if arm_solver == ArmSolver.FABRIK:
				arm = _solve_arm_fabrik(i, root, target, arm, to_local)
				pole = arm.middle
			var bases := TwoBoneIk.leg_bases(arm, pole)
			# The chest has the identity basis, so the upper arm's local
			# rotation is its global one (Lesson 12, _solve_and_pose()).
			pose.rotations[StringName("UpperArm." + suffix)] = bases[0].get_rotation_quaternion()
			pose.rotations[StringName("LowerArm." + suffix)] = (bases[0].transposed() * bases[1]).get_rotation_quaternion()
			limb_errors[i] = arm.end.distance_to(target)
		else:
			# Knees point toward the face and out to the side (a frog stance).
			var pole := root + Vector3(side * 0.4, -q.thigh_length, -1.0)
			var leg := TwoBoneIk.solve(root, target, pole, q.thigh_length, q.shin_length)
			var bases := TwoBoneIk.leg_bases(leg, pole)
			var normal := Vector3.UP
			if limb.hold != null and limb.state == LimbState.HOLD:
				normal = (to_local.basis * TwoBoneIk.limit_tilt(limb.hold.normal, _rig.max_foot_tilt_degrees)).normalized()
			var foot := TwoBoneIk.foot_basis(normal, Vector3.FORWARD)
			pose.rotations[StringName("UpperLeg." + suffix)] = bases[0].get_rotation_quaternion()
			pose.rotations[StringName("LowerLeg." + suffix)] = (bases[0].transposed() * bases[1]).get_rotation_quaternion()
			pose.rotations[StringName("Foot." + suffix)] = (bases[1].transposed() * foot).get_rotation_quaternion()
			limb_errors[i] = leg.end.distance_to(target)
	_rig.apply_pose(pose)


## FABRIK for one arm, in the rig's frame, warm-started from the last
## tick. Returns the result in TwoBoneIk's Solution form.
##
## Q: Where does FABRIK's elbow come from, with no pole?
## A: From the previous pose: each pass moves the elbow along the line to
##    its old position. On the first tick the two-bone solution (with its
##    pole) seeds it; afterward the elbow keeps whatever bend it had.
func _solve_arm_fabrik(i: int, root: Vector3, target: Vector3, seed: TwoBoneIk.Solution,
		to_local: Transform3D) -> TwoBoneIk.Solution:
	var q := _rig.proportions
	var joints := PackedVector3Array()
	var world := _arm_joints[i - Limb.HAND_L]
	if world.size() == 3:
		joints = PackedVector3Array([root, to_local * world[1], to_local * world[2]])
	else:
		joints = PackedVector3Array([root, seed.middle, seed.end])
	var lengths := PackedFloat32Array([q.upper_arm_length, q.forearm_length])
	var result := Fabrik.solve(joints, lengths, target, fabrik_tolerance, fabrik_iterations)
	fabrik_iteration_counts[i - Limb.HAND_L] = result.iterations
	var from_local := to_local.affine_inverse()
	_arm_joints[i - Limb.HAND_L] = PackedVector3Array([from_local * result.joints[0], from_local * result.joints[1], from_local * result.joints[2]])
	var solution := TwoBoneIk.Solution.new()
	solution.root = result.joints[0]
	solution.middle = result.joints[1]
	solution.end = result.joints[2]
	solution.reached = result.reachable and result.error <= fabrik_tolerance
	return solution


# --- Mantle --------------------------------------------------------------

func _both_hands_top_out() -> bool:
	for i in 2:
		var hold := limbs[i].hold
		if hold == null or not hold.top_out:
			return false
	return true


## Finds the top behind the hands and starts the mantle.
func _start_mantle() -> void:
	var hands := (limbs[0].hold.position + limbs[1].hold.position) * 0.5
	var above := hands + Vector3.UP * 1.0 - face_normal() * 0.45
	var query := PhysicsRayQueryParameters3D.create(above, above + Vector3.DOWN * 2.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_mantle_from = player.global_position
	_mantle_to = hit.position
	_mantle_progress = 0.0
	_set_state(State.MANTLING)


## MANTLING: up first, then over the edge; then walk.
##
## Q: Why two overlapping ramps and not one straight line?
## A: A straight line from below the edge to the top passes through the
##    rock. The vertical ramp runs over the first 60 % of the time and
##    the horizontal one over the last 60 %, so the body clears the edge
##    before it moves over it.
func _mantle_tick(delta: float) -> void:
	_mantle_progress = minf(_mantle_progress + delta / mantle_time, 1.0)
	var u := _mantle_progress
	var rise := FootRig.swing_ease(clampf(u / 0.6, 0.0, 1.0))
	var over := FootRig.swing_ease(clampf((u - 0.4) / 0.6, 0.0, 1.0))
	var p := _mantle_from.lerp(_mantle_to, over)
	p.y = lerpf(_mantle_from.y, _mantle_to.y + 0.05, rise)
	player.global_position = p
	pelvis = p + Vector3.UP * _rig.proportions.hip_height()
	ascent = pelvis.y - _start_height
	_rig.apply_pose(_rig.walk_cycle.sample(_rig.phase, 0.0))
	if u >= 1.0:
		_end_climb()


# --- Helpers -------------------------------------------------------------

func _set_state(value: State) -> void:
	if value == state:
		return
	state = value
	state_changed.emit(state)


func _is_hand(limb: int) -> bool:
	return limb == Limb.HAND_L or limb == Limb.HAND_R


## Height of a limb's hold, or -INF without one.
func _limb_height(i: int) -> float:
	return -INF if limbs[i].hold == null else limbs[i].hold.position.y


## Where the end of a limb is to be this tick, world space.
func _end_of(i: int) -> Vector3:
	var limb := limbs[i]
	if limb.state != LimbState.HOLD:
		return limb.point
	if limb.hold != null:
		return limb_target(i, limb.hold)
	# A foot without a hold hangs below its hip.
	return limb_root(i, pelvis) + Vector3.DOWN * limb_reach(i)


func _used_holds(except: int) -> Array:
	var used := []
	for i in 4:
		if i != except and limbs[i].hold != null:
			used.append(limbs[i].hold)
	return used


## The joint of a limb relative to the pelvis, body frame (x right, y up,
## z back).
func _root_offset(limb: int) -> Vector3:
	if _shoulder_offsets.is_empty():
		_cache_offsets()
	return _shoulder_offsets[limb] if _is_hand(limb) else _hip_offsets[limb - 2]


## Reads the shoulder and hip offsets from the skeleton's rest pose.
func _cache_offsets() -> void:
	_shoulder_offsets.clear()
	_hip_offsets.clear()
	var skeleton := _rig.skeleton()
	var hips := skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin
	for suffix in FootRig.SIDE_NAMES:
		_shoulder_offsets.append(skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm." + suffix)).origin - hips)
		_hip_offsets.append(skeleton.get_bone_global_rest(skeleton.find_bone("UpperLeg." + suffix)).origin - hips)


func _draw_debug() -> void:
	if _debug_mesh == null or not debug_draw:
		return
	_debug_mesh.clear_surfaces()
	if state != State.CLIMBING:
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var basis := body_basis()
	for i in 4:
		var limb := limbs[i]
		var root := limb_root(i, pelvis)
		var color := Color(0.3, 0.8, 1.0) if _is_hand(i) else Color(0.6, 1.0, 0.4)
		if limb.state == LimbState.HOLD and limb.hold != null:
			_line(pelvis, limb_target(i, limb.hold), color.darkened(0.3))
		# The reach sphere, cut by the plane of the face through the root.
		if limb.state == LimbState.REACH:
			_circle(root, basis.x, basis.y, limb_reach(i), Color(1.0, 0.9, 0.2))
			_line(root, limb.point, Color(1.0, 0.9, 0.2))
	if candidate != null:
		_circle(candidate.position, basis.x, basis.y, 0.06, Color(1.0, 0.3, 0.2))
	_circle(pelvis, basis.x, basis.z, 0.08, Color.WHITE)
	_debug_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(a)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(b)


func _circle(center: Vector3, u: Vector3, v: Vector3, radius: float, color: Color) -> void:
	var segments := 32
	for k in segments:
		var a := TAU * k / segments
		var b := TAU * (k + 1) / segments
		_line(center + (u * cos(a) + v * sin(a)) * radius, center + (u * cos(b) + v * sin(b)) * radius, color)
