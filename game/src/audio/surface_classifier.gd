class_name SurfaceClassifier
extends RefCounted
## Answers "which ground lies under this point?" on the CPU (Lesson 05).
##
## shaders/terrain_painted.gdshader (Lesson 03) paints grass, dirt, and
## rock from the slope, the height, and a noise texture. The GPU decides
## per pixel and tells nobody. This class repeats the same rules on the
## CPU, with the same numbers, so a footstep can know what it stepped on.
## It reads the rule parameters and the noise texture from the painted
## ShaderMaterial; it holds no numbers of its own.
##
## Used by src/audio/footstep_reporter.gd. Checked against the shader's
## formulas in tests/test_05_surface.gd.
##
## Q: Why weights instead of one surface name?
## A: The shader blends: at a rock edge a pixel may be 40 % rock and
##    60 % grass. A footstep there can be a blend too. SuperCollider
##    receives three weights that sum to 1 and mixes three sounds.

enum Surface { GRASS, DIRT, ROCK }

const SURFACE_NAMES: PackedStringArray = ["grass", "dirt", "rock"]

var rock_angle_start := 22.0
var rock_angle_end := 32.0
var rock_breakup_degrees := 8.0
var dirt_height := 1.0
var dirt_blend_meters := 3.0
var dirt_breakup_meters := 1.5
var noise_scale_meters := 24.0
var triplanar_sharpness := 4.0

# The noise texture's pixels. Null until the texture has been generated;
# until then the noise shift is 0 (clean bands).
var _noise_image: Image


## Copies the rule parameters and the noise texture from a material that
## uses terrain_painted.gdshader.
func read_material(material: ShaderMaterial) -> void:
	rock_angle_start = material.get_shader_parameter("rock_angle_start")
	rock_angle_end = material.get_shader_parameter("rock_angle_end")
	rock_breakup_degrees = material.get_shader_parameter("rock_breakup_degrees")
	dirt_height = material.get_shader_parameter("dirt_height")
	dirt_blend_meters = material.get_shader_parameter("dirt_blend_meters")
	dirt_breakup_meters = material.get_shader_parameter("dirt_breakup_meters")
	noise_scale_meters = material.get_shader_parameter("noise_scale_meters")
	triplanar_sharpness = material.get_shader_parameter("triplanar_sharpness")
	var texture := material.get_shader_parameter("ground_noise") as Texture2D
	if texture == null:
		return
	# Q: Why might get_image() return null?
	# A: A NoiseTexture2D computes its pixels on a worker thread after it
	#    loads. Until it emits "changed", there is no image yet.
	_noise_image = texture.get_image()
	if _noise_image == null:
		texture.changed.connect(_on_noise_changed.bind(texture), CONNECT_ONE_SHOT)


func has_noise() -> bool:
	return _noise_image != null


func _on_noise_changed(texture: Texture2D) -> void:
	_noise_image = texture.get_image()


## Weights (grass, dirt, rock) at a world position with unit normal n.
## The three weights are non-negative and sum to 1.
func weights_at(position: Vector3, n: Vector3) -> Vector3:
	var slope := slope_degrees(n)
	var shift := noise_at(position, n) - 0.5
	return surface_weights(rockiness(slope, shift), dirtiness(position.y, shift))


## Slope angle in degrees between the normal and straight up.
static func slope_degrees(n: Vector3) -> float:
	return rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))


## The shader's rock rule. shift is the noise value minus 0.5.
func rockiness(slope: float, shift: float) -> float:
	return smoothstep(rock_angle_start, rock_angle_end, slope + shift * 2.0 * rock_breakup_degrees)


## The shader's dirt rule: 1 in low ground, 0 above the blend band.
func dirtiness(height: float, shift: float) -> float:
	return 1.0 - smoothstep(dirt_height, dirt_height + dirt_blend_meters, height + shift * 2.0 * dirt_breakup_meters)


## Turns the two rule values into three weights, the way the shader mixes
## colors: ground = mix(grass, dirt, dirtiness); final = mix(ground, rock, rockiness).
##
## Q: How do two nested mixes become three weights?
## A: Expand mix(a, b, t) = (1 - t) a + t b twice:
##      final = (1 - r) ((1 - d) grass + d dirt) + r rock
##    The coefficient of each color is its weight:
##      grass (1 - r)(1 - d),  dirt (1 - r) d,  rock r
##    They sum to (1 - r)(1 - d + d) + r = 1.
static func surface_weights(r: float, d: float) -> Vector3:
	return Vector3((1.0 - r) * (1.0 - d), (1.0 - r) * d, r)


## Index of the largest weight: Surface.GRASS, DIRT, or ROCK.
static func dominant(weights: Vector3) -> int:
	return weights.max_axis_index()


## The coarse noise value in [0, 1] at a point, sampled triplanar as in
## the shader. 0.5 (no shift) while the texture is not ready.
func noise_at(position: Vector3, n: Vector3) -> float:
	if _noise_image == null:
		return 0.5
	var w := PaintMath.triplanar_weights(n, triplanar_sharpness)
	var q := position / noise_scale_meters
	return (
		sample_bilinear(_noise_image, Vector2(q.z, q.y)) * w.x
		+ sample_bilinear(_noise_image, Vector2(q.x, q.z)) * w.y
		+ sample_bilinear(_noise_image, Vector2(q.x, q.y)) * w.z
	)


## Red channel of an image at texture coordinate uv, with repeat and
## bilinear filtering: what texture() returns on the GPU at mip level 0.
##
## Q: Where are the texel centers?
## A: Texel i covers u from i / size to (i + 1) / size; its center is at
##    (i + 0.5) / size. So u * size - 0.5 is a position measured in texel
##    centers: its integer part names the left neighbor, its fraction is
##    the blend toward the right neighbor.
static func sample_bilinear(image: Image, uv: Vector2) -> float:
	var size := image.get_size()
	var x := uv.x * size.x - 0.5
	var y := uv.y * size.y - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	# posmod() wraps negative indices too: texel -1 is the last texel.
	var xa := posmod(x0, size.x)
	var xb := posmod(x0 + 1, size.x)
	var ya := posmod(y0, size.y)
	var yb := posmod(y0 + 1, size.y)
	var top := lerpf(image.get_pixel(xa, ya).r, image.get_pixel(xb, ya).r, fx)
	var bottom := lerpf(image.get_pixel(xa, yb).r, image.get_pixel(xb, yb).r, fx)
	return lerpf(top, bottom, fy)
