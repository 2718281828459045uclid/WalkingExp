# Lesson 17. Writing `light()`

Lesson scene: `game/scenes/lessons/17_writing_light.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–16 are unchanged; the Lesson 16 scene has no gallery and uses Godot's built-in light everywhere.

## 1. Orientation

Every lesson since Lesson 01 has handed Godot a surface (positions, normals, a color, a roughness) and let Godot decide how bright it is under the sun. This lesson takes that decision over. Godot calls a function named `light()` once per pixel and per light; a shader may define it. The lesson answers four questions:

1. What does `light()` receive, what must it return, and what does Godot do with the result? (measured, not assumed)
2. How much light may a surface reflect, and how is a reflection model normalized so that it does not create light? (Lambert, the 1/π, integrals over the hemisphere)
3. What do the common alternatives change, and at what cost in energy? (wrap lighting, Oren–Nayar)
4. How does a microfacet model build a highlight from the statistics of tiny mirrors? (GGX distribution, Smith masking-shadowing, Schlick Fresnel)

The method: two shader include files hold the formulas (`brdf.gdshaderinc`) and the `light()` function with four models (`custom_light.gdshaderinc`). `LitShader` appends the include to a copy of Lesson 03's terrain shader and Lesson 09's rock shader, so `fragment()` stays the original, line for line, and only `light()` differs. `ShadingSwitch` swaps the materials of the terrain, the boulder pile and the climbing face between the original (Godot's built-in light) and the four custom models (F5). `ShadingGallery` puts all five side by side: five identical columns of rippled ground and a rock, labelled, in a row whose sun comes from the left. `Brdf` repeats every formula in GDScript, where the tests integrate them over the hemisphere ("white furnace" tests) and a windowed test compares rendered pixels with them.

Goal served (`plan.md`): "beautiful lighting that remains performant. Realism is not the goal but I want to play with various lighting methods, equations, pipelines, and tradeoffs to get something striking." Milestone M4 (`ROADMAP.md`): "Climb a granite formation under custom lighting": the climbing face of Lesson 15 is one of the switched surfaces.

Files:

| File | Role |
|---|---|
| `game/shaders/lighting/brdf.gdshaderinc` | The formulas in GLSL: `lambert_cosine()`, `wrap_cosine()`, `oren_nayar_cosine()`, `ggx_distribution()`, `smith_lambda()`, `smith_g2()`, `schlick_fresnel()`, `ggx_specular_cosine()`. |
| `game/shaders/lighting/custom_light.gdshaderinc` | Uniforms `light_model`, `light_term`, `light_wrap`, `light_sigma_degrees`, `light_f0`; the function `light()`. Includes `brdf.gdshaderinc`. |
| `game/src/render/brdf.gd` | `Brdf` (static): the same formulas in GDScript, `reflected()` (the pixel value a formula predicts), and the hemisphere integrals. |
| `game/src/render/lit_shader.gd` | `LitShader` (static): `make()` appends the include to a base shader, `material()` makes a lit copy of a material, `copy_parameters()`. |
| `game/src/render/shading_switch.gd` | `ShadingSwitch` (Node): five modes (built-in and the four models), F5 and F6. |
| `game/src/render/shading_gallery.gd` | `ShadingGallery` (`@tool` Node3D): five columns of tile, plinth, rock and label. |
| `game/src/lessons/writing_light.gd` | Scene root. Extends `crawling_and_scrambling.gd` (Lesson 16); keys F5, F6, F7; `HUD/LightLabel`. |
| `game/scenes/lessons/17_writing_light.tscn` | The Lesson 16 scene with the player at (14.2, 42), facing the gallery, and three new nodes: `Gallery`, `Shading`, `HUD/LightLabel`. |
| `game/data/rocks/gallery_rock.tres` | `SdfTransform` of `tor_boulder.tres` (Lesson 07) at scale 0.35: the gallery's rock. |
| `game/data/terrain/gallery_tile_field.tres` | `HeightField` (Lesson 01) of the gallery's tiles: ripples of amplitude 0.08 m, wavelengths 0.9 × 0.7 m, no tilt, no mound. |
| `game/project.godot` | Input actions `cycle_shading_model` (F5), `cycle_light_term` (F6), `toggle_lesson_hud` (F7); `run/main_scene`. |
| `game/tests/test_17_brdf.gd` | White-furnace and normalization checks of `Brdf`. |
| `game/tests/test_17_light_scene.gd` | `LitShader`, `ShadingSwitch`, `ShadingGallery` and the scene, headless. |
| `game/tests/test_17_light_pixels.gd` | In a window: Godot's conventions and every model against `Brdf.reflected()`, pixel by pixel. Headless it prints "skipped". |
| `docs/decisions/0017-custom-light-by-shader-include.md` | Why `light()` is an include appended to existing shaders, why built-in and custom are separate materials, why include paths are allowed in code. |

Controls, in the running game (in the editor, F5 and F6 run scenes, as stated at the top): **F5** steps the terrain, the boulder pile and the climbing face through built-in → Lambert → wrap → Oren–Nayar → GGX → built-in. **F6** shows diffuse and specular, diffuse only, or specular only, on every custom material (the four custom gallery columns included). **F7** switches the HUD between this lesson's label and the labels of Lessons 01–16, which cover most of a 1280 × 720 window. No gamepad button is free; the three keys have none. Every key of Lessons 01–16 still works (Tab, V, C on the terrain, U on the rocks), and its setting survives an F5.

The `CrawlGap`, the `Slab` and the `StepRow` share the terrain's material but are not switched: they rebuild their meshes and collision when their `material` changes (decision 0017). They keep the built-in light, as a reference beside the switched terrain.

The HUD label (bottom left) has three lines: the mode and the term; the sun's elevation (27°) and, for the ground under the player, N·L and N·V (V toward the camera); and the value π f cos θ_l of each model for a white surface with that normal, that sun and that view: the brightness each model gives that patch of ground per unit of sun energy, before albedo. `Brdf` computes the line on the CPU.

The `Gallery` node stands at (12, 0, 37.5), about 5 m from the spawn; its five columns stand 2.57 m above it (`row_height()`, section 3.8). The node is turned 26° about the vertical so that the sun, 27° above the horizon, comes from the exact left of a viewer who faces it. The climbing face (Lesson 15), the gap and the slab (Lesson 16) are where they were; the player starts beside the gallery instead of at (0, 40).

Reading:

- Tomas Akenine-Möller et al., *Real-Time Rendering*, 4th ed., chapter 9, "Physically Based Shading": radiometry, the BRDF, Fresnel, microfacet theory, Smith masking.
- Matt Pharr, Wenzel Jakob, Greg Humphreys, *Physically Based Rendering*, 4th ed. (https://pbr-book.org): the chapter on reflection models, for the integrals over the sphere.
- Michael Oren, Shree K. Nayar, "Generalization of Lambert's Reflectance Model", SIGGRAPH 1994: the rough-diffuse model and its qualitative form.
- Bruce Walter, Stephen R. Marschner, Hongsong Li, Kenneth E. Torrance, "Microfacet Models for Refraction through Rough Surfaces", EGSR 2007: the GGX distribution (Trowbridge and Reitz 1975 described the same shape).
- Eric Heitz, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs", *Journal of Computer Graphics Techniques* 3(2), 2014: Λ, the separable and the height-correlated G.
- Christophe Schlick, "An Inexpensive BRDF Model for Physically-based Rendering", *Computer Graphics Forum* 13(3), 1994: the (1 − cos)⁵ Fresnel approximation.
- Keenan Crane, *Discrete Differential Geometry* (`discreteDifferentialGeometry.pdf`): §3.1, p. 30, the Gauss map N : M → S², which places every normal of a surface on the unit sphere (the microfacet distribution D is a density on that sphere); §5.1, p. 87, the vector area ∫ N dA, which depends only on the boundary of the surface (P4).
- Godot documentation, "Spatial shaders", the section on light built-ins. This lesson measures what the page states, and some things it does not.

Full entries: `docs/references.md`.

No earlier exercise is solved here. Lesson 03's shader and Lesson 09's shader are unchanged; the lit copies are generated from them at run time.

## 2. Predict

Notation: n the unit normal, l the unit vector toward the light, v the unit vector toward the camera, h = (l + v)/‖l + v‖ the half vector, θ_l and θ_v their angles from n, ρ the albedo (diffuse reflectance, 0..1), E the irradiance of the sun measured on a plane facing it. A BRDF f(l, v) gives the radiance leaving toward v per unit of irradiance arriving from l: L_out = f(l, v) · E · cos θ_l.

- **P1. Lambert.** A Lambertian surface sends the same radiance L in every direction of the hemisphere above it. (a) Show that the total power leaving one square meter is L · ∫ cos θ dω = π L. (b) Conclude that f = ρ/π reflects the fraction ρ of what arrives. (c) The "white furnace": light arrives from every direction of the hemisphere with the same radiance. Write the directional albedo E(v) = ∫ f(l, v) cos θ_l dω_l and evaluate it for Lambert. (d) Godot's `LIGHT_COLOR` is the light's color × energy × π (section 3.2). What does a white Lambertian surface facing a sun of energy 1 show? What does a surface of albedo 0.5 show at N·L = 0.5?
- **P2. Wrap lighting.** Wrap lighting replaces cos θ_l by max(0, (cos θ_l + w)/(1 + w)). (a) For w = 0.5, at what angle θ_l does the response reach zero? What is it at 90°, where Lambert is zero? (b) Integrate the response, times ρ/π, over the upper hemisphere of light directions, and over the whole sphere (wrap also answers light from below the horizon). How much more light does it return than it receives, for w = 0.5 and w = 1? (c) Where on a sphere lit from one side does the difference to Lambert show most?
- **P3. Oren–Nayar.** In the qualitative model f = ρ/π · (A + B · max(0, cos(φ_v − φ_l)) · sin α · tan β), A = 1 − 0.5 σ²/(σ² + 0.33), B = 0.45 σ²/(σ² + 0.09), α = max(θ_l, θ_v), β = min(θ_l, θ_v). (a) Compute A and B for σ = 30° (in radians). (b) Show that for v = n the directional albedo is A. (c) Compare f with Lambert's for θ_l = θ_v = 60° with the light behind the camera (φ_v = φ_l) and with the light opposite (φ_v − φ_l = 180°). Which looks brighter than Lambert, and why does a full moon look flat?
- **P4. A distribution of facet normals.** Picture the rock's surface as a field of tiny flat facets (microfacets), and D(m) as the area of facets whose normal is m, per unit solid angle of m, per unit area of the smooth surface (the macro surface). Each normal is a point on the unit sphere (the Gauss map, DDG §3.1, p. 30), so D is a density on the sphere. (a) The microsurface and the macro surface share their boundary. Use the vector area of DDG §5.1, p. 87 (∫ N dA depends only on the boundary) to show that ∫ D(m) (n · m) dω_m = 1. (b) For GGX, D(m) = α²/(π((n·m)²(α² − 1) + 1)²). Verify (a) by the substitution u = (n·m)². (c) Compute the peak D at n·m = 1 for the rock's roughness 0.92 (α = roughness²) and for roughness 0.3.
- **P5. The microfacet BRDF.** f = D(h) G(l, v) F(v·h) / (4 (n·l)(n·v)). (a) Only facets with normal h send light from l to v. Explain where n·l and n·v come from, and why a factor 1/(4 v·h) appears when the density over facet normals h is turned into a density over outgoing directions (the reflection doubles the angle). (b) Smith's masking function is G1(s) = 1/(1 + Λ(s)) with Λ(s) = (√(1 + α² tan² θ_s) − 1)/2. Show that the height-correlated G2 = 1/(1 + Λ(l) + Λ(v)) is never smaller than G1(l)·G1(v). (c) For α = 1, D = 1/π. At normal view (Λ(v) = 0) and with F = 1, show that the specular directional albedo is ∫₀¹ μ/(1 + μ) dμ = 1 − ln 2. Where did the rest of the light go?
- **P6. Fresnel and the sum.** (a) With f0 = 0.04, compute Schlick's F at v·h = 1, 0.5 and cos 80°. (b) The GGX model of this lesson is Lambert diffuse plus GGX specular, both evaluated in full. Can the sum reflect more than it receives? At which view angles most? (c) How could a model shift light from the diffuse part to the specular part to keep the sum at most 1?
- **P7. Godot's conventions.** Section 3.2 lists what Godot does with `light()`'s output. (a) Write the one line of `light()` that gives Lambert. (b) A student writes `DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;`. What does a surface of albedo 0.5 at N·L = 0.5 show, and what should it show? (c) Another forgets `/ PI`. (d) A third writes `=` instead of `+=`. With one sun, does the image change? With a sun and a lantern? (e) `NORMAL`, `LIGHT` and `VIEW` are given in view space, not world space. Why can the formulas use them as they are?

## 3. Read

### 3.1 Where `light()` sits

For each pixel of a mesh, Godot runs `vertex()` (per vertex) and `fragment()`, which decides what the surface is at that pixel: `ALBEDO`, `ROUGHNESS`, `METALLIC`, `SPECULAR`, `NORMAL`, `EMISSION`. Then it loops over the lights that reach the pixel and runs the lighting code once per light. That code adds to two sums, the diffuse light and the specular light. Last, Godot composes the pixel:

```
pixel = emission + ambient (× albedo) + diffuse sum (× albedo × (1 − metallic)) + specular sum + reflections
```

then fog, then the tonemapper (Lesson 03). A shader that defines `light()` replaces the lighting code inside the loop and nothing else. Ambient light, sky reflections, global illumination (Lesson 18) and emission do not pass through `light()`.

The built-ins of `light()` used here:

| Built-in | Direction | Meaning |
|---|---|---|
| `NORMAL` | in | the normal `fragment()` wrote, view space |
| `VIEW` | in | toward the camera, view space |
| `LIGHT` | in | toward the light, view space |
| `LIGHT_COLOR` | in | light color × energy × π |
| `ATTENUATION` | in | distance falloff × shadow, 0..1 |
| `LIGHT_IS_DIRECTIONAL` | in | true for a `DirectionalLight3D` |
| `SPECULAR_AMOUNT` | in | the light's `light_specular` |
| `ALBEDO`, `ROUGHNESS`, `METALLIC` | in | what `fragment()` wrote |
| `DIFFUSE_LIGHT` | inout | the diffuse sum |
| `SPECULAR_LIGHT` | inout | the specular sum |

`fragment()`'s `SPECULAR` is not among them. Godot's built-in code turns it into the Fresnel reflectance at normal incidence f0 = 0.16 · `SPECULAR`²; this lesson uses the uniform `light_f0` instead.

### 3.2 The conventions, measured

The documentation describes some of these rules and not others; the lesson does not take them on trust. A windowed scratch harness rendered flat quads under one `DirectionalLight3D` (energy 1, the light 60° from the quads' normal, so N·L = 0.5), an orthographic camera looking straight down, no ambient light, no sky reflection, Linear tonemapping, into a `SubViewport` with a 16-bit float buffer, so that the pixels read back are linear values. `tests/test_17_light_pixels.gd` repeats the main rows.

| Shader | Pixel | Reading |
|---|---|---|
| `render_mode unshaded; ALBEDO = vec3(0.5)` | 0.5000 | readback is linear |
| `light(): DIFFUSE_LIGHT += 0.1 * LIGHT_COLOR`, ALBEDO 1 | 0.3140 | `LIGHT_COLOR` = π × energy (0.1 π = 0.3142; energy 0.5 gives 0.1570) |
| `light(): DIFFUSE_LIGHT += vec3(0.25)`, ALBEDO 0.5 | 0.1250 | the diffuse sum is multiplied by ALBEDO afterward |
| the same, METALLIC 0.5 | 0.0625 | and by (1 − METALLIC) |
| `light(): SPECULAR_LIGHT += vec3(0.25)`, ALBEDO 0.5 | 0.2500 | the specular sum is not (METALLIC 1: also 0.2500) |
| `light(): SPECULAR_LIGHT += vec3(0.1 * SPECULAR_AMOUNT)` | 0.1000 | `SPECULAR_AMOUNT` = `light_specular`: 1.0, the default of a `DirectionalLight3D`; 0.25 gives 0.0250, 0 gives 0 |
| `light(): DIFFUSE_LIGHT += vec3(ATTENUATION * 0.3)` | 0.2998 | `ATTENUATION` = 1 for an unshadowed sun |
| `light(): DIFFUSE_LIGHT += vec3(LIGHT_IS_DIRECTIONAL ? 0.2 : 0.05)` | 0.1999 | the sun is directional |
| no `light()`, `render_mode diffuse_lambert, specular_disabled`, ALBEDO 0.5 | 0.2500 | built-in Lambert = 0.5 × 1 × 0.5 |
| no `light()`, `render_mode specular_disabled` (no diffuse mode named) | 0.2500 | Godot 4.6's default diffuse is Lambert (identical on all 24 quads of the pixel test) |
| `render_mode diffuse_burley, specular_disabled`, roughness 1 / 0.5, camera 2000 m above the quad | 0.2578 / 0.2520 | Burley is a separate mode; it depends on the view direction (below) |
| `render_mode diffuse_lambert_wrap`, roughness 0.5 | 0.2222 | the engine's own wrap mode (exercise E1) |
| `light(): DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI`, ALBEDO 0.5 | 0.2500 | the custom Lambert equals the built-in |
| empty `light()`, ALBEDO 0.5, ambient color 0.2 (sRGB), light on | 0.01654 | ambient alone; the same value as the built-in shader with the light hidden |

Two consequences shape the code. The custom diffuse terms leave out ρ, because Godot multiplies by `ALBEDO` afterward. And the 1/π of every diffuse BRDF stays in the formulas, because `LIGHT_COLOR` carries π: a white surface facing a light of energy 1 shows 1. The energy slider then means "the brightness of a white wall facing the light".

One more measurement explains a line of the pixel test: with the camera 10 m above the quads the custom Oren–Nayar and GGX pixels differed from the CPU formulas by up to 0.34; with the camera 2000 m above, by at most 0.0005. Godot computes `VIEW` from the pixel's position relative to the camera, also for an orthographic camera.

The Burley row shows the same effect. Godot's Burley code (the shader source stored in the Godot binary) is (1/π) F_D(v) F_D(l) N·L with F_D(s) = 1 + (2 (l·h)² r − 0.5)(1 − n·s)⁵, r the roughness. With the camera above the quad, N·V = 1, N·L = 0.5, l·h = cos 30° and albedo 0.5, this is 0.25 (1 + (1.5 r − 0.5)/32): 0.2578 at r = 1 and 0.2520 at r = 0.5, the measured values. For the other rows the camera stood 5 m above a point 6.5 m and 5.5 m to the side of the two Burley quads; seen from there, at N·V 0.61 and 0.67 and from the side of the light, they read 0.2651 and 0.2542. The other rows of the table do not depend on v.

### 3.3 `brdf.gdshaderinc`

Read the header first: it defines the BRDF and the 1/π. Then each function, in order:

- `lambert_cosine(n_dot_l)` returns max(N·L, 0)/π. No ρ (section 3.2).
- `wrap_cosine(n_dot_l, w)` returns max(0, (N·L + w)/(1 + w))/π. The comment says why it is not a BRDF.
- `oren_nayar_cosine(n, l, v, sigma)`. Follow the two question-and-answer blocks: the azimuth difference from vectors flattened into the tangent plane, and sin α · tan β without `acos()`. The cosine of the larger angle is the smaller cosine.
- `ggx_distribution(n_dot_h, alpha)`, `smith_lambda()`, `smith_g2()`, `schlick_fresnel()`: the three questions of a microfacet model (how many facets face h, how many of them are seen, how much one facet reflects).
- `ggx_specular_cosine()` assembles D G F / (4 (n·l)(n·v)) × (n·l). Find the cancellation of n·l.

Compare each function with your answers to P1–P6.

### 3.4 `custom_light.gdshaderinc`

The header is the answer to "what is `light()`", written for this file. The body of `light()` has four parts: normalize the three vectors; choose the diffuse factor by `light_model`; add the GGX specular for model 3, with f0 mixed toward `ALBEDO` by `METALLIC` as Godot does; drop a term for F6; add both, times `LIGHT_COLOR * ATTENUATION`. The specular term is also multiplied by `SPECULAR_AMOUNT`, so the light's `light_specular` slider keeps its meaning.

Why `+=`: the sums start at zero for each pixel and every light adds to them. P7 d asks what `=` would do.

### 3.5 `brdf.gd`

The same formulas in GDScript, with one convention stated at the top: functions named `*_cosine` return f · cos θ_l, the quantity the shader adds. `reflected()` turns that into the pixel value of the measurement setup: π · E · (diffuse + specular). The comment of `diffuse_cosine()` states that ρ is in the CPU value; the shader leaves it to Godot.

The integrals:

- `directional_albedo()` sums f · cos over a grid of equal steps in μ = cos θ and in φ. Read the comment on d ω = dμ dφ: equal steps in μ give cells of equal solid angle, so the midpoint rule needs no weights. `mu_min = −1` integrates over the whole sphere (for wrap lighting).
- `ggx_normalization()` integrates D (n·h) over θ alone, because D does not depend on φ.
- `projected_facet_area()` integrates max(0, v·h) D(h); the result divided by cos θ_v must be 1 + Λ(v). This checks the Λ formula against the distribution it belongs to.
- `ggx_specular_albedo()` does not use an even grid: a smooth surface reflects into a lobe a few degrees wide. The grid is laid over facet normals in proportion to D (n·h), and the value of each cell is divided by the probability of picking it. Follow the three steps in the comment to the quotient F G2 (v·h)/((n·v)(n·h)).

Measured with these functions (256 × 256 cells in μ and φ; the GGX lobe alone with 65 536 × 512 importance-sampled cells):

| Model | E(v) at θ_v = 0°, 30°, 60°, 80° |
|---|---|
| Lambert, ρ = 1 | 1.000000 at all four |
| Oren–Nayar σ = 15° | 0.9140, 0.9377, 0.9720, 0.9992 |
| Oren–Nayar σ = 30° | 0.7731, 0.8143, 0.8741, 0.9215 |
| Oren–Nayar σ = 45° | 0.6743, 0.7220, 0.7913, 0.8463 |
| Oren–Nayar σ = 60° | 0.6157, 0.6662, 0.7396, 0.7979 |
| GGX specular alone, f0 = 1, roughness 0.2 | 0.9983, 0.9980, 0.9955, 0.9681 |
| roughness 0.5 | 0.9158, 0.9041, 0.8573, 0.8556 |
| roughness 0.92 (the rock) | 0.3953, 0.4188, 0.5181, 0.7099 |
| roughness 1 | 0.3069, 0.3352, 0.4507, 0.6682 |
| Lambert ρ = 1 + GGX, roughness 0.92, f0 0.04 | 1.0159 (0°), 1.0247 (60°), 1.0485 (80°) |

The GGX distribution integrates to 1.000031, 1.000005, 1.000001 for α = 0.02, 0.05, 0.1 (4096 steps in θ) and to 1.000000 for α = 0.3, 0.6, 1. The projected facet area matches 1 + Λ within 1e-4 for α = 0.1, 0.5, 1 at θ_v = 0°, 60°, 85°. A plain 512 × 256 grid and the importance-sampled grid give the same GGX albedo to four digits (0.3953 at 0°, 0.5181 at 60°, roughness 0.92). A scratch computation (not in the repository) on a plain grid over (θ_h, φ) of 8192 × 4096 cells, weighted by D (n·h) sin θ_h, gave every GGX row of the table to the digits shown.

The default of `ggx_specular_albedo()`, 256 × 128 cells, is not enough everywhere. It gives the rows for roughness 0.92 and 1 to four digits up to 60° and differs by at most 0.0002 at 80°; at roughness 0.2 and 0.5 it differs by up to 0.004, and at roughness 0.5 it shows the albedo rising from 60° to 80° (0.8574 to 0.8593), where the converged values fall (0.8573 to 0.8556). A narrow lobe seen at a grazing angle needs many more cells; repeat a value at four times the cells before you trust its last digit (E3).

Each `directional_albedo()` call of 65 536 cells took, headless, about 50 ms for Lambert and wrap, 85 ms for Oren–Nayar and 120 ms for Lambert + GGX.

### 3.6 `lit_shader.gd`

`make()` concatenates: the base shader's code, a comment line, and `#include "<path>"`, where the path is the `resource_path` of the `ShaderInclude` it was given. Read the class comment: the point of generating is that the lit shader's `fragment()` is the original, so any difference on screen comes from `light()`. Generated shaders are cached per base shader; every material made from the terrain shader shares one compiled shader. `material()` copies the base material's uniform values; `copy_parameters()` copies by name and skips names the other shader lacks. `has_light_function()` refuses a base that already defines `light()`.

