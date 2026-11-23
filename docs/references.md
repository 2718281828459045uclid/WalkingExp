# References

Grouped by subject. The lesson numbers refer to `ROADMAP.md`.

## Discrete differential geometry

Keenan Crane, *Discrete Differential Geometry: An Applied Introduction* (revision of 29 January 2025). File: `discreteDifferentialGeometry.pdf` in the repository root. Course page: https://www.cs.cmu.edu/~kmcrane/Projects/DDG/

| Chapter | Subject | Lessons |
|---|---|---|
| 2 | Combinatorial surfaces, halfedge mesh; §2.2.1 oriented complexes, §2.3 manifold and nonmanifold, Exercise 2.1 and the Euler–L'Huilier formula V − E + F = 2 − 2g | 08 (orientation, nonmanifold edges, Euler characteristic of meshes), 21 |
| 3.1–3.2 | Surfaces, derivatives, tangent vectors; §3.2.2 directional derivatives | 01, 02, 16 (the normal of a graph surface, P7), 17 (§3.1, p. 30: the Gauss map, P4) |
| 3.4 | Curvature of surfaces; §3.4.1 principal, mean (H = (κ₁ + κ₂)/2) and Gaussian (K = κ₁κ₂) curvature, normal curvature κₙ(Y) = κ₁cos²θ + κ₂sin²θ; §3.4.2 fundamental forms | 01 (exercise 7), 09, 10 (mean curvature per pixel), 15 (hold tests; knob or edge from κ₂/κ₁; developable edges K = 0) |
| 4 | Exterior calculus; §4.6.1 gradient as steepest ascent; §4.6.3 directional derivative df(u) = u · ∇f | 02 (§4.6.3), 03 (§4.6.1, §4.6.3: contour lines), 07 (§4.6.1, §4.6.3: the gradient of a distance field, the Lipschitz bound), 10 (§4.6.3: the safe step of sphere tracing), 15 (§4.6.1, p. 68: the outward normal of a hold), 16 (§4.6.1: the scramble faces up the gradient); background for 23–24 |
| 5 | Curvature of discrete surfaces; §5.1 vector area; §5.4 vertex normal definitions; §5.6 convergence tests | 01 (exercises 5–6), 17 (§5.1, p. 87: projected microfacet area, P4), 22 |
| 6 | The Laplacian, Poisson equation, mean curvature flow | 23 |
| 7 | Surface parameterization | texture coordinates for SDF rock meshes (unscheduled) |
| 8 | Vector field decomposition and design | 24, 25 |

## Signed distance fields and procedural shape

- Inigo Quilez, articles: https://iquilezles.org/articles/ — in particular "distance functions" (3D primitives), "smooth minimum", "normals for an SDF", "raymarching SDFs", "value noise derivatives", "fBM". Lessons 07–10, 01 (exercise on noise).
- Inigo Quilez, articles "distance functions" (sphere, box, rounded box, capsule, ellipsoid, opRepLim), "smooth minimum" (quadratic polynomial smin and its k/4 bound), "ellipsoid SDF" (the k0(k0 − 1)/k1 estimate), "domain warping". Lesson 07.
- John C. Hart, "Sphere tracing: a geometric method for the antialiased ray tracing of implicit surfaces", *The Visual Computer* 12(10), 1996. Lipschitz bounds of distance functions and of their combinations. Lessons 07, 10 (the march loop, the step f / L, the hit tolerance).
- Sarah F. F. Gibson, "Constrained elastic surface nets: generating smooth surfaces from binary segmented data", MICCAI 1998. Origin of surface nets. Lesson 08.
- Mikola Lysenko, "Smooth voxel terrain (part 2)", 0fps.net, 2012. Marching cubes and naive surface nets compared. Lesson 08.
- William E. Lorensen and Harvey E. Cline, "Marching cubes: a high resolution 3D surface construction algorithm", SIGGRAPH 1987. Lesson 08 (exercise E1).
- Tao Ju, Frank Losasso, Scott Schaefer, Joe Warren, "Dual contouring of Hermite data", SIGGRAPH 2002. Lesson 08 (exercise E2).
- Godot documentation, "Spatial shaders" (tutorials/shaders/shader_reference/spatial_shader): fragment built-ins `DEPTH`, `LIGHT_VERTEX`, `NORMAL`, `CAMERA_POSITION_WORLD`, `render_mode cull_front`; "Shader preprocessor" (`#include` of `.gdshaderinc` files). Lesson 10.
- Godot documentation, "Using compute shaders" (tutorials/shaders/compute_shaders) and the `RenderingDevice` class reference. Lesson 08.
- Ron Goldman, "Curvature formulas for implicit curves and surfaces", *Computer Aided Geometric Design* 22(7), 2005, 632–658. Eq. (4.1) Gaussian curvature g·adj(H)g/|g|⁴, Eq. (4.2) mean curvature (g·Hg − |g|² tr H)/(2|g|³), Eq. (4.3) principal curvatures, Example 4.1 (sphere: K_M = −1/R with N = ∇F/|∇F|). Goldman's mean curvature has the opposite sign of the convention used in Lesson 09. Lesson 09.
- Inigo Quilez, "normals for an SDF" (central differences and the tetrahedron technique). Lesson 09 (exercise E3).
- Ken Perlin, "Improving Noise", SIGGRAPH 2002.
- Amit Patel, Red Blob Games: https://www.redblobgames.com — noise-based terrain, grids.

