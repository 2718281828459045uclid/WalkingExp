@tool
class_name ShadingGallery
extends Node3D
## A row of five identical samples, one per shading mode: built-in,
## Lambert, wrap, Oren-Nayar, GGX (Lesson 17). Each sample is a rippled
## ground tile with a rock on it, under the scene's sun.
##
## How this file relates to the others:
##   LitShader (src/render/lit_shader.gd)    makes one lit material per
##                                            column from the originals
##   ShadingSwitch.Mode / MODE_NAMES         the column order and labels
##   Terrain, HeightField (Lesson 01)        each tile is a small Terrain
##                                            built from tile_field
##   CurvatureMesher (Lesson 09)             meshes rock_shape once, with
##                                            its curvature channel, so the
##                                            weathering colors appear; the
##                                            other columns reuse its mesh
##   src/lessons/writing_light.gd            sets light_term through
##                                            set_term() (F6)
##
## Q: Why a gallery when F5 already switches the whole scene?
## A: Two images seen one after the other are compared from memory; two
##    images side by side are compared by the eye at once. Each column
##    has the same geometry, the same material values and the same light;
##    only light() differs.
##
## Generated nodes are internal children (Lesson 01 rule), rebuilt when
## the scene loads; nothing of them is saved in the .tscn file.

## The light() to append (shaders/lighting/custom_light.gdshaderinc).
@export var light_include: ShaderInclude:
	set(value):
		light_include = value
		_queue_rebuild()
## The rock of every column (data/rocks/gallery_rock.tres).
@export var rock_shape: SdfShape:
	set(value):
		rock_shape = value
		_queue_rebuild()
## The rocks' original material (Lesson 09 weathering).
@export var rock_material: ShaderMaterial:
	set(value):
		rock_material = value
		_queue_rebuild()
@export_range(0.03, 0.3, 0.01) var rock_cell_size: float = 0.06:
	set(value):
		rock_cell_size = value
		_queue_rebuild()
## Height function of every tile, in tile-local coordinates.
@export var tile_field: HeightField:
	set(value):
		tile_field = value
		_queue_rebuild()
## The tiles' original material (Lesson 03 painted ground).
@export var tile_material: ShaderMaterial:
	set(value):
		tile_material = value
		_queue_rebuild()
@export_range(0.5, 8.0, 0.1) var tile_size: float = 2.4:
	set(value):
		tile_size = value
		_queue_rebuild()
@export_range(3, 129) var tile_vertices: int = 49:
	set(value):
		tile_vertices = value
		_queue_rebuild()
## Distance between column centers along the gallery's local x axis.
@export_range(0.5, 10.0, 0.1) var spacing: float = 2.7:
	set(value):
		spacing = value
		_queue_rebuild()
## How far the box (plinth) under each tile reaches below the lowest
## terrain point under the tile, in meters (without a terrain: the box's
## whole depth).
@export_range(0.1, 4.0, 0.1) var plinth_depth: float = 0.3:
	set(value):
		plinth_depth = value
		_queue_rebuild()
## Optional: the terrain the row stands on (row_height()); without a
## terrain, local y = 0.
@export var ground: Terrain:
	set(value):
		ground = value
		_queue_rebuild()
## Height of the labels above the tile.
@export var label_height: float = 1.7:
	set(value):
		label_height = value
		_queue_rebuild()

## One entry per column, in ShadingSwitch.Mode order.
var columns: Array[Column] = []
var rock_mesh: Mesh
var build_milliseconds := 0.0

var _rebuild_queued := false
var _generated: Array[Node] = []
var _rock_collision: Shape3D


class Column:
	var mode: int
	var root: Node3D
	var tile: Terrain
	var plinth: MeshInstance3D
	var rock: MeshInstance3D
	var label: Label3D
	var tile_material: ShaderMaterial
	var rock_material: ShaderMaterial


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_node_ready():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	for node in _generated:
		node.queue_free()
	_generated.clear()
	columns.clear()
	rock_mesh = null
	_rock_collision = null
	if rock_shape == null or rock_material == null or tile_field == null or tile_material == null or light_include == null:
		return
	var started := Time.get_ticks_usec()

	# The rock is meshed once, by a CurvatureMesher in the first column.
	var mesher := CurvatureMesher.new()
	mesher.shape = rock_shape
	mesher.cell_size = rock_cell_size
	mesher.material = rock_material
	mesher.build_collision = false

	for i in ShadingSwitch.Mode.size():
		var column := Column.new()
		column.mode = i
		column.root = Node3D.new()
		column.root.position = column_position(i)
		_add_internal(self, column.root)

		# Q: Which materials does a column use?
		# A: Column 0 (built-in) uses the originals. Columns 1-4 use lit
		#    copies, one per column, so each can hold its own light_model.
		column.tile_material = tile_material
		column.rock_material = rock_material
		if i != ShadingSwitch.Mode.BUILT_IN:
			column.tile_material = LitShader.material(tile_material, light_include)
			column.rock_material = LitShader.material(rock_material, light_include)
			for lit in [column.tile_material, column.rock_material]:
				if lit != null:
					lit.set_shader_parameter("light_model", i - 1)

		column.tile = Terrain.new()
		column.tile.size_meters = tile_size
		column.tile.vertices_per_side = tile_vertices
		column.tile.field = tile_field
		column.tile.material = column.tile_material
		_add_internal(column.root, column.tile)

		# Q: Why a box under the tile?
		# A: The tile is a single rippled sheet. Lifted above the sloping
		#    terrain it would show its edge and the gap below it; the box
		#    closes the gap. Its flat sides, in the column's material, are
		#    three more surfaces at three fixed angles to the sun.
		var depth := plinth_height(i)
		var box := BoxMesh.new()
		box.size = Vector3(tile_size, depth, tile_size)
		column.plinth = MeshInstance3D.new()
		column.plinth.mesh = box
		column.plinth.material_override = column.tile_material
		column.plinth.position.y = -tile_field.ripple_amplitude - 0.5 * depth
		_add_internal(column.root, column.plinth)
		if not Engine.is_editor_hint():
			var plinth_body := StaticBody3D.new()
			var plinth_shape := CollisionShape3D.new()
			plinth_shape.shape = BoxShape3D.new()
			(plinth_shape.shape as BoxShape3D).size = box.size
			plinth_body.add_child(plinth_shape)
			plinth_body.position = column.plinth.position
			_add_internal(column.root, plinth_body)

		# The rock stands on the tile's center, 0.05 m into it.
		var rock_y := tile_field.height(Vector2.ZERO) - 0.05
		if i == 0:
			mesher.position.y = rock_y
			_add_internal(column.root, mesher)
			rock_mesh = _mesh_of(mesher)
		else:
			column.rock = MeshInstance3D.new()
			column.rock.mesh = rock_mesh
			column.rock.material_override = column.rock_material
			column.rock.position.y = rock_y
			_add_internal(column.root, column.rock)
		_add_rock_collision(column.root, rock_y)

		column.label = Label3D.new()
		column.label.text = ShadingSwitch.MODE_NAMES[i]
		column.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		column.label.font_size = 64
		column.label.outline_size = 12
		column.label.pixel_size = 0.007
		column.label.position = Vector3(0.0, label_height, 0.0)
		_add_internal(column.root, column.label)
		columns.append(column)
	build_milliseconds = (Time.get_ticks_usec() - started) / 1000.0


