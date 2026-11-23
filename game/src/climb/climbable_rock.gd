@tool
class_name ClimbableRock
extends CurvatureMesher
## A CurvatureMesher (Lessons 08-09) whose surface carries holds
## (Lesson 15).
##
## How the files relate:
##   SdfMesher, CurvatureMesher   mesh, collision, per-vertex n and H
##                                (unchanged)
##   HoldFinder                   vertices -> holds
##   SphereTracer (Lesson 10)     looks over the top edge for top_out
##   Terrain (Lesson 01)          optional `ground`: holds below it, or
##                                less than ground_clearance above it,
##                                are left out of `holds`
##   this file                    runs HoldFinder after every rebuild and
##                                after a change of a threshold (no
##                                re-meshing), marks the holds below the
##                                top edge (top_out), draws the holds
##   ClimbController              reads holds and face_normal_world()
##
## The node may be moved and turned about +y. Its scale must be 1 and it
## must not tilt: the hold tests compare normals with +y in shape space.

@export_group("Holds")
## The outward normal of the climbing face, in shape space.
@export var face_normal := Vector3(0, 0, 1):
	set(value):
		face_normal = value
		_queue_hold_search()
## Smallest mean curvature of a hold, 1/m.
@export var min_mean_curvature: float = 3.0:
	set(value):
		min_mean_curvature = value
		_queue_hold_search()
## Largest mean curvature of a hold, 1/m. Larger values are creases.
@export var max_mean_curvature: float = 40.0:
	set(value):
		max_mean_curvature = value
		_queue_hold_search()
## Smallest |grad f| at a hold. A distance field has 1.
@export_range(0.0, 1.0, 0.05) var min_gradient: float = 0.5:
	set(value):
		min_gradient = value
		_queue_hold_search()
## Smallest upward component of a hold's normal.
@export_range(-1.0, 1.0, 0.05) var min_up: float = 0.3:
	set(value):
		min_up = value
		_queue_hold_search()
## Smallest component of a hold's normal along face_normal.
@export_range(-1.0, 1.0, 0.05) var min_facing: float = 0.2:
	set(value):
		min_facing = value
		_queue_hold_search()
## Smallest distance between two holds, meters.
@export var hold_spacing: float = 0.2:
	set(value):
		hold_spacing = value
		_queue_hold_search()
## k2 / k1 at or above this ratio makes a knob, below it an edge.
@export_range(0.0, 1.0, 0.05) var knob_ratio: float = 0.25:
	set(value):
		knob_ratio = value
		_queue_hold_search()
## Draws a cross at every hold: orange knobs, yellow edges, cyan top-outs.
@export var show_holds := true:
	set(value):
		show_holds = value
		if _hold_instance != null:
			_hold_instance.visible = value
## The terrain the rock stands in. Holds below its surface, or less than
## ground_clearance above it, are left out of `holds` and not drawn.
## Optional; the scene assigns it.
@export var ground: Terrain:
	set(value):
		ground = value
		if is_node_ready():
			_update_world_holds()
			_draw_holds()
## Smallest height of a hold above the ground, meters. A foot on a lower
## hold stands on the ground anyway, and the marker (arms 0.05 m long)
## would sink into the terrain.
@export_range(0.0, 0.5, 0.01) var ground_clearance: float = 0.05:
	set(value):
		ground_clearance = value
		if is_node_ready():
			_update_world_holds()
			_draw_holds()

## Every hold of the last search, shape space, best score first. Holds
## below the ground are included.
var local_holds: Array[HoldFinder.Hold] = []
## The holds of local_holds that lie above the ground, world space, in
## the same order.
var holds: Array[HoldFinder.Hold] = []
## Holds of local_holds below the ground or within ground_clearance of
## it (not in holds).
var buried_count := 0
## Vertices that passed the vertex tests, before suppression.
var candidate_count := 0
## Suppressed candidates that failed after refinement.
var rejected_count := 0
## Time of the hold search, milliseconds.
var hold_milliseconds := 0.0

var _hold_instance: MeshInstance3D
var _hold_mesh: ImmediateMesh
var _search_queued := false
## The entries of local_holds above the ground, in the order of holds.
var _open_local_holds: Array[HoldFinder.Hold] = []


func rebuild() -> void:
	super()
	find_holds()


## Runs the hold search on the current mesh and curvature.
##
## Q: Why is this separate from rebuild()?
## A: Meshing and curvature take about 1.2 s for this rock; the search
##    takes about 12 ms. The thresholds above call only this function,
##    so they can be changed in the Inspector while the game runs.
func find_holds() -> void:
	_search_queued = false
	if nets == null or mean_curvatures.is_empty():
		return
	var started := Time.get_ticks_usec()
	var criteria := criteria()
	var found := HoldFinder.candidates(nets.positions, gradient_normals, mean_curvatures, criteria)
	candidate_count = found.size()
	var suppressed := HoldFinder.suppress(found, criteria.spacing)
	local_holds.clear()
	for hold in suppressed:
		if HoldFinder.refine(shape, hold, criteria):
			hold.top_out = _below_top(hold.position)
			local_holds.append(hold)
	rejected_count = suppressed.size() - local_holds.size()
	hold_milliseconds = (Time.get_ticks_usec() - started) / 1000.0
	_update_world_holds()
	_draw_holds()