Decision 0017 records why an include path in code does not break decision 0004 ("code does not contain asset paths"): an include is source code compiled with the file that includes it, like an `extends "res://..."` line, and the path `LitShader` writes comes from an exported property that the scene assigns.

### 3.7 `shading_switch.gd`

Read the class comment ("Why swap whole materials"). `_ready()` records each target's original material and makes one lit copy per original; the boulder pile and the climbing face share the weathered material, so they share one lit copy. `material_for()` returns the original for BUILT_IN and the lit copy with `light_model` set otherwise. `set_mode()` copies the base uniforms from the material on screen to the next one before assigning it. Why does it have to? Find the keys of earlier lessons that write uniforms (Tab in `sandbox.gd`, V and C in `painting_the_ground.gd`, U in `implicit_curvature.gd`) and note which material each one writes to.

Targets need a `material` property whose setter only assigns the mesh's `material_override`. Check `Terrain.material` (Lesson 01) and `SdfMesher.material` (Lesson 08), then `BoxCourse.material` (Lesson 02), which is why the slab and the gap are not targets.

### 3.8 `shading_gallery.gd`

A `@tool` script, so the gallery appears in the editor. `rebuild()` makes five columns. Each column has a `Terrain` (Lesson 01) of 2.4 m with the rippled `gallery_tile_field.tres`, a box (plinth) under it, a rock, a label, and its two materials: plain copies of the originals in column 0, lit copies with `light_model` 0–3 in columns 1–4. Column 0 does not share the originals with the scene: the keys of earlier lessons (Tab, V, C, U) write to the materials the terrain and the rocks show, and a column that shared them would change while the other four did not. The rock is meshed once, by a `CurvatureMesher` (Lesson 09) in column 0, so its weathering colors appear; columns 1–4 show the same mesh. One trimesh collision shape serves all five rocks.