## Local position of column i: centered on the node, along local x, all
## at one height (row_height()).
func column_position(i: int) -> Vector3:
	var x := (i - 0.5 * (ShadingSwitch.Mode.size() - 1)) * spacing
	return Vector3(x, row_height(), 0.0)


## Q: How high does the row stand on a ground terrain?
## A: At the highest terrain point under any of its tiles (a 5 x 5 grid
##    of samples per tile) plus the ripple amplitude, so that no part of
##    the terrain comes up through a tile. The plinths reach down from
##    there into the ground (plinth_height()) and hide the gap on the
##    lower side (CrawlGap, Lesson 16, places its floor the same way).
##
## Q: Why one height for all five columns?
## A: The ground material colors by world height (Lesson 03: dirt below
##    dirt_height) and draws contour lines at whole meters. Columns at
##    different heights would differ in color for a reason that has
##    nothing to do with light().
func row_height() -> float:
	if ground == null or ground.field == null or not is_inside_tree():
		return 0.0
	var highest := -INF
	for i in ShadingSwitch.Mode.size():
		var x := (i - 0.5 * (ShadingSwitch.Mode.size() - 1)) * spacing
		for a in 5:
			for b in 5:
				var corner := Vector3(x + (a / 4.0 - 0.5) * tile_size, 0.0, (b / 4.0 - 0.5) * tile_size)
				var world := global_transform * corner
				highest = maxf(highest, ground.height_at(world.x, world.z))
	return highest - global_position.y + tile_field.ripple_amplitude


## Height of column i's plinth: from the tile's lowest point down to
## plinth_depth below the lowest terrain point under the tile.
func plinth_height(i: int) -> float:
	if ground == null or ground.field == null or not is_inside_tree():
		return plinth_depth
	var top := global_position.y + row_height() - tile_field.ripple_amplitude
	var x := (i - 0.5 * (ShadingSwitch.Mode.size() - 1)) * spacing
	var lowest := INF
	for a in 5:
		for b in 5:
			var corner := Vector3(x + (a / 4.0 - 0.5) * tile_size, 0.0, (b / 4.0 - 0.5) * tile_size)
			var world := global_transform * corner
			lowest = minf(lowest, ground.height_at(world.x, world.z))
	return top - lowest + plinth_depth


## Shows diffuse and specular, diffuse only, or specular only on the lit
## columns (ShadingSwitch.Term values).
func set_term(term: int) -> void:
	for column in columns:
		if column.mode == ShadingSwitch.Mode.BUILT_IN:
			continue
		for lit in [column.tile_material, column.rock_material]:
			if lit != null:
				lit.set_shader_parameter("light_term", term)


## The mesh the CurvatureMesher built: its internal MeshInstance3D child.
func _mesh_of(mesher: Node) -> Mesh:
	for child in mesher.get_children(true):
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


## Q: Why add collision here instead of in the CurvatureMesher?
## A: Only the first column has a mesher. One trimesh shape, built once
##    from the shared mesh, serves all five columns. As in Lesson 08, the
##    editor gets no collision.
func _add_rock_collision(column_root: Node3D, rock_y: float) -> void:
	if Engine.is_editor_hint() or rock_mesh == null:
		return
	if _rock_collision == null:
		_rock_collision = rock_mesh.create_trimesh_shape()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = _rock_collision
	body.add_child(shape)
	body.position.y = rock_y
	_add_internal(column_root, body)


func _add_internal(parent: Node, node: Node) -> void:
	parent.add_child(node, false, Node.INTERNAL_MODE_FRONT)
	if parent == self:
		_generated.append(node)
