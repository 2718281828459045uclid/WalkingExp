class_name AxialStickResponse
extends StickResponse
## A StickResponse with an axial deadzone: one deadzone per axis, a square
## instead of the circle of Lesson 02 (Lesson 14).
##
## It exists for comparison. Lesson 14 key 8 swaps the player's
## stick_response between data/input/walk_stick_response.tres (radial) and
## data/input/walk_stick_axial.tres (this class, same numbers).
##
## Each component c of the raw stick is shaped on its own:
##   c -> sign(c) * shape(|c|)
## with the inherited shape() (deadzone, saturation, power law or Curve).
## The result is limited to length 1.
##
##        y
##        |   a stick pushed 10 degrees right of forward, magnitude 0.5
##        |   (y here is forward; Input.get_vector gives forward as -y):
##   .----|----.    raw    (0.087, 0.492)
##   |  ##|##  |    radial (0.050, 0.282): the direction is kept
##   |---##+##-|-x  axial  (0.000, 0.277): x is inside its deadzone,
##   |  ##|##  |           so the stick snaps to straight forward
##   '----|----'
##   ## = the cross-shaped region where one axis reads zero


func apply(raw: Vector2) -> Vector2:
	var shaped := Vector2(signf(raw.x) * shape(absf(raw.x)), signf(raw.y) * shape(absf(raw.y)))
	# Q: Why limit the length?
	# A: Both axes can reach 1 at the same time (a stick pushed into a
	#    corner of a square gate, or the keys W and D together). The vector
	#    (1, 1) has length 1.41: diagonal walking would be 41 % faster.
	return shaped.limit_length(1.0)