`row_height()` puts the whole row at the highest terrain point under any tile. Read its second question: the Lesson 03 ground material colors by world height and draws contour lines at whole meters, so columns at different heights would differ for a reason unrelated to light. `plinth_height()` reaches 0.3 m below the lowest terrain point under each tile. The noise of the ground material is sampled in world space, so the five tiles show different noise patches; the rock material has no noise, and the five rocks are identical.

Measured: the gallery builds in 414 ms headless (the rock: 1594 vertices, 3184 triangles, 285 ms, of which the curvature pass 78 ms). The row stands at y = 2.57 m; the plinths are 0.96 to 2.68 m tall.

### 3.9 The scene and `writing_light.gd`

`17_writing_light.tscn` is the Lesson 16 scene with: the root script `writing_light.gd`, name `WritingLight`, export `start_pitch_degrees` −15; the player at (14.2, 0, 42); `Gallery` after `Slab` (rotated 26° about y, `ground` = `../Terrain`); `Shading` before `HUD` (targets `../Terrain`, `../Rocks/Boulders`, `../ClimbFace`); a label `HUD/LightLabel` at the bottom left. The root turns the camera toward the gallery and pitches it 15° further down, so that the gallery shows above the player's head, and hides the earlier labels.

`_update_hud()` evaluates `Brdf.reflected()` for the four models with the terrain's analytic normal under the player (`HeightField.normal()`, Lesson 01), the sun's direction (+z of its basis), and the direction to the camera. At the start the label reads N·L 0.68, N·V 0.64, Lambert 0.68, wrap 0.79, O-N 0.53, GGX 0.69. Check the wrap and Oren–Nayar values with your formulas from P2 and P3.

