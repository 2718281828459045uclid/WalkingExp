# Lesson 03. Painting the ground

Lesson scene: `game/scenes/lessons/03_painting_the_ground.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). `game/scenes/sandbox.tscn` and `game/scenes/lessons/02_walking_on_a_surface.tscn` are unchanged and run as Lessons 00–02 describe.

## 1. Orientation

Lesson 01 colored the terrain with two rules: steep ground is rock, low ground is dirt. The result is flat color with straight-edged bands. This lesson answers five questions about how a surface gets its color on screen:

1. Where does a texture come from on a mesh with no usable texture coordinates? (triplanar mapping)
2. How do rules with thresholds become irregular boundaries? (`smoothstep`, noise-shifted thresholds)
3. How are lines of constant height drawn at a constant width on screen? (`fract`, `fwidth`, contour lines)
4. What do the numbers in a color picker mean, and which numbers does lighting use? (sRGB and linear color)
5. What happens between the computed light values and the display? (fog, tonemapping)

Goal served (`plan.md`): "various textures of earth, topography"; "beautiful lighting that remains performant ... play with various lighting methods, equations, pipelines, and tradeoffs."

Files:

| File | Role |
|---|---|
| `game/shaders/terrain_painted.gdshader` | New terrain shader: triplanar noise, noise-shifted slope and height rules, contour lines, `paint_view` debug views. Keeps `debug_view` 0–2 from `terrain.gdshader`. |
| `game/shaders/color_ramp.gdshader` | Unshaded test strip: linear ramp, sRGB-decoded ramp, HDR ramp from 0 to 8. |
| `game/src/render/paint_math.gd` | `PaintMath`: GDScript copies of the shader formulas (sRGB curves, triplanar weights, contour distance) for tests and the HUD. |
| `game/src/lessons/painting_the_ground.gd` | Scene root. Extends `src/sandbox.gd`; adds the V, C, M, F keys, places the color strip and the ramp tower, and adds HUD lines. |
| `game/scenes/lessons/03_painting_the_ground.tscn` | Lesson scene: the Lesson 01 height field with the painted material, a `RampTower` (Lesson 02) with ramps of 45°, 60°, 75°, and 85° in the same material, the color strip, `tonemap_white` 6. |
| `game/data/terrain/painted_terrain_material.tres` | `ShaderMaterial` with every uniform of `terrain_painted.gdshader`. |
| `game/data/terrain/ground_noise.tres` | `NoiseTexture2D`: 512 × 512, seamless, Simplex Smooth noise, fBm with 5 octaves. |
| `game/data/debug/color_ramp_material.tres` | `ShaderMaterial` for the color strip. |
| `game/project.godot` | `run/main_scene` pointed to this scene while it was the newest lesson scene. New input actions `cycle_paint_view` (V, D-pad left), `toggle_contours` (C, D-pad right), `cycle_tonemapper` (M, left shoulder), `toggle_fog` (F, right shoulder). |
| `game/tests/test_03_*.gd` | Tests for `PaintMath`, the lesson scene's keys, and the ramp tower's placement. |

`terrain.gdshader` and `terrain_material.tres` from Lesson 01 and `ramp_tower.gd` from Lesson 02 are unchanged. The new shader is a separate file, and the lesson scene assigns a separate material.

Reading: DDG §4.6.1 (the gradient as the direction of steepest ascent on a terrain) and §4.6.3 (df(u) = u · ∇f), for the geometry of contour lines. Godot documentation: "Spatial shaders" (built-ins, render modes, `fwidth`), "Shading language" (uniform hints, `source_color`, sampler filter and repeat hints), "Environment and post-processing" (tonemap, fog). Full entries: `docs/references.md`.

Lesson 01 exercises E7 (curvature view) and E8 (diagonal choice) remain open, and this lesson's code does not solve them. The painted shader colors by slope and height, not by curvature.

## 2. Predict

Work these on paper before reading the code. The sRGB decoding curve is

  linear = c / 12.92 for c < 0.04045, otherwise ((c + 0.055) / 1.055)^2.4,

and the encoding curve is its inverse. A display receives encoded values; light is added and multiplied in linear values.

- **P1.** The Inspector shows `grass_color` as (0.33, 0.40, 0.20). The uniform carries the hint `source_color`. Which three numbers does the fragment shader receive? By what factor would each channel be too bright if the shader received the Inspector numbers instead?
- **P2.** Two lamps light a white wall. Each lamp alone makes the wall display as sRGB 0.5. Both lamps on: what value is displayed? What value would a program display that added the sRGB values?
- **P3.** Triplanar weights are wᵢ = |nᵢ|^k / Σⱼ |nⱼ|^k. Take a slope of angle θ facing +x: n = (sin θ, cos θ, 0). Show that w_x / w_y = tan^k θ. For k = 4, at which angles is w_x = 0.1, 0.5, and 0.9? What is the width of the band in which neither projector has more than 90 % of the weight, for k = 1, 4, 8?
- **P4.** A texture is projected from above alone: texture coordinates (x, z). On a slope of angle θ, how long is the strip of surface covered by one texel that spans Δ on the ground plane, along the direction of steepest ascent? Along the contour? At what angle is the texture stretched by a factor of 2?
- **P5.** Contour lines are spaced Δh = 1 m apart in height. On a slope of angle θ, what is their horizontal spacing? Evaluate for 10°, 20°, 45°. Along which direction do contour lines run, in terms of ∇h? Use DDG §4.6.3.
- **P6.** The shader computes f = h / Δh and d = |fract(f − ½) − ½|. Sketch d as a function of f. The distance in pixels is d / fwidth(f); the coverage of a line falls from 1 to 0 over one pixel centered on half the line width w (it is 0.5 where d / fwidth(f) = w / 2). A flat plane lies at height exactly 2.0 m, with Δh = 1 m. What is fwidth(f) on that plane, and what does the shader draw? Repeat for a flat plane at 2.3 m.
- **P7.** Godot's exponential fog blends a surface at distance d toward the fog color by the fraction 1 − e^(−ρd). The lesson scene uses ρ = 0.004 m⁻¹. What fraction of the surface's own color remains at 25, 100, 250, and 500 m? At what distance is half the color replaced?
- **P8.** Godot's Reinhard tonemapper with white point W is f(x) = x (1 + x / W²) / (1 + x), clamped to [0, 1]. Evaluate f(0.5), f(1), f(6) for W = 6. Simplify f for W = 1. What does that predict for a scene whose Environment keeps the default `tonemap_white` of 1.0?

## 3. Read

### 3.1 `terrain_painted.gdshader`

Read the header comment. Four ideas are numbered there; this section follows them.

1. **Triplanar mapping.** `triplanar_weights()` and `triplanar_sample()`. Read the Q/A comments, then check the claim that each projector uses the two world coordinates that change across its wall. Compare the weights with P3.
2. **Smooth rules.** In `fragment()`, the `else` branch at the end of the view selection. The noise value in [0, 1] becomes a shift in [−0.5, 0.5], scaled by `rock_breakup_degrees` or `dirt_breakup_meters`, and added to the slope angle or the height before `smoothstep`. With both breakup values at 0, the rules are those of `terrain.gdshader`. Why is the shift added to the input of the rule, not to its output?
3. **Contour lines.** `contour_coverage()`. Follow one fragment: height, f, distance in steps, distance in pixels, coverage. The index contour is a second call with a coarser interval and twice the width. Compare with P6.
4. **Color spaces.** The color uniforms carry `source_color`; `ground_noise` carries `hint_default_white, filter_linear_mipmap, repeat_enable` and no `source_color`. Read the Q/A comment above it.

The view selection at the top of `fragment()` checks `debug_view` first, then `paint_view`. Why does Tab (`debug_view`) still work, although `sandbox.gd` was written for `terrain.gdshader`?

### 3.2 `color_ramp.gdshader`

`render_mode unshaded, fog_disabled, cull_disabled`. Which part of the pipeline does each flag remove, and which part remains? The bottom band draws ticks with the construction of `contour_coverage()`, applied to the value instead of the height. Why is `fwidth` computed before the `if` statements?

### 3.3 `paint_math.gd`

The same formulas, in GDScript. Shaders return pixels; tests and the HUD need numbers. `contour_distance()` uses `fposmod(x, 1.0)` where the shader uses `fract(x)`. Why not `fmod`? (Evaluate both at x = −0.25.)

### 3.4 `ground_noise.tres`

Open it in the Inspector. A `NoiseTexture2D` wraps a `FastNoiseLite` generator: Simplex Smooth noise (`TYPE_SIMPLEX_SMOOTH`, the Inspector's default type) summed over 5 octaves (fractal Brownian motion), sampled into a 512 × 512 image. **Seamless** makes the left edge match the right edge and the top match the bottom, so `repeat_enable` tiles it without a seam. **Normalize** (on by default) rescales the image to [0, 1]. Measured over the image: mean 0.495, 5th percentile 0.251, median 0.490, 95th percentile 0.753.

### 3.5 `painting_the_ground.gd` and the scene

The scene has the node names of `sandbox.tscn` (Terrain, Player, HUD/Label), so the script extends `src/sandbox.gd`. Its `_unhandled_input()` calls `super(event)` first, so Tab and N keep their meaning. It writes two uniforms with `set_shader_parameter()` and two `Environment` properties. Open the scene's `WorldEnvironment` in the Inspector and find **Tonemap → Mode**, **Tonemap → White**, and **Fog → Density**. The scene sets **White** to 6; the other lesson scenes keep the default of 1.

The terrain's slopes stay below 41°. For surfaces beyond that range (O3), the scene adds a `RampTower`, the class from Lesson 02, with a platform 4 m high and 6 m wide and ramps of 60°, 45°, 75°, and 85° on the sides facing +z, +x, −z, −x. Its `material` is `painted_terrain_material.tres`, the terrain's material, so V and C change the tower too. The script reaches the tower through the exported property `ramp_tower` (read the Q/A comment in `_ready()`) and sets its height to the ground height at its center, as the Lesson 02 script does. At the chosen site, (16, 38), the ground under the tower's footprint, buried ramp ends included, lies at most 0.85 m below that height (at the outer corner of the 45° ramp), less than the 1 m (`BoxCourse.BURY_DEPTH`) by which the boxes reach below the origin, so no ramp end hangs in the air.

## 4. Run and observe

Open `scenes/lessons/03_painting_the_ground.tscn` and press F6. The color strip hangs to the front left of the start position; the ramp tower stands 16 m to the right. **V** (D-pad left) cycles the paint view: painted, triplanar weights, noise sampled triplanar, noise projected from above alone. **C** (D-pad right) toggles contour lines. **M** (left shoulder) cycles the tonemapper: Linear, Reinhard, Filmic, ACES, AgX. **F** (right shoulder) toggles fog. Tab and N work as in the sandbox. Some experiments edit the material or the environment while the game runs: in the Scene dock choose **Remote**, select the node, and edit in the Inspector (Lesson 00 O3). The material is under `PaintingTheGround/Terrain`, property **Material**.

- **O1.** Walk to the color strip. Press M through all five tonemappers. In the bottom band, at which tick does each tonemapper reach white? Which tonemappers leave the top band (values 0 to 1) as it was under Linear? Compare with P8.
- **O2.** Under Linear, compare the top band and the middle band. Which one looks like an even ramp from black to white? Which one is lighter at its center, and why? Compare with P2.
- **O3.** Turn toward the ramp tower; the labels give the ramp angles. Press V once (triplanar weights). Which colors appear on the terrain, and which on each ramp? Compare with P3. Press V again (noise, sampled triplanar) and look at the 60° and 85° ramps and at the terrain. Press V again (noise, projected from above alone) and look at the same places. What changed, and where? Compare with P4. A fourth press of V returns to the painted view.
- **O4.** Walk up the central hill and watch the contour lines and the HUD's contour number. Where are the lines close together, and where far apart? Look into the distance: what happens to the lines where they are less than two pixels apart?
- **O5.** Press F to turn fog off and on while looking at the far edge of the terrain. Then press M until Linear is shown and repeat. Compare with P7.
- **O6.** Press Tab once (normals view). Set the tonemapper to Linear and turn fog off. Flat ground has the normal (0, 1, 0), written as (0.5, 1.0, 0.5). Does the ground look like the color (0.5, 1.0, 0.5) chosen in a color picker? Lesson 01 O5 named fog and the tonemapper as causes; which step of the pipeline remains?
- **O7.** In the painted view, find a place where grass meets rock. Set **Rock Breakup Degrees** to 0 in the Remote Inspector, then to 20. Describe the boundary in each case.

## 5. Tweak

Restore each change after the observation.

- **T1.** In `terrain_painted.gdshader`, delete `: source_color` from `grass_color`. Predict the result before running, using P1. Then restore it and add `source_color` to `ground_noise` (`uniform sampler2D ground_noise : source_color, hint_default_white, ...`). Predict the effect on the noise view (V twice), using the measured mean of 0.495, then run and compare. Keep the hint, open `game/data/terrain/ground_noise.tres` in the Inspector, set **Color Ramp** to **New Gradient** (black to white), and run again. Explain both results. Restore the shader and clear the Color Ramp afterward.
- **T2.** With the weights view (V once), set **Triplanar Sharpness** to 1, then 16. How do the colors of the terrain and of each ramp change? Which ramp keeps its color at every value, and why? Where would the blend band of k = 16 appear as a seam? Then compare the noise view (V again) at 1, 4, and 16, on the 60° ramp and on the terrain. At which value is the pattern weakest in contrast?
- **T3.** Set **Contour Interval** to 0.25 and **Contour Width Pixels** to 3. Then, in the shader, replace `max(fwidth(f), 1e-6)` in `contour_coverage()` with the constant `0.01`. Walk close to a slope and away from it. What does the line width do without `fwidth`?
- **T4.** In the scene's `WorldEnvironment`, set **Tonemap → White** to 1 and compare Reinhard and Linear on the strip. Then set it to 16. Compare with P8.
- **T5.** Set **Fog → Density** to 0.02. At what distance is half the terrain color replaced? Then set **Fog → Sun Scatter** to 0.5 and turn the camera toward the sun and away from it.
- **T6.** Set **Noise Scale Meters** to 8 and look across the plain from the start position. What pattern appears, and at what spacing? Then set it to 64.

## 6. Exercises

- **E1 ★ Isotropic line width.** `fwidth(f)` is |∂f/∂x| + |∂f/∂y| in screen pixels, an L1 norm. Replace it with `length(vec2(dFdx(f), dFdy(f)))`. Show on paper that the two differ by a factor between 1 and √2, depending on the line's direction on screen. Find contour lines that run along a diagonal of the screen and compare their widths before and after.
- **E2 ★ Slope bands.** Draw lines of constant slope angle (isoclines), every 5°, with the construction of `contour_coverage()` applied to `slope_degrees`. Where on the Gaussian hill do the isoclines form closed rings, and where do they meet the contours at right angles?
- **E3 ★★ Height fog.** Real haze is denser near the ground. Write fog in `terrain_painted.gdshader` (and add `fog_disabled` to the render mode) with density ρ(y) = ρ₀ e^(−y / H). Integrate ρ along the ray from the camera to the fragment to get the optical depth τ, and blend by 1 − e^(−τ). Derive τ in closed form first; treat a horizontal ray as a separate case. Check your fog against the Environment's fog for H → ∞, using P7.
- **E4 ★★ Hiding the tile.** The noise repeats every `noise_scale_meters` (T6). Reduce the visible repetition without a larger texture. Two directions: sample twice at scales whose ratio is irrational and blend; or divide the plane into cells and rotate and offset the texture per cell by a hash of the cell index, blending at cell borders. Describe what you measure to decide that the repetition is less visible.
- **E5 ★★ A tonemapper of your own.** Add a fourth band to `color_ramp.gdshader` that applies the Reinhard curve of P8 in the shader. Run with the Environment's tonemapper set to Linear and compare your band with the HDR band under Godot's Reinhard. Then design a curve of your own: linear up to a knee value, then a soft shoulder that approaches 1. Choose the shoulder so that the curve and its first derivative are continuous at the knee. (A compressor's soft knee is the same construction.)
- **E6 ★★ Fading contours.** Where contour lines are closer than about two pixels (O4), they merge into a dark band. Fade the lines out as their screen spacing falls below a threshold. The screen spacing in pixels is 1 / fwidth(f). Choose the threshold and the fade from measurements.
- **E7 ★★★ Height-based blending.** Linear blending of grass and rock gives a translucent overlap. Use the noise as a height map for each layer and choose, per fragment, the layer whose height plus blend weight is greater, with a narrow transition. Compare the boundary with O7. Explain why this needs the noise as data, not as color.

## 7. Reflect

- **R1.** sRGB encoding spends more of the 256 code values on dark tones than a linear encoding would. Relate this to decibels in audio: why do both scales follow perception rather than physical amplitude?
- **R2.** A tonemapper maps an unbounded range of light into [0, 1] with a curve that has a knee and a shoulder. Compare it with a compressor and a limiter on a mix bus. Which tonemapper here behaves like hard clipping?
- **R3.** Lesson 05 sends footstep events to SuperCollider and needs the surface type under the foot. The rock and dirt rules run on the GPU. Which parts of the shader must exist on the CPU, and how does `PaintMath` point toward a solution? What happens to the noise shift?
- **R4.** SDF rock meshes (Phase 3) have no texture coordinates. Which parts of this lesson transfer to them unchanged? Lesson 20 adds detail normals with triplanar mapping; what extra problem does a normal have that a color does not?
- **R5.** Lesson 19 replaces the constant fog color with light scattered in the atmosphere. Which quantity in P7 depends on the wavelength of light in that model, and what color does it give distant hills?

## 8. Answers

<details><summary>P1</summary>

Decoded (measured with `Color.srgb_to_linear()`): (0.0890, 0.1329, 0.0331). Without the hint the shader would receive (0.33, 0.40, 0.20): too bright by factors of 3.71, 3.01, and 6.04. The darkest channel is affected most, so the color would also lose saturation.
</details>

<details><summary>P2</summary>

sRGB 0.5 is linear 0.2140. Light adds in linear values: 0.2140 + 0.2140 = 0.4281, which encodes to sRGB 0.686. Adding sRGB values gives 1.0, full white, as if the two lamps were 4.7 times brighter together than one alone (1 / 0.214). Lighting computed on encoded values makes light falloff, shading, and blending wrong in the same way.
</details>

<details><summary>P3</summary>

With n = (sin θ, cos θ, 0): w_x / w_y = sin^k θ / cos^k θ = tan^k θ, and w_z = 0, so w_x = tan^k θ / (1 + tan^k θ).

For k = 4: w_x = 0.5 at tan θ = 1, θ = 45°. w_x = 0.1 at tan⁴ θ = 1/9, tan θ = 1/√3, θ = 30°. w_x = 0.9 at tan⁴ θ = 9, tan θ = √3, θ = 60°.

Measured with `PaintMath.triplanar_weights()`, the band in which w_x runs from 0.1 to 0.9:

| k | w_x = 0.1 | w_x = 0.9 | Band width |
|---|---|---|---|
| 1 | 6.3° | 83.7° | 77.3° |
| 4 | 30.0° | 60.0° | 30.0° |
| 8 | 37.2° | 52.8° | 15.5° |

At k = 1 almost every slope blends two projections. For a normal along (1, 1, 1) / √3 all three weights are 1/3 at every k.
</details>

<details><summary>P4</summary>

Along the direction of steepest ascent, a ground distance Δ corresponds to a surface distance Δ / cos θ. Along the contour the height does not change, so the surface distance is Δ. The texel is stretched in one direction by 1 / cos θ: by 2 at 60°, by 1.15 at 30°, by 1.41 at 45°. Near 90° the stretch has no bound.
</details>

<details><summary>P5</summary>

Horizontal spacing = Δh / tan θ = Δh / ‖∇h‖ (Lesson 01 P4). For Δh = 1 m: 5.67 m at 10°, 2.75 m at 20°, 1.00 m at 45°. Contour lines run along directions u with D_u h = u · ∇h = 0 (DDG §4.6.3), perpendicular to ∇h. Steep ground crowds the lines together; on a map, line density reads as slope.
</details>

<details><summary>P6</summary>

d is a triangle wave: 0 at integers, 0.5 at half-integers, slope ±1.

On a flat plane f is constant, so fwidth(f) = 0 and the shader uses the floor value 10⁻⁶. At height 2.0, d = 0 and the pixel distance is 0: every pixel of the plane is covered, and the whole plane takes the contour color. A flat region at exactly a contour height is a contour region, not a line, and the shader paints it so. At 2.3, d = 0.3 and the pixel distance is 3 × 10⁵: nothing is drawn. The lesson terrain has no flat regions, so the case does not arise in the scene.
</details>

<details><summary>P7</summary>

The remaining fraction is e^(−ρd): e^(−0.1) = 0.905 at 25 m, e^(−0.4) = 0.670 at 100 m, e^(−1) = 0.368 at 250 m, e^(−2) = 0.135 at 500 m. Half the color is replaced at d = ln 2 / ρ = 173 m.

Measured with a white unshaded quad, black fog, black background, and the Linear tonemapper, decoding the screen pixel to linear: 0.905 at 25 m, 0.672 at 100 m, 0.366 at 250 m, 0.136 at 500 m. The differences are within one 8-bit step. Godot's exponential fog follows the formula.
</details>

<details><summary>P8</summary>

With W = 6: f(0.5) = 0.5 × 1.0139 / 1.5 = 0.338, f(1) = 1.0278 / 2 = 0.514, f(6) = 6 × 1.1667 / 7 = 1.

With W = 1: f(x) = x (1 + x) / (1 + x) = x. Reinhard with white 1 is the identity, clamped at 1: the same as Linear. Measured on screen with `tonemap_white` = 1: Linear and Reinhard give the same 8-bit values at every input from 0.05 to 16 (63, 118, 188 for 0.05, 0.18, 0.5; 255 from 1 upward). Filmic and ACES also reach 255 at an input of 1 when white is 1. AgX ignores `tonemap_white`; it has its own `tonemap_agx_white` (default 16.29). The sandbox and Lesson 02 scenes use AgX, so the default white of 1 does not affect them.
</details>

<details><summary>O1</summary>

Measured screen values (8-bit sRGB) for unshaded inputs, with `tonemap_white` = 6 as in the lesson scene:

| Input | Linear | Reinhard | Filmic | ACES | AgX |
|---|---|---|---|---|---|
| 0.05 | 63 | 62 | 64 | 54 | 58 |
| 0.18 | 118 | 109 | 124 | 134 | 118 |
| 0.5 | 188 | 157 | 181 | 203 | 172 |
| 1 | 255 | 190 | 213 | 231 | 203 |
| 2 | 255 | 218 | 235 | 246 | 225 |
| 4 | 255 | 242 | 250 | 253 | 239 |
| 8 | 255 | 255 | 255 | 255 | 248 |
| 16 | 255 | 255 | 255 | 255 | 255 |

Linear reaches white at the first tick. Reinhard, Filmic, and ACES reach it at the white point, 6, so between ticks 4 and 8. AgX reaches it near 16, beyond the strip's range of 8. Only Linear leaves the top band unchanged; every other curve darkens or lightens values below 1 as well, so a tonemapper changes the midtones of the whole scene, not only the highlights. AgX maps 0.18 to the same value as Linear.
</details>

<details><summary>O2</summary>

The middle band (sRGB-decoded) looks even: each step of t is an equal step in perceived lightness, because the display re-encodes what the shader decoded. The top band (linear values) is lighter: at t = 0.5 it displays 188 of 255 (measured), the sRGB encoding of linear 0.5. Most of the top band looks light gray; its dark tones occupy a short stretch at the left end. P2 is the same effect seen from the other side: equal steps of light are not equal steps of perceived lightness.
</details>

<details><summary>O3</summary>

Weights view. The terrain is green (y projection) almost everywhere. With k = 4 a second color takes part above 30° (P3): teal where a slope faces ±z, yellow-green where it faces ±x. The terrain's steepest slope is 40.6° (at x = 5.75, z = 21.25; sampled on a 513 × 513 grid), so the tint stays faint: the y projector keeps at least 65 % of the weight on every flank. Each ramp is a plane with a single normal and shows a single color. The 45° ramp (facing +x) is olive: half red, half green, w_x = w_y = 0.5. The 60° ramp (facing +z) is blue with a trace of green, w_z = 0.9. The 75° and 85° ramps are pure blue and pure red (side weight 0.995 and 1.000), as are the vertical side faces of the ramp boxes.

Noise views. On the terrain the two views look the same: the top-down stretch 1 / cos θ is at most 1.32 (P4), and the y projector dominates in the triplanar view as well. On the ramps the top-down view draws the pattern out along the slope, by 2 on the 60° ramp, 3.9 on the 75° ramp, and 11.5 on the 85° ramp, where it becomes vertical streaks. The triplanar view shows blotches of one size on every ramp, because the side projector carries the weight there. Measured on screen (AgX, fog on, a Camera3D placed by a measurement script 11 m from the tower's center, facing the 85° ramp, so that vertical on screen is down the ramp; mean absolute difference of luminance between pixels 4 px apart):

| Surface, view | Horizontal neighbors | Vertical neighbors |
|---|---|---|
| 85° ramp, triplanar | 0.0055 | 0.0054 |
| 85° ramp, top-down | 0.0033 | 0.0005 |
| Terrain, triplanar | 0.0070 | 0.0122 |
| Terrain, top-down | 0.0071 | 0.0123 |

On the 85° ramp the top-down pattern almost stops changing down the slope. On the terrain the two views differ by less than 2 %.
</details>

<details><summary>O4</summary>

The lines crowd on the flanks of the hill and of the ripples and spread on the plain and the hilltop (P5). On screen they keep a width of about one pixel at any distance, because the width is set in pixels by `fwidth`. In the distance, where the screen spacing of the lines falls to a few pixels, they merge into a darker band. E6 addresses this.
</details>

<details><summary>O5</summary>

With fog on, the far edge of the terrain takes on the fog color. The terrain is 128 m across; at 100 m, 33 % of the color is replaced (P7). Fog is applied in linear values before the tonemapper, so the same fog looks different under each tonemapper: under Linear the far hills are lighter, as the tonemapper no longer compresses the fog color.
</details>

<details><summary>O6</summary>

No. The shader writes 0.5 to the red and blue channels of `EMISSION`, which is a linear value; the display shows its sRGB encoding, 188 of 255, which looks like 0.74 in a color picker. The ground in the normals view also reflects the sky (the shader sets `ALBEDO` to black, but the default `SPECULAR` and `ROUGHNESS` still produce a reflection). A view that shows a vector as a color must account for every step after the fragment shader: lighting, fog, tonemapping, and the sRGB encoding at the end. For an exact readout, use `render_mode unshaded, fog_disabled`, the Linear tonemapper, and decode the screen value with the sRGB curve.
</details>

<details><summary>O7</summary>

At 0 the boundary between grass and rock follows the slope rule alone: smooth bands parallel to the contours of slope, as in Lesson 01. At 8 (the default) the band breaks into patches that follow the noise. At 20 rock appears on gentle ground and grass on steep ground; the noise dominates the rule. The breakup value sets how many degrees of slope the noise can trade against.
</details>

<details><summary>T1</summary>

Without `source_color` on `grass_color`, the shader receives (0.33, 0.40, 0.20) as linear values: 3.7, 3.0, and 6.0 times brighter than intended (P1). The grass turns pale and yellow-green.

With `source_color` on `ground_noise`, decoding from sRGB to linear would lower the mean from 0.495 to 0.236 (computed over the image with `PaintMath.srgb_to_linear()`), and a prediction from that number is a darker noise view. The run shows no change. Measured in the noise view (Linear tonemapper, fog off, start position; mean luminance of the lower half of the screen): 0.496 without the hint, 0.496 with it. `NoiseTexture2D` writes a one-channel image: `get_image().get_format()` returns `FORMAT_L8`. On Godot 4.6 the renderer applies no sRGB decoding to that format, so the hint has no effect.

With a Color Ramp, `NoiseTexture2D` maps the noise through the gradient and writes an RGBA8 image (`FORMAT_RGBA8`; mean 0.494, the same values in each color channel). Without the hint the noise view is unchanged (0.496). With the hint the texture is decoded, and the screen mean falls to 0.353. The noise view darkens, its dark patches grow, and its bright patches shrink; in the painted view the color variation becomes darker on average, because 2 × noise − 1 averages −0.53 instead of −0.01. The hint on a data texture is therefore an error that stays hidden while the texture is L8 and appears when its format changes.
</details>

<details><summary>T2</summary>

At k = 1 the blend band spans 6° to 84° (P3), and the side weight on a slope θ is tan θ / (1 + tan θ): 0.15 at 10°, 0.37 at 30°, 0.46 at 40°. The terrain turns teal and yellow-green on most flanks, and the 60° ramp turns a lighter blue (w_z = 0.63). At k = 16 the band shrinks to 41.1°–48.9°. The terrain, whose steepest slope is 40.6°, is pure green (side weight at most 0.078), and the 60°, 75°, and 85° ramps are pure blue or red. The 45° ramp keeps its olive at every k: its normal has |n_x| = |n_y|, so w_x = w_y for any exponent. A curved surface whose slope passes through 45° would show the band of k = 16 as a narrow seam where one projection replaces the other. The scene has no such surface: the terrain stays below 41°, and each ramp is a plane with one normal.

In the noise view the pattern is weakest at k = 1. Two unrelated samples averaged with weights w and 1 − w have a standard deviation √(w² + (1 − w)²) times that of one sample: 0.71 at w = 0.5. Measured on screen (AgX, fog on, a Camera3D placed by a measurement script 14 m from the tower; standard deviation of luminance):

| k | 60° ramp | Terrain |
|---|---|---|
| 1 | 0.052 | 0.048 |
| 4 | 0.059 | 0.059 |
| 16 | 0.064 | 0.060 |

k = 4 (the default) gives a blend band of 30° (P3).
</details>

<details><summary>T3</summary>

With `fwidth`, the lines keep the width of 3 pixels at every distance and on every slope. With the constant, the line width is fixed in units of f, that is, in meters of height: lines are wide on gentle ground and up close, and thin to the point of breaking up on steep ground and at a distance, where one pixel spans more than 0.01 of f.
</details>

<details><summary>T4</summary>

With white 1, Reinhard and Linear give identical images (P8). With white 16 the Reinhard curve reaches 1 at 16, beyond the strip; every value in the HDR band is distinguishable, and the scene's midtones darken further: f(1) = 0.502 for W = 16 against 0.514 for W = 6.
</details>

<details><summary>T5</summary>

Half the color is replaced at ln 2 / 0.02 = 34.7 m. Sun Scatter adds the sun's color to the fog in the direction of the sun, so the fog brightens toward the sun and stays at the fog color away from it.
</details>

<details><summary>T6</summary>

At 8 m the noise repeats every 8 m, and on the plain the repetition shows as a grid of identical patches. At 64 m the repetition is spread over half the terrain and is no longer visible, but the variation becomes large blotches. E4 seeks a texture that shows neither.
</details>
