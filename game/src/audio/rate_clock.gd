class_name RateClock
extends RefCounted
## Decides on which physics ticks a message goes out, for a target rate
## in messages per second (Lesson 04). Used by player_state_reporter.gd.
##
##   ticks (60 Hz)   |  |  |  |  |  |  |  |  |
##   sends (30 Hz)   x     x     x     x     x
##   ticks (144 Hz)  ||||||||||||||||||||||||||
##   sends (30 Hz)   x    x   x    x    x   x       4 or 5 ticks apart
##
## The clock adds each tick's delta to an accumulator. When the
## accumulator reaches one period (1 / rate), it subtracts the period and
## reports a send. The remainder carries over, so the average rate is
## exact even when the period is not a whole number of ticks.

## Messages per second. 0 or less stops all sends.
var rate_hz := 30.0

var _accumulator := 0.0


func _init(initial_rate_hz: float = 30.0) -> void:
	rate_hz = initial_rate_hz


## Advances the clock by delta seconds. Returns true when a message is due.
func tick(delta: float) -> bool:
	if rate_hz <= 0.0:
		_accumulator = 0.0
		return false
	var period := 1.0 / rate_hz
	_accumulator += delta
	# Q: Why the small tolerance in the comparison?
	# A: 1/144 has no exact binary form, and each addition rounds. Where
	#    the exact accumulator would equal the period, the rounded one can
	#    land a hair below it, and a send that is due waits one more tick.
	#    Measured: without the tolerance, a 30 Hz clock on 144 Hz ticks
	#    sends 299 messages in 10 simulated seconds instead of 300.
	if _accumulator + 1e-9 < period:
		return false
	_accumulator -= period
	# Q: What if a frame hitch delivers a delta of half a second?
	# A: The accumulator would hold many periods, and the next ticks would
	#    send a burst of stale states. Keeping less than one period drops
	#    the backlog: state messages describe "now", so old ones have no use.
	if _accumulator >= period:
		_accumulator = fmod(_accumulator, period)
	return true