## Rendering

- Tomas Akenine-Möller et al., *Real-Time Rendering*, 4th ed., CRC Press, 2018. Lessons 17–20.
- Matt Pharr, Wenzel Jakob, Greg Humphreys, *Physically Based Rendering*, 4th ed. Free online: https://pbr-book.org. Lessons 17–19.
- Godot documentation: https://docs.godotengine.org/en/stable/ — "Shading language", "Spatial shaders", "Procedural geometry", "Using compute shaders".
- Godot documentation, "Environment and post-processing" (tonemap modes, white point, exponential fog) and class reference `Environment`, `NoiseTexture2D`, `FastNoiseLite`. Lesson 03.
- IEC 61966-2-1:1999, *Default RGB colour space — sRGB*. The piecewise encoding and decoding curves. Lesson 03.
- Erik Reinhard, Michael Stark, Peter Shirley, James Ferwerda, "Photographic Tone Reproduction for Digital Images", SIGGRAPH 2002. The x / (1 + x) operator and its white-point extension. Lesson 03.
- Ben Golus, "Normal Mapping for a Triplanar Shader" (blog post, 2017): https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a — triplanar weights and blending; its normal-map part belongs to Lesson 20. Lesson 03.
- Johann Heinrich Lambert, *Photometria, sive de mensura et gradibus luminis, colorum et umbrae*, 1760. The cosine law of diffuse reflection. Lesson 17.
- Tomas Akenine-Möller et al., *Real-Time Rendering*, 4th ed., chapter 9, "Physically Based Shading": radiometry, the BRDF, Fresnel, microfacet theory, masking-shadowing. Lesson 17.
- Michael Oren, Shree K. Nayar, "Generalization of Lambert's Reflectance Model", SIGGRAPH 1994. Rough diffuse surfaces as V-cavities; the qualitative model with A = 1 − 0.5 σ²/(σ² + 0.33), B = 0.45 σ²/(σ² + 0.09) (`oren_nayar_cosine()`). Lesson 17 (exercise E7 for the fuller model).
- T. S. Trowbridge, K. P. Reitz, "Average irregularity representation of a rough surface for ray reflection", *Journal of the Optical Society of America* 65(5), 1975. The distribution later named GGX. Lesson 17.
- Bruce Walter, Stephen R. Marschner, Hongsong Li, Kenneth E. Torrance, "Microfacet Models for Refraction through Rough Surfaces", Eurographics Symposium on Rendering 2007. The GGX distribution, its Smith G1, the microfacet BRDF and the Jacobian of reflection. Lesson 17 (P4, P5).
- Robert L. Cook, Kenneth E. Torrance, "A Reflectance Model for Computer Graphics", *ACM Transactions on Graphics* 1(1), 1982. The D G F / (4 (n·l)(n·v)) form. Lesson 17.
- Eric Heitz, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs", *Journal of Computer Graphics Techniques* 3(2), 2014. Λ, the projected-area constraint, separable and height-correlated G2 (`smith_g2()`, `Brdf.projected_facet_area()`). Lesson 17 (P5, E3).
- Christophe Schlick, "An Inexpensive BRDF Model for Physically-based Rendering", *Computer Graphics Forum* 13(3), 1994. The Fresnel approximation f0 + (1 − f0)(1 − cos)⁵. Lesson 17 (P6).
- Brent Burley, "Physically-Based Shading at Disney", SIGGRAPH 2012 course "Practical Physically Based Shading in Film and Game Production". The Burley diffuse model (Godot's `diffuse_burley`), perceptual roughness. Lesson 17.
- Brian Karis, "Real Shading in Unreal Engine 4", SIGGRAPH 2013 course "Physically Based Shading in Theory and Practice". α = roughness², the split between D, G, F. Lesson 17.
- Earl Hammon, Jr., "PBR Diffuse Lighting for GGX+Smith Microsurfaces", GDC 2017. The approximation of the height-correlated G that Godot's built-in GGX uses (cited in Godot's scene shader source). Lesson 17 (O5).
- Steve McAuley, "Energy-conserving wrapped diffuse", blog post, 2011, cited in Godot's scene shader source for `diffuse_lambert_wrap`. Lesson 17 (exercise E1; read after the exercise).
- Simon Green, "Real-Time Approximations to Subsurface Scattering", *GPU Gems*, chapter 16, Addison-Wesley, 2004. Wrap lighting. Lesson 17.
- Jason Mitchell, Gary McTaggart, Chris Green, "Shading in Valve's Source Engine", SIGGRAPH 2006 course "Advanced Real-Time Rendering in 3D Graphics and Games". Half-Lambert. Lesson 17 (exercise E2).
- Christopher Kulla, Alejandro Conty, "Revisiting Physically Based Shading at Imageworks", SIGGRAPH 2017 course "Physically Based Shading in Theory and Practice". Energy compensation for multiple scattering. Lesson 17 (exercise E8).
- Godot documentation, "Spatial shaders" (tutorials/shaders/shader_reference/spatial_shader), section on light built-ins: `LIGHT`, `LIGHT_COLOR`, `ATTENUATION`, `LIGHT_IS_DIRECTIONAL`, `SPECULAR_AMOUNT`, `DIFFUSE_LIGHT`, `SPECULAR_LIGHT`; render modes `diffuse_lambert`, `diffuse_burley`, `diffuse_lambert_wrap`. Lesson 17 measures the conventions (section 3.2). Class reference `ShaderInclude`. Lesson 17.
- DDG text (`discreteDifferentialGeometry.pdf`), §3.1, p. 30 (the Gauss map N : M → S²: the facet normals as points on the sphere, where D is a density) and §5.1, p. 87 (the vector area ∫ N dA depends only on the boundary: the projected microfacet area equals the macro area). Lesson 17 (P4).