### 3.10 The tests

`test_17_brdf.gd` runs the integrals of section 3.5 and checks: Lambert 1 (ρ = 1) and 0.4 (ρ = 0.4); wrap (1 + 2w)/(1 + w) and 1 + w; Oren–Nayar with σ = 0 equal to Lambert, reciprocal, albedo at most 1 and falling with σ; GGX D normalized; Λ against its integral; G2 ≥ G1·G1 on 500 random cases; specular albedo at most 1, 1 − ln 2 at α = 1, grid equal to importance sampling; reciprocity of GGX to 1e-5 (the two dot products v·h and l·h differ in the seventh digit, because `Vector3` holds 32-bit floats). `test_17_light_scene.gd` checks the generated shaders (Lesson 03: 22 base and 5 light uniforms; Lesson 09: 12 and 5), the switch and its keys, the survival of Tab's view across switches, the gallery's materials and placement, the input map, and that `run/main_scene` is the Lesson 17 scene. `test_17_light_pixels.gd` needs a window (section 3.2); every model matched `Brdf.reflected()` within 0.00002 beyond the 0.2 % allowance on 24 quads at roughness 0.5 and 0.92.

## 4. Run and observe

Open `scenes/lessons/17_writing_light.tscn` and press F6. The gallery stands ahead; the sun is 27° up, on the left. Measurements below were read from screenshots (screen values 0–255, after AgX tonemapping), with a camera 9 m in front of the middle column and 4 m above it unless stated; "lit side" means rock points with N·L ≥ 0.6, "terminator" N·L in [−0.1, 0.1).

