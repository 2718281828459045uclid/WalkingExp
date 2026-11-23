class_name PostureController
extends StanceController
## Four postures with guarded transitions (Lesson 16): standing, crouched,
## crawling, scrambling.
##
## How the files relate:
##   StanceController (Lesson 14)  weight shift and crouch of the rig; this
##                                 class keeps all of it and adds postures
##   CrawlingPlayer                the collision shapes, fits(), the movement
##     (crawling_player.gd)        mode; this node calls it
##   CrawlController               listens to posture_changed and poses the
##     (crawl_controller.gd)       body in the low postures
##   ClimbController (Lesson 15)   optional: no posture changes while it
##                                 climbs; key 4 then toggles only the
##                                 Lesson 14 crouch, which the climb reads
##   src/lessons/crawling_and_scrambling.gd   key 4 calls toggle_stance(),
##                                 F3 calls toggle_crawl()
##
## The postures, their shapes and movement modes:
##   STAND     stand shape    upright (Lesson 14 STANDING)
##   CROUCH    crouch shape   upright (Lesson 14 CROUCHED)
##   CRAWL     crawl shape    crawl
##   SCRAMBLE  crouch shape   scramble
##
## The transitions (README section 3.2 and P6):
##   key 4    STAND <-> CROUCH; CRAWL -> CROUCH; while climbing, the
##            Lesson 14 stance only, and the posture follows it after the
##            climb
##   F3       STAND or CROUCH -> CRAWL; CRAWL -> the upright posture it
##            came from
##   automatic: STAND, CROUCH or CRAWL -> SCRAMBLE when the stick pushes
##            the body toward ground steeper than the walking limit and
##            no steeper than the scramble limit; SCRAMBLE -> the posture
##            it came from (or CRAWL) when the ground under and ahead is
##            walkable again
## Every transition is refused when the new shape does not fit
## (CrawlingPlayer.fits()); `refusal` says why.
##
## Order inside one physics tick: BalanceMonitor, then this node (priority
## -1, later in the tree): the Lesson 14 shift and crouch, then (while not
## climbing) the posture follows the stance and the automatic transitions
## run. A new shape is in place before the player moves.
##
## OSC: /body/posture s (the posture's name) on every change, through the
## "Osc" autoload (Lesson 04).

## The posture changed (for the pose blend and the HUD).
signal posture_changed(posture: int)

enum Posture {
	STAND,
	CROUCH,
	CRAWL,
	SCRAMBLE,
}

const POSTURE_NAMES: PackedStringArray = ["standing", "crouched", "crawling", "scrambling"]

## Optional. While it climbs, every request is refused.
@export var climb: ClimbController
@export_group("Scramble")
## Whether the body drops to a scramble by itself before a slab. Off, the
## slab is a wall to the upright body, as in Lessons 02-15.
@export var auto_scramble := true
## Distance ahead of the origin at which the ground is probed, meters.
@export var probe_distance: float = 0.6
## Smallest stick deflection that counts as pushing, 0 to 1.
@export var push_threshold: float = 0.3
## Scrambling ends when the ground under the body and ahead of it is
## less steep than this, degrees.
@export var walkable_degrees: float = 40.0

var posture := Posture.STAND
## Why the last request failed, or "".
var refusal := ""
## Slope of the probed ground ahead in the last tick, degrees (NAN when
## the probe missed or was not cast).
var slope_ahead_degrees := NAN
var transitions := 0
var refusals := 0
## Where /body/posture goes. Left empty, _ready() takes the "Osc" autoload.
var sender: OscSender

## The upright posture that F3 returns to from CRAWL.
var _upright := Posture.STAND
## The posture that SCRAMBLE returns to.
var _return := Posture.STAND


## The body shape each posture uses.
static func shape_of(p: Posture) -> CrawlingPlayer.BodyShape:
	match p:
		Posture.STAND:
			return CrawlingPlayer.BodyShape.STAND
		Posture.CRAWL:
			return CrawlingPlayer.BodyShape.CRAWL
	return CrawlingPlayer.BodyShape.CROUCH


## The movement mode each posture uses.
static func mode_of(p: Posture) -> CrawlingPlayer.Mode:
	match p:
		Posture.CRAWL:
			return CrawlingPlayer.Mode.CRAWL
		Posture.SCRAMBLE:
			return CrawlingPlayer.Mode.SCRAMBLE
	return CrawlingPlayer.Mode.UPRIGHT


func _ready() -> void:
	super()
	if sender == null:
		sender = get_node_or_null("/root/Osc") as OscSender


func _physics_process(delta: float) -> void:
	super(delta)
	if _climbing():
		return
	_follow_stance()
	_automatic_transitions()


## Asks for a posture. Returns whether the body is in it afterward.
func request(target: Posture) -> bool:
	if target == posture:
		return true
	var body := player as CrawlingPlayer
	if body == null:
		return _refuse("no crawling player")
	if _climbing():
		return _refuse("climbing")
	var shape := shape_of(target)
	if shape != body.body_shape and not body.fits(shape):
		# Q: Which word does the refusal use?
		# A: A taller shape that does not fit hits something above:
		#    "no headroom". A shape that is not taller (the crawl shape is
		#    lower but longer) hits something in front or behind:
		#    "no room".
		var taller := body.shape_height(shape) > body.shape_height(body.body_shape)
		return _refuse("no headroom" if taller else "no room")
	_apply(target)
	return true