## Animation, balance, physics

- David Rosen, "An Indie Approach to Procedural Animation", GDC 2014. Lessons 11–14.
- Andreas Aristidou, Joan Lasenby, "FABRIK: A fast, iterative solver for the Inverse Kinematics problem", *Graphical Models* 73(5), 2011. Lesson 15 (`Fabrik`: backward and forward passes, reachability, warm start).
- L. M. Bregman, "The method of successive projection for finding a common point of convex sets", *Soviet Mathematics Doklady* 6, 1965. Convergence of cyclic projections onto convex sets. Lesson 15 (`ReachSolver`).
- Stephen Boyd, Jon Dattorro, "Alternating Projections", lecture notes, EE392o, Stanford University, 2003. Alternating projections between convex sets and their convergence. Lesson 15 (`ReachSolver`, Predict P6).
- Richard L. Dykstra, "An algorithm for restricted least squares regression", *Journal of the American Statistical Association* 78(384), 1983; James P. Boyle, Richard L. Dykstra, "A method for finding projections onto the intersection of convex sets in Hilbert spaces", *Advances in Order Restricted Statistical Inference*, Lecture Notes in Statistics 37, Springer, 1986. Cyclic projections with a correction term that converge to the point of the intersection nearest the start (Dykstra's algorithm). Lesson 15 (Predict P6).
- David A. Winter, *Biomechanics and Motor Control of Human Movement*, 4th ed., Wiley, 2009. Chapter 4, Table 4.1: segment mass fractions and center-of-mass ratios (`data/body/winter_segment_masses.tres`); center of mass, base of support. Lesson 13.
- A. M. Andrew, "Another efficient algorithm for convex hulls in two dimensions", *Information Processing Letters* 9(5), 1979: the monotone chain (`SupportPolygon.convex_hull()`). Lesson 13.
- Mark de Berg, Otfried Cheong, Marc van Kreveld, Mark Overmars, *Computational Geometry: Algorithms and Applications*, 3rd ed., Springer, 2008. Chapter 1: convex hulls, the left-turn test, degenerate cases. Lesson 13.
- Jerry Pratt, John Carff, Sergey Drakunov, Ambarish Goswami, "Capture Point: A Step toward Humanoid Push Recovery", IEEE-RAS Humanoids 2006. Lesson 13 exercise E5; Lesson 14 exercise E7.
- DDG text (`discreteDifferentialGeometry.pdf`), section 5.1 "Vector Area", pp. 85–87: signed polygon area ½ Σ pᵢ × pᵢ₊₁, positive for counterclockwise vertices (Exercise 5.1). Lesson 13 (`SupportPolygon.area()`).
- R. B. McGhee, A. A. Frank, "On the stability properties of quadruped creeping gaits", *Mathematical Biosciences* 3, 1968, 331–351. Creeping gaits (one leg lifted at a time) and their static stability margin, the distance from the ground point of the center of mass to the edge of the support polygon. Lesson 16 (the lift test, the gait schedule).
- Milton Hildebrand, "Symmetrical gaits of horses", *Science* 150(3697), 1965, 701–708; "The quadrupedal gaits of vertebrates", *BioScience* 39(11), 1989, 766–775. Footfall sequences (lateral and diagonal), duty factor. Lesson 16 (`CrawlController.SWING_START`, exercise E5).
- Godot documentation, class references `PhysicsDirectSpaceState3D` (`intersect_shape()`, `cast_motion()`), `PhysicsShapeQueryParameters3D`, `CapsuleShape3D`, `CharacterBody3D` (`floor_max_angle`). Lesson 16 (`CrawlingPlayer.fits()`, `headroom()`, the scramble's walking limit).
- DDG text (`discreteDifferentialGeometry.pdf`), §5.1 "Vector Area", pp. 85–87 (the area of the four-contact polygon), §4.6.1, p. 68 (up the slab is along the gradient). Lesson 16 (Predict P3, P7).
- Erin Catto, publications on game physics: https://box2d.org/publications/ — constraints, solvers.

## Audio

- Andy Farnell, *Designing Sound*, MIT Press, 2010. Procedural models of footsteps, wind, water, and fire, written in Pure Data; the models translate to SuperCollider. Lessons 05–06, 27.
- Perry Cook, *Real Sound Synthesis for Interactive Applications*, A K Peters, 2002. Modal and physical models. Lesson 05.
- Kees van den Doel, Paul Kry, Dinesh Pai, "FoleyAutomatic: Physically-based Sound Effects for Interactive Simulation and Animation", SIGGRAPH 2001. Contact sound from modal synthesis. Lesson 05.
- Open Sound Control 1.0 specification: https://opensoundcontrol.stanford.edu/spec-1_0.html. Message layout, type tags, padding, address patterns. Lesson 04.
- Godot documentation, class reference `PacketPeerUDP`, `StreamPeerBuffer`; manual page "Singletons (Autoload)". Lesson 04.
- SuperCollider help: "OSC Communication", `OSCdef`, `OSCFunc`, `NetAddr`. Lesson 04.
- J. Postel, RFC 768, *User Datagram Protocol*, 1980. Lesson 04.
- IEEE 754-2019, *Standard for Floating-Point Arithmetic*. The binary32 format. Lesson 04.
- OSC 1.0 specification, sections "OSC Bundles" and "Temporal Semantics and OSC Time Tags". Lesson 05.
- D. Mills et al., RFC 5905, *Network Time Protocol Version 4*, 2010. Section 6: the 64-bit timestamp format (seconds since 1900, 32-bit fraction). Lesson 05.
- A. Farnell, *Designing Sound*, MIT Press, 2010. Chapter "Footsteps" (practical series "Human"): heel and ball phases, surface textures as granular processes. Lesson 05.
- K. van den Doel, P. G. Kry, D. K. Pai, "FoleyAutomatic: Physically-based Sound Effects for Interactive Simulation and Animation", *SIGGRAPH 2001*. Modal synthesis of impacts; contact sounds driven by simulation. Lesson 05.
- P. R. Cook, *Real Sound Synthesis for Interactive Applications*, A K Peters, 2002. Modal synthesis; PhISEM particle models for gravel and shakers. Lesson 05 (exercise E5).
- ITU-R Recommendation BT.1359-1, *Relative timing of sound and vision for broadcasting*, 1998. Detectability thresholds of audio–video offset (sound early about 45 ms, sound late about 125 ms). Lesson 05.
- SuperCollider help: `Server` (`makeBundle`, `latency`), `Score` (`recordNRT`), `Klank`, `Dust2`. Lesson 05.
- Ambisonic Toolkit for SuperCollider: https://www.ambisonictoolkit.net. Binaural and higher-order decoders; its UGens are installed with sc3-plugins, its class library (the `atk-sc3` quark) is not, and Lesson 06 does not use it (decision 0007, exercise E4). Lesson 06.
- V. Pulkki, "Virtual Sound Source Positioning Using Vector Base Amplitude Panning", *Journal of the Audio Engineering Society* 45(6), 1997. Pairwise and triplet amplitude panning; the constant-power condition. Lesson 06.
- D. G. Malham, A. Myatt, "3-D Sound Spatialization using Ambisonic Techniques", *Computer Music Journal* 19(4), 1995. First-order B-format (W, X, Y, Z), encoding and decoding. Lesson 06.
- ISO 9613-1:1993, *Acoustics — Attenuation of sound during propagation outdoors — Part 1: Calculation of the absorption of sound by the atmosphere*. Absorption coefficients by frequency, temperature, humidity. Lesson 06 (exercise E6).
- A. Farnell, *Designing Sound*, MIT Press, 2010. Practical "Wind": noise sources, gusts, whistling edges. Lesson 06.
- R. S. Woodworth, *Experimental Psychology*, Holt, 1938. The interaural time difference of a spherical head, (a/c)(θ + sin θ). Lesson 06 (exercise E4).
- SuperCollider help: `PanAz`, `PanB`, `DecodeB2`, `Lag`. Lesson 06.

## Character movement and input

- Godot documentation, class reference `CharacterBody3D` (`floor_max_angle`, `floor_snap_length`, `floor_constant_speed`, `floor_block_on_wall`, `move_and_slide()`), and the tutorial "Using CharacterBody2D/3D". Lesson 02.
- Glenn Fiedler, "Fix Your Timestep!", Gaffer On Games, 2004: https://gafferongames.com/post/fix_your_timestep/ — fixed physics ticks and their relation to rendering frames. Lesson 02.
- Josh Sutphin, "Doing Thumbstick Dead Zones Right", Third Helix (blog), 2013 — axial versus radial deadzones, rescaling after the deadzone. Lessons 02, 14.

## Software architecture

- Robert Nystrom, *Game Programming Patterns*: https://gameprogrammingpatterns.com — game loop, update method, event queue, component. Lessons 02, 05, 30.

## Rotations, skeletons and kinematics

- Ken Shoemake, "Animating rotation with quaternion curves", SIGGRAPH 1985. Unit quaternions as rotations, the product as composition, slerp. Lesson 11.
- John J. Craig, *Introduction to Robotics: Mechanics and Control*, 3rd ed., Pearson, 2005. Chapter 2 (spatial descriptions: rotation matrices, homogeneous transforms, composition and inversion) and chapter 3 (forward kinematics of a chain). Lesson 11; chapter 4 (inverse kinematics) for Lesson 12.
- Godot documentation: "Using 3D transforms" (tutorials/3d/using_transforms), class references `Skeleton3D` (bone rest, bone pose, `get_bone_global_pose`), `BoneAttachment3D`, `Quaternion`. Lesson 11.
- The DDG text (`discreteDifferentialGeometry.pdf`) does not treat rotation groups or quaternions; Lesson 11 cites no section of it.
- Samuel R. Buss, "Introduction to Inverse Kinematics with Jacobian Transpose, Pseudoinverse and Damped Least Squares methods", University of California, San Diego, 2004 (revised 2009). Section 1 (the IK problem, reachability); the iterative methods are the background of the engine's `JacobianIK3D`. Lesson 12.
- Godot documentation, class references `TwoBoneIK3D`, `IKModifier3D`, `SkeletonModifier3D` (modifier order, `skeleton_updated`), `PhysicsDirectSpaceState3D.intersect_ray()`, `PhysicsRayQueryParameters3D`. Lesson 12.
- The DDG text does not treat inverse kinematics; Lesson 12 cites no section of it.

## Input shaping and filters

- Josh Sutphin, "Doing Thumbstick Dead Zones Right" (radial, axial and hybrid deadzones). Lessons 02 and 14.
- Godot documentation, "Controllers, gamepads, and joysticks" (tutorials/inputs/controllers_gamepads_joysticks): action deadzones, `Input.get_action_raw_strength()`, trigger axes; class reference `Curve`. Lesson 14.
- Julius O. Smith III, *Introduction to Digital Filters with Audio Applications*, W3K Publishing, 2007, chapter "Elementary Filter Sections": the one-pole filter. Lesson 14 (`OnePoleFilter`).
- DDG text (`discreteDifferentialGeometry.pdf`), section 6.6 "Implicit Mean Curvature Flow", pp. 114–116: forward Euler (stable only for small steps) against backward Euler. Lesson 14 (Predict P6, `CriticalSpring.step_euler()`).