- **O1. The gallery.** Compare the five rocks. Which column differs most from Lambert, and on which part of the rock? Which column is darker than Lambert on the sunlit side of the rock, and why do the two agree on the dark side? Which columns can you not tell apart? Then compare the front faces of the plinths, which face the camera and are parallel to the sun's direction (N·L = 0).
- **O2. F5 on the scene.** Look at the ground in front of the gallery and at the boulder pile behind it while pressing F5. Order the five modes from darkest to brightest ground. Then look at the `Slab` and the `CrawlGap` (around x = −7 to −16, z = 52): do they change?
- **O3. F6, specular only.** Press F6 twice. What remains on the four custom columns, and what is the brightest custom column now? Why does the built-in column not change?
- **O4. Walk around.** Walk to the far side of the gallery, so that the sun is ahead of you and to the right. Compare the GGX column with the Lambert column again, on the rocks and on the tiles. Then return.
- **O5. Built-in against the custom models.** Godot's built-in light is Lambert plus GGX. Compare the built-in column with the GGX column on the rock and on the tile, and the built-in terrain with the GGX terrain (F5). Where do they agree, and where not? Two differences are listed in section 3.1 and decision 0017: f0, and the G term.
- **O6. The climbing face (M4).** Walk to the climbing face (Lesson 15, at (5.5, 47.5)) and press F5 through the modes while looking at the face. How much does it change, and why? Climb it (key 0) in the mode you prefer.
- **O7. The HUD numbers.** Walk around on the open ground and watch the third line. Find a place where wrap and Lambert differ most, and one where Oren–Nayar exceeds Lambert. What do the angles on the second line say about those places?

## 5. Tweak

Restore each change after the observation.