func _queue_hold_search() -> void:
	if _search_queued or not is_node_ready():
		return
	_search_queued = true
	find_holds.call_deferred()


## The exported thresholds as a HoldFinder.Criteria (shape space).
func criteria() -> HoldFinder.Criteria:
	var c := HoldFinder.Criteria.new()
	c.min_mean = min_mean_curvature
	c.max_mean = max_mean_curvature
	c.min_gradient = min_gradient
	c.min_up = min_up
	c.face = face_normal.normalized()
	c.min_facing = min_facing
	c.spacing = hold_spacing
	c.knob_ratio = knob_ratio
	return c


## The face normal in world space.
func face_normal_world() -> Vector3:
	return (global_transform.basis * face_normal).normalized()


## Counts the holds of one kind among the holds above the ground.
func count_kind(kind: HoldFinder.Kind) -> int:
	var count := 0
	for hold in holds:
		if hold.kind == kind:
			count += 1
	return count


## Converts the shape-space holds to world space and leaves out the holds
## below the ground or within ground_clearance of it. Runs again whenever
## the node moves (the scene root moves it onto the terrain in _ready()).
##
## Q: How can a hold lie under the ground?
## A: The rock stands in a slope, and its shape continues below the foot
##    of the face. SdfRepeat puts count copies on each side of the grid's
##    center (Lesson 07); the knob grids of climbing_face.tres are
##    centered at mid-height, and their two lowest rows sit at and below
##    the foot of the face. The hold search works in shape space and
##    knows nothing of the terrain; the holds it finds there lie inside
##    the ground, where no hand or foot can take them, and their markers
##    would be hidden. Whether a hold is buried depends on where the rock
##    stands, so the test runs here, with the world positions.
func _update_world_holds() -> void:
	holds.clear()
	_open_local_holds.clear()
	for local in local_holds:
		var world := global_transform * local.position
		if ground != null and world.y < ground.height_at(world.x, world.z) + ground_clearance:
			continue
		var hold := HoldFinder.Hold.new()
		hold.position = world
		hold.normal = (global_transform.basis * local.normal).normalized()
		hold.mean = local.mean
		hold.gaussian = local.gaussian
		hold.k1 = local.k1
		hold.k2 = local.k2
		hold.gradient_length = local.gradient_length
		hold.score = local.score
		hold.kind = local.kind
		hold.top_out = local.top_out
		holds.append(hold)
		_open_local_holds.append(local)
	buried_count = local_holds.size() - holds.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not local_holds.is_empty():
		_update_world_holds()
		_draw_holds()


func _ready() -> void:
	set_notify_transform(true)
	_hold_mesh = ImmediateMesh.new()
	_hold_instance = MeshInstance3D.new()
	_hold_instance.name = "HoldMarks"
	_hold_instance.mesh = _hold_mesh
	_hold_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.vertex_color_use_as_albedo = true
	_hold_instance.material_override = lines
	add_child(_hold_instance, false, Node.INTERNAL_MODE_FRONT)
	_hold_instance.visible = show_holds
	super()


## Whether the flat top of the rock lies just above and behind a point.
##
## Q: How does the code know that a hold is on the top edge?
## A: It looks over the edge. From a point 0.6 m above the hold and 0.35 m
##    behind it (into the rock), a ray goes straight down (sphere tracing,
##    Lesson 10). On the top edge, the start lies in the air above the top
##    and the ray lands on a flat surface near the hold's height. On the
##    face, the start lies inside the rock (f < 0), and the hold is not a
##    top-out.
func _below_top(p: Vector3) -> bool:
	var start := p + Vector3.UP * 0.6 - face_normal.normalized() * 0.35
	if shape.evaluate(start) <= 0.0:
		return false
	var trace := SphereTracer.trace(shape, start, Vector3.DOWN, 64, 0.0, 0.0, 1.2, shape.lipschitz_bound(), 1e-4)
	if not trace.hit:
		return false
	var top := start + Vector3.DOWN * trace.t
	return absf(top.y - p.y) <= 0.25 and shape.gradient(top).normalized().y >= 0.8


func _draw_holds() -> void:
	if _hold_mesh == null:
		return
	_hold_mesh.clear_surfaces()
	if _open_local_holds.is_empty():
		return
	_hold_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for hold in _open_local_holds:
		var color := Color(1.0, 0.55, 0.1) if hold.kind == HoldFinder.Kind.KNOB else Color(1.0, 0.95, 0.2)
		if hold.top_out:
			color = Color(0.2, 0.9, 1.0)
		var p := hold.position + hold.normal * 0.01
		var s := 0.05
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			_hold_mesh.surface_set_color(color)
			_hold_mesh.surface_add_vertex(p - axis * s)
			_hold_mesh.surface_set_color(color)
			_hold_mesh.surface_add_vertex(p + axis * s)
		# The normal, 0.1 m long.
		_hold_mesh.surface_set_color(color)
		_hold_mesh.surface_add_vertex(p)
		_hold_mesh.surface_set_color(color)
		_hold_mesh.surface_add_vertex(p + hold.normal * 0.1)
	_hold_mesh.surface_end()
