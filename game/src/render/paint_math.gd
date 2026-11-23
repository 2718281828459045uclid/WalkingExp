class_name PaintMath
extends RefCounted
## CPU copies of the formulas in shaders/terrain_painted.gdshader and
## shaders/color_ramp.gdshader (Lesson 03).
##
## Q: Why repeat shader math in GDScript?
## A: A shader runs on the GPU and returns pixels, not numbers. Tests and
##    the HUD need the numbers. tests/test_03_paint_math.gd checks these
##    functions against Godot's own Color conversions, and
##    src/lessons/painting_the_ground.gd uses contour_index() for the HUD.
##    If you change a formula in a shader, change its copy here.


## sRGB decoding (IEC 61966-2-1): stored value -> linear light.
## Same curve as srgb_to_linear() in color_ramp.gdshader.
static func srgb_to_linear(c: float) -> float:
	if c < 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## sRGB encoding, the inverse of srgb_to_linear().
static func linear_to_srgb(x: float) -> float:
	if x < 0.0031308:
		return x * 12.92
	return 1.055 * pow(x, 1.0 / 2.4) - 0.055


## Triplanar blend weights for a unit normal n: |n|^k per component,
## divided by their sum. Same as triplanar_weights() in terrain_painted.gdshader.
static func triplanar_weights(n: Vector3, sharpness: float) -> Vector3:
	var w := Vector3(
		pow(absf(n.x), sharpness),
		pow(absf(n.y), sharpness),
		pow(absf(n.z), sharpness),
	)
	return w / (w.x + w.y + w.z)


## Distance from height to the nearest contour line, in contour steps:
## 0 on a line, 0.5 halfway between two lines.
static func contour_distance(height: float, interval: float) -> float:
	var f := height / interval
	# fposmod(x, 1) is GLSL's fract(x) for negative x too: fract(-0.25) = 0.75.
	return absf(fposmod(f - 0.5, 1.0) - 0.5)


## Number of the contour line at or below height: floor(height / interval).
static func contour_index(height: float, interval: float) -> int:
	return floori(height / interval)