- **T1.** In `custom_light.gdshaderinc`, comment out the two `+=` lines at the end of `light()`. Run, and compare the four custom columns with each other and with the built-in column. What is still lit, and by what?
- **T2.** Multiply the diffuse line by `ALBEDO`: `DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * diffuse;`. How do the rock and the ground change, and what does it do to color saturation?
- **T3.** In `brdf.gdshaderinc`, remove the `/ PI` from `lambert_cosine()`. By what factor do the Lambert column and the GGX column (which uses it) brighten? Which parts of the image clip?
- **T4.** Set `light_wrap` to 1.0 (in the include's uniform declaration). Where on the wrap rock is it dark now? Measure the energy: `Brdf.directional_albedo()` with `wrap = 1.0` and `mu_min` 0 and −1.
- **T5.** In `light()`, pass `0.3` instead of `ROUGHNESS` to `ggx_specular_cosine()`. Look at the GGX column from the front (O1) and from the far side (O4). Where is the highlight, and why is it hard to see from the front?
- **T6.** Set `light_sigma_degrees` to 0. Which column does the Oren–Nayar column now equal? Then set it to 60 and predict the albedo from the table in section 3.5.
- **T7.** Select the `Sun` in the Remote tree while the game runs and set **Specular** (`light_specular`) to 0. Which column changes, and which does not?

## 6. Exercises

- **E1 ★ Energy-conserving wrap.** Find the normalization c(w) so that c(w) · max(0, cos θ + w)/π integrates over the whole sphere of light directions to the value Lambert's cos θ/π gives over the hemisphere. Add it as `light_model` 4 (extend `ShadingSwitch.Mode` and the gallery), check it with `Brdf.directional_albedo(..., mu_min = -1.0)`, and compare its terminator with plain wrap. Then compare your formula with Godot's `render_mode diffuse_lambert_wrap` (it uses ROUGHNESS as w; section 3.2 gives one measured value).
- **E2 ★ Half-Lambert.** Valve's "Half-Lambert" uses ((N·L)/2 + 1/2)². Derive its integral over the sphere, add it as a model, and compare its falloff on the gallery rock with wrap at w = 1.
- **E3 ★ Smith, separable.** Add the separable G1(l)·G1(v) as a fifth GGX variant. Measure its specular albedo with the importance-sampled integral for roughness 0.5 and 0.92 at four view angles, and compare with the height-correlated table of section 3.5. Where is the difference largest? Can you see it in the gallery?
- **E4 ★★ A banded model.** Add a toon model: N·L quantized into three bands. Make the band edges one pixel wide with `fwidth()`, as Lesson 03's contour lines are. Does the result conserve energy? Measure it.
- **E5 ★★ Diffuse that yields to specular.** Scale the diffuse term by (1 − F(n·v)) or by (1 − E_spec(v)), where E_spec is the specular directional albedo. For the second, bake E_spec(μ_v, roughness) into a 32 × 32 texture with `Brdf.ggx_specular_albedo()` (a `Resource` in `game/data/`, assigned through an export, decision 0004) and sample it in `light()`. Repeat the white-furnace test of the sum (section 3.5, last row).
- **E6 ★★ A lantern.** Add an `OmniLight3D` near the gallery. Check `LIGHT_IS_DIRECTIONAL` and `ATTENUATION` in `light()` (a debug model that writes them), compare the built-in and custom Lambert columns under the lantern alone, and find out whether `LIGHT_COLOR` carries π for an omni light as well.
- **E7 ★★ Oren–Nayar with the full model.** Oren and Nayar's paper gives a more complete model than the qualitative one used here. Implement it from the paper, compare its directional albedo with the table of section 3.5, and decide whether the difference is visible on the rock.
- **E8 ★★★ Multiple scattering.** At roughness 0.92 the GGX lobe returns 0.40 of the light at normal view (f0 = 1); the rest is light that a full model would bounce between facets. Read Kulla and Conty (2017) on energy compensation, implement it with a baked table, and show with the white-furnace test that the lobe returns 1 for f0 = 1.
- **E9 ★★★ Your own model.** Design a model for this place: rock in desert light, the look of `plan.md` ("something striking"), not realism. Give it a name, derive its energy over the hemisphere, add it to the switch and the gallery, and write down which property of Lambert, wrap, Oren–Nayar and GGX you kept or dropped.

## 7. Reflect

- **R1.** The climbing face changes little under F5 (O6). What lights it, and which lesson can change that? (Lesson 18: shadows and global illumination.)
- **R2.** The sun of this scene stands 27° above the horizon. As it sets (Lesson 19: time of day), N·L falls on the ground and grazing angles grow. Which model's difference to Lambert grows with it, and which shrinks?
- **R3.** Lesson 20 adds detail normals: `fragment()` will bend `NORMAL` before `light()` reads it. Which of the four models shows small normal changes most, and which hides them? (Think of wrap's slope (1/(1 + w)) and of Oren–Nayar's A.)
- **R4.** The rock material already knows its mean curvature per vertex (Lesson 09, `CUSTOM0`). Could curvature choose σ or the roughness per point, so that worn edges look smooth and cavities rough? What would `light()` need to receive, and how could `fragment()` pass it?
- **R5.** Lesson 28 maps game state to music. The HUD's third line is a number for "how much sun falls on the ground where the player stands". Is it a useful input for the score, and how often would you send it?

## 8. Answers

<details><summary>P1</summary>

(a) With radiance L in every direction, the power through one square meter is ∫ L cos θ dω over the hemisphere: ∫₀^{2π} ∫₀^{π/2} L cos θ sin θ dθ dφ = 2π L · ½ = π L.

(b) A surface that receives irradiance E and reflects the fraction ρ sends out ρE, so L = ρE/π. Since L = f · E for light arriving along the normal, f = ρ/π. For any other direction the arriving power per square meter is E cos θ_l, and L = (ρ/π) E cos θ_l.

(c) E(v) = ∫ (ρ/π) cos θ_l dω_l = (ρ/π) · π = ρ, for every v. The test measured 1.000000 at 0°, 30°, 60°, 80° and 0.400000 for ρ = 0.4.

(d) π · (1/π) · 1 · 1 = 1 for the white surface facing the light. For albedo 0.5 at N·L = 0.5: 0.5 · 0.5 = 0.25 (measured 0.2500, section 3.2).
</details>

<details><summary>P2</summary>

(a) At cos θ_l = −w: θ_l = 120° for w = 0.5, 30° past the geometric terminator. At 90° the response is w/(1 + w) = 1/3.

(b) With μ = cos θ_l, over the upper hemisphere: (1/π) · 2π ∫₀¹ (μ + w)/(1 + w) dμ = 2 (½ + w)/(1 + w) = (1 + 2w)/(1 + w). Over the whole sphere the response is nonzero for μ > −w: 2 ∫_{−w}^{1} (μ + w)/(1 + w) dμ = (1 + w)²/(1 + w) = 1 + w. For w = 0.5: 4/3 and 1.5, a third and a half more than Lambert's 1. For w = 1: 1.5 and 2. The test measured 1.333333 and 1.500000, 1.500000 and 2.000000.

(c) Near the terminator, where Lambert falls to zero and wrap still gives about a third of its maximum. Facing the light the two agree (both 1).
</details>

<details><summary>P3</summary>

(a) σ = 30° = 0.5236 rad, σ² = 0.2742: A = 1 − 0.5 · 0.2742/0.6042 = 0.7731, B = 0.45 · 0.2742/0.3642 = 0.3388.

(b) For v = n, θ_v = 0, so β = 0 and tan β = 0: f = (ρ/π) A for every l, and E(n) = A ∫ cos θ_l dω/π = A = 0.7731. The integral measured 0.7731.

(c) Same side: sin 60° · tan 60° = 1.5, so f = (ρ/π)(0.7731 + 0.3388 · 1.5) = (ρ/π) · 1.281, 28 % brighter than Lambert. Opposite side: cos(φ_v − φ_l) = −1 is clamped to 0, f = (ρ/π) · 0.7731, 23 % darker. Light behind the observer makes a rough surface brighter toward its rim than Lambert predicts: near the rim both θ_l and θ_v approach 90°, sin α tan β grows, and the B term offsets the falling cos θ_l. A full moon seen with the sun behind the Earth is that case.
</details>

<details><summary>P4</summary>

(a) The vector area ∫ N dA depends only on the boundary (DDG §5.1, p. 87). The microsurface and the flat macro patch have the same boundary, so their vector areas are equal. The macro patch has vector area n · A_macro. The n-component of the microsurface's vector area is ∫ (n · m) dA_micro, and by the definition of D this is A_macro ∫ D(m)(n · m) dω_m. Equating gives ∫ D(m)(n · m) dω_m = 1: the facets, projected onto the macro plane, cover it once. (A height-field microsurface has n · m > 0 for every facet, so no facet cancels another.)

(b) With μ = n·m and dω = dμ dφ: 2π ∫₀¹ α² μ/(π((α² − 1)μ² + 1)²) dμ. With u = μ², du = 2μ dμ: ∫₀¹ α²/((α² − 1)u + 1)² du = α²/(α² − 1) · [−1/((α² − 1)u + 1)]₀¹ = α²/(α² − 1) · (1 − 1/α²) = 1.

(c) D(1) = 1/(πα²). Roughness 0.92: α = 0.8464, D = 0.444. Roughness 0.3: α = 0.09, D = 39.3. The smooth surface has 88 times the facet density at n.
</details>

<details><summary>P5</summary>

(a) Follow the light through one macro square meter dA. Light of radiance L_i arrives from a cone dω_l around l. The facets with normals in a cone dω_h around h have area D(h) dω_h dA; each receives L_i dω_l (l·h) per unit of its own area; the fraction G of them is lit and seen, and each reflects the fraction F. The reflected power is dΦ = L_i dω_l (l·h) · D dω_h dA · G F. It leaves into a cone dω_v = 4 (v·h) dω_h: a mirror doubles the angle between v and the facet normal, so a cone of normals maps to a cone of reflected directions with four times the solid angle, times the cosine v·h. The outgoing radiance is power per projected area per solid angle: L_o = dΦ / (dA cos θ_v dω_v) = L_i dω_l D G F (l·h) / (4 (v·h) cos θ_v), and l·h = v·h cancels. The BRDF divides by the arriving irradiance L_i cos θ_l dω_l: f = D G F / (4 cos θ_l cos θ_v). So n·v is the macro patch's projected area seen from v, n·l the conversion from radiance to irradiance, and the 4 is the Jacobian of the reflection (Walter et al. 2007 give the same steps).

(b) G1(l) G1(v) = 1/((1 + a)(1 + b)) = 1/(1 + a + b + ab) with a = Λ(l) ≥ 0, b = Λ(v) ≥ 0. Since ab ≥ 0, 1 + a + b ≤ 1 + a + b + ab, so 1/(1 + a + b) ≥ the product. The test found no case with a smaller G2 among 500 random ones.

(c) With α = 1, Λ(μ) = (1/μ − 1)/2, G2 = 1/(1 + (1/μ − 1)/2) = 2μ/(1 + μ). f · cos θ_l = D G2 F/(4 n·v) = (1/π) · 2μ/(1 + μ)/4. Integrate over the hemisphere: 2π ∫₀¹ μ/(2π(1 + μ)) dμ = ∫₀¹ μ/(1 + μ) dμ = 1 − ln 2 = 0.3069. The test measured 0.30685. The missing 69 % is light that hits a second facet after the first: the Smith G counts it as lost, because the model follows one bounce. On a real rough metal that light leaves after two or more bounces (E8).
</details>

<details><summary>P6</summary>

(a) v·h = 1: F = 0.04. v·h = 0.5: 0.04 + 0.96 · 0.5⁵ = 0.070. v·h = cos 80° = 0.174: 0.04 + 0.96 · 0.826⁵ = 0.410.

(b) Yes. The Lambert part alone returns ρ ≤ 1, and the specular part adds its own albedo on top: measured, 1.0159 at normal view, 1.0247 at 60°, 1.0485 at 80° for ρ = 1, roughness 0.92, f0 = 0.04. The excess grows toward grazing angles, where F grows. Godot's built-in light adds its two terms in the same way.

(c) Light that the specular lobe reflects never enters the material, so it cannot come back out as diffuse light. Scale the diffuse term by (1 − F) or by (1 − E_spec(v)) (E5).
</details>

<details><summary>P7</summary>

(a) `DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;` (`lambert_cosine()` and the last lines of `light()`).

(b) It shows 0.125; it should show 0.25. Godot multiplies by ALBEDO again, so the albedo is squared (measured 0.1250).

(c) π times too bright: 0.785 instead of 0.25 (measured 0.7852).

(d) With one sun, no change: the sum starts at zero for each pixel (measured: 0.2500 both ways). With a sun and a lantern, only the light processed last would remain.

(e) The formulas use dot products and lengths only. A rotation, such as the change from world to view space, preserves both.
</details>

<details><summary>O1</summary>

Measured (mean screen value of rock points in each N·L range, at the same surface points in every column):

| N·L | built-in | Lambert | wrap | Oren–Nayar | GGX |
|---|---|---|---|---|---|
| ≥ 0.6 (lit side) | 145.0 | 143.3 | 148.1 | 134.8 | 145.7 |
| 0.3–0.6 | 139.9 | 137.4 | 149.0 | 130.7 | 138.8 |
| 0.1–0.3 | 126.2 | 124.4 | 147.9 | 121.9 | 125.7 |
| −0.1–0.1 (terminator) | 107.7 | 107.4 | 142.6 | 107.2 | 108.2 |
| −0.4 to −0.1 | 99.6 | 98.9 | 114.2 | 99.3 | 100.0 |
| < −0.4 | 95.6 | 95.1 | 95.3 | 94.3 | 92.0 |

Wrap differs most, at and past the terminator: 142.6 against 107.4, where Lambert has only the ambient light. The dark side starts 30° later (P2 a), so the shadow edge moves around the rock and softens. Oren–Nayar is darker than Lambert on the lit side (134.8 against 143.3), as A = 0.77 predicts for a sun from the side, where the B term contributes little. Where N·L ≤ 0 both add no direct light (`oren_nayar_cosine()` and `lambert_cosine()` return 0), so both show the ambient light alone; their values there differ by less than 1. Built-in, Lambert and GGX are within 2.5 of each other except below N·L = −0.4 (O5): the rock's GGX lobe is wide and weak (roughness 0.92, f0 0.04). The plinths' front faces (N·L = 0): Lambert 58.3, wrap 82.7, the other three 62–64. At N·L = 0 only wrap adds direct light; the differences among the other four come from the world-space noise of the ground material (section 3.8, T1), not from the models.

Below N·L = −0.4 even wrap is dark: (−0.4 + 0.5)/1.5 = 0.07 at most, and part of that region lies in the rock's own shadow (`ATTENUATION`). On the tiles, points in the rocks' shadows read 55.0–56.7 in all five columns, against 80.1–91.1 in the sun (measured with the ground noise set to zero in the harness, so that the five tiles are identical): `ATTENUATION` carries the shadow into every model.
</details>

<details><summary>O2</summary>

Mean screen value of the ground in the lower left of the start view: built-in 93.2, Lambert 90.6, wrap 96.6, Oren–Nayar 83.8, GGX 96.8; of the boulder pile behind the gallery: built-in 96.7, Lambert 95.4, wrap 105.9, Oren–Nayar 92.1, GGX 97.2. Darkest to brightest on the ground: Oren–Nayar, Lambert, built-in, wrap and GGX (close). The `Slab`, the `CrawlGap` and the `StepRow` do not change: they are not targets of the switch (section 3.7) and keep the built-in light.
</details>

<details><summary>O3</summary>

Specular only: the four custom columns lose their direct diffuse light and keep the ambient light and the sky reflection, which do not pass through `light()`. The lit side of the rock reads 82.1–82.6 in the Lambert, wrap and Oren–Nayar columns (no specular term) and 87.6 in the GGX column: the specular lobe adds about 5. On the tiles, sunlit points read 52.4–53.1 against 59.9 for GGX. The built-in column stays at 145.0: it uses a plain copy of the original material, which has no `light_term` uniform; F6 acts on `light()`, and the built-in material has none.
</details>

<details><summary>O4</summary>

From the far side, with the sun ahead and to the right: rock lit side, Lambert 157.9, GGX 159.4, built-in 158.1; Oren–Nayar 149.4; wrap 162.0, and at the terminator wrap 132.4 against Lambert 98.3. The GGX highlight remains weak at roughness 0.92, but on the tiles the sunlit points read 87.9 for GGX against 83.5 for Lambert. With roughness 0.3 (T5) the brightest rock point of the GGX column reads 199 from the far side, against 179 for Lambert: the mirror direction of the sun now points toward the camera from some of the rock's facets.
</details>

<details><summary>O5</summary>

On the rock, the built-in and the GGX column agree within 1.1 on every N·L range of O1 except the darkest (where the two columns are seen from different angles and the sky reflection differs): both use f0 = 0.04 (the rock writes no `SPECULAR`, so 0.16 · 0.5² = 0.04), and their G terms differ little at this roughness. A scratch harness with the setup of the pixel test (section 3.2) measured the two G terms: with Godot's built-in GGX and the custom one on quads tilted up to 75°, the whole pixel differed by at most 0.36 % (roughness 0.5) and 0.23 % (0.92); the specular term alone by up to 21 % and 4.9 %, at the steepest quads, where Hammon's approximation and the exact height-correlated G2 differ most.

On the ground they disagree: the terrain writes `SPECULAR = 0.3`, so the built-in light uses f0 = 0.16 · 0.3² = 0.0144, while `light_f0` is 0.04. Ground in the start view: built-in 93.2, GGX 96.8. On the tiles, sunlit points: built-in 87.2, GGX 88.0, Lambert 83.2. Setting `light_f0` to 0.0144 on the lit terrain material would give the built-in reflectance at normal incidence; toward grazing angles the built-in code also lowers Fresnel's limit from 1 to 50 f0 = 0.72 (an approximate specular occlusion), which the Schlick form here does not. `light()` cannot read `SPECULAR` (section 3.1).
</details>

<details><summary>O6</summary>

Mean screen value of the climbing face, seen from the player standing at (3, 40): built-in 71.1, Lambert 71.1, wrap 72.2, Oren–Nayar 71.0, GGX 71.1. The face looks toward −z, away from the sun: its normal (0, 0, −1) gives N·L = −0.39 with the sun's direction (−0.80, 0.45, 0.39). It receives no direct sun, only the knobs' upper sides catch a little, and wrap adds at most (−0.39 + 0.5)/1.5 = 0.07 of the sun where the shadow map lets it through. What lights the face is the ambient light, which `light()` does not touch. R1 and Lesson 18 continue from here.
</details>

<details><summary>O7</summary>

At the start: N·L 0.68, N·V 0.64, Lambert 0.68, wrap (0.68 + 0.5)/1.5 = 0.79, Oren–Nayar 0.53 (A · 0.68 = 0.526 plus a small B term), GGX 0.69 (Lambert plus 0.01 of specular). Wrap differs most from Lambert where N·L is small: on slopes whose downhill direction points away from the sun (toward +x and −z), where wrap stays above zero after Lambert reaches it. Oren–Nayar exceeds Lambert where the camera and the sun are on the same side of the normal, both at large angles from it: with the sun behind you, on ground that slopes away from you, θ_l and θ_v are both large and the azimuth difference is small (P3 c).
</details>

<details><summary>T1</summary>

The four custom columns become identical and match the built-in column with the sun hidden: what remains is the ambient light and the sky reflection, added outside `light()`. Measured with the sun hidden: the five columns read within 1 of each other on every N·L range except the darkest (rock lit side 80.9–82.5), and the plinth front faces 52.9–63.5, which differ by the world-space noise of the ground material. On a quad: an empty `light()` under ambient color 0.2 gave 0.01654, the value of the built-in shader with the light hidden (section 3.2).
</details>

<details><summary>T2</summary>

The albedo is applied twice. A surface of albedo 0.5 drops from 0.25 to 0.125 at N·L = 0.5 (measured on a quad). Each color channel is squared: a channel of value x keeps the fraction x of its light, so dark channels lose more than bright ones and colors become more saturated. In the gallery (measured): the Lambert rock's lit side fell from 143.3 to 113.3; sunlit tile points from 83.2 to 58.7, 4.8 above the 53.9 of the tiles in shade. The ambient light, which Godot multiplies by albedo once, is unchanged, so the balance between sun and shade shifts toward shade.
</details>

<details><summary>T3</summary>

By π in light: 0.25 becomes 0.785 on a quad (measured). On screen the factor is smaller, because AgX compresses bright values (Lesson 03): the lit side of the Lambert rock rose from 143.3 to 187.7, its brightest point from 179 to 216, sunlit tile points from 83.2 to 120.0; no rock point reached 255. The GGX column, which uses `lambert_cosine()`, rose the same way (145.7 to 188.8); points in shade keep their values, because the ambient light does not pass through `light()`. Wrap and Oren–Nayar keep their 1/π and do not change.
</details>

<details><summary>T4</summary>

With w = 1 the response (cos θ_l + 1)/2 reaches zero only at θ_l = 180°, the point that faces away from the sun. Measured on the wrap rock: terminator 155.1 (was 142.6), N·L from −0.4 to −0.1 126.0 (was 114.2), lit side 150.3 (was 148.1); below N·L = −0.4 95.5, because the rock's own shadow (`ATTENUATION`) covers that side. The integrals: 1.5 over the hemisphere, 2 over the sphere (P2 b).
</details>

<details><summary>T5</summary>

From the front (sun from the left, camera in front of the row) the brightest point of the GGX rock rose from 180.3 to 185.7; from the far side, from 179.3 to 199.0 (measured). The highlight sits where the normal is the half vector h, halfway between the directions to the sun and to the camera. From the front, with the sun at 90° to the left, h points left and toward the camera at a large angle from both, and few points of the rock face that way; from the far side, with the sun ahead and to the right, h lies between the camera and the sun, and the screenshot shows a small bright spot on the upper right of the GGX rock, the side that faces between them. The mean over the lit side moves from 145.7 to 144.2 (front): a sharp lobe concentrates the reflected light in a few points.
</details>

<details><summary>T6</summary>

With σ = 0, A = 1 and B = 0: the Oren–Nayar column equals the Lambert column (lit side 143.7 against 143.3, terminator 107.6 against 107.4, measured). With σ = 60° the table of section 3.5 gives 0.616 at normal view, against 0.773 at 30°: the column darkens further. Measured: lit side 127.5 at 60°, 134.8 at 30°, 143.3 for Lambert.
</details>

<details><summary>T7</summary>

`SPECULAR_AMOUNT` becomes 0 (section 3.2: it equals `light_specular`), so the GGX column loses its specular term and equals the Lambert column; the built-in column loses its specular term too, because Godot's built-in code multiplies by the same factor. Lambert, wrap and Oren–Nayar do not change: they have no specular term.
</details>