## Key 4 (Lesson 14): standing and crouched; from a crawl, up to crouched.
##
## Q: What does key 4 do on the rock?
## A: What it does in Lesson 15: it toggles the Lesson 14 stance, and
##    ClimbController reads the crouch to pull the hips toward the rock.
##    The posture and the shape stay; the climb places the capsule
##    itself. When the climb ends, _follow_stance() brings the posture
##    to the stance.
func toggle_stance() -> void:
	if _climbing():
		super()
		return
	match posture:
		Posture.STAND:
			request(Posture.CROUCH)
		Posture.CROUCH:
			request(Posture.STAND)
		Posture.CRAWL:
			request(Posture.CROUCH)
		Posture.SCRAMBLE:
			_refuse("scrambling")


## F3: down to a crawl, or back up to the upright posture.
func toggle_crawl() -> void:
	match posture:
		Posture.STAND, Posture.CROUCH:
			request(Posture.CRAWL)
		Posture.CRAWL:
			request(_upright)
		Posture.SCRAMBLE:
			_refuse("scrambling")


## The slope at which a ground probe counts as a slab, degrees: steeper
## than the walking limit, no steeper than the scramble limit.
func is_scramble_slope(degrees: float) -> bool:
	var body := player as CrawlingPlayer
	if body == null:
		return false
	return degrees > body.walk_max_angle_degrees() and degrees <= body.scramble_max_angle_degrees


func _apply(target: Posture) -> void:
	var body := player as CrawlingPlayer
	if target == Posture.STAND or target == Posture.CROUCH:
		_upright = target
	if target == Posture.SCRAMBLE:
		_return = posture
	posture = target
	body.set_body_shape(shape_of(target))
	body.mode = mode_of(target)
	# The Lesson 14 crouch lowers the rig while crouched. In the low
	# postures CrawlController writes the whole pose in world space, so
	# the rig's offset does not matter there.
	stance = Stance.CROUCHED if target == Posture.CROUCH else Stance.STANDING
	refusal = ""
	transitions += 1
	posture_changed.emit(posture)
	if sender != null:
		sender.send("/body/posture", [POSTURE_NAMES[posture]])


func _refuse(reason: String) -> bool:
	refusal = reason
	refusals += 1
	return false


func _climbing() -> bool:
	return climb != null and climb.state != ClimbController.State.WALKING


## Q: When do the stance and the posture disagree?
## A: After a climb in which key 4 toggled the Lesson 14 stance
##    (toggle_stance()). Back on the ground, an upright posture follows
##    the stance through request(), so the new shape is tested first.
##    When it does not fit, the stance follows the posture instead.
func _follow_stance() -> void:
	if posture != Posture.STAND and posture != Posture.CROUCH:
		return
	var wanted := Posture.CROUCH if stance == Stance.CROUCHED else Posture.STAND
	if wanted != posture and not request(wanted):
		stance = Stance.CROUCHED if posture == Posture.CROUCH else Stance.STANDING


## Enters and leaves SCRAMBLE.
##
## Q: How does the body know it stands before a slab?
## A: A ray cast down probe_distance ahead (CrawlingPlayer.ground_ahead())
##    returns the ground's normal n there. The slope is the angle between
##    n and up. A slab is ground that rises or falls ahead (the hit lies
##    more than 5 cm above or below the feet) with a slope between the
##    walking limit (floor_max_angle, 45 degrees) and the scramble limit
##    (55 degrees). The probe looks along the stick while the stick
##    pushes, else along the facing.
## Q: Why does the stick have to push toward the slab?
## A: Standing next to a slab is not a reason to drop to all fours. The
##    push is the player's intent; the slope is the permission.
func _automatic_transitions() -> void:
	var body := player as CrawlingPlayer
	if body == null or not auto_scramble:
		return
	var wish := body.wish_direction()
	var pushing := wish.length() >= push_threshold
	var direction := wish if pushing else body.facing()
	var hit := body.ground_ahead(direction, probe_distance)
	slope_ahead_degrees = NAN
	var climbs := false
	if not hit.is_empty():
		slope_ahead_degrees = rad_to_deg((hit.normal as Vector3).angle_to(Vector3.UP))
		# Up or down: a slab can be scrambled down as well as up.
		climbs = absf((hit.position as Vector3).y - body.global_position.y) > 0.05

	if posture != Posture.SCRAMBLE:
		if pushing and climbs and is_scramble_slope(slope_ahead_degrees):
			request(Posture.SCRAMBLE)
		elif pushing and climbs and slope_ahead_degrees > body.scramble_max_angle_degrees and body.is_on_wall():
			refusal = "too steep"
		return

	# Q: When does a scramble end?
	# A: When the ground under the body (the floor normal of the last
	#    move) and the ground ahead are both walkable. At the top of the
	#    slab both turn flat. At its foot the floor under the body is
	#    flat while the probe still sees the slab, so pushing up keeps the
	#    scramble and pushing away ends it. Scrambling down from the top,
	#    the probe sees the slab below the edge, and the scramble goes on.
	var under := body.floor_angle_degrees
	var ahead_walkable := is_nan(slope_ahead_degrees) or slope_ahead_degrees < walkable_degrees
	if not is_nan(under) and under < walkable_degrees and ahead_walkable:
		if not request(_return):
			request(Posture.CRAWL)
