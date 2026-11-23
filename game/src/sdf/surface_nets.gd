class_name SurfaceNets
extends RefCounted
## Turns an SdfGrid into a triangle mesh by naive surface nets (Lesson 08).
##
## The algorithm has two passes.
##   1. Vertices. Each cell whose eight corners do not all have the same
##      sign contains a piece of the surface f = 0. Such a cell gets one
##      vertex: the average of the points where f crosses zero along the
##      cell's twelve edges (linear interpolation on each edge).
##   2. Faces. Each grid edge whose two ends have different signs is
##      pierced by the surface. The four cells around that edge all have
##      vertices (each contains the edge's sign change), and their four
##      vertices form one quad, split into two triangles.
##
## Pass 1 is one independent job per cell, so it suits the GPU
## (surface_nets_gpu.gd, shaders/compute/surface_nets.glsl). Both paths
## write the same "cell table", CELL_FLOATS floats per cell:
##   [x, y, z, has_vertex, nx, ny, nz, 0]
## Pass 2 reads only the table and the signs; it runs on the CPU for both.
##
## Corner numbering inside a cell: bit 0 is +x, bit 1 is +y, bit 2 is +z.
## Corner 0 is grid point (i, j, k); corner 7 is (i + 1, j + 1, k + 1).

const CELL_FLOATS := 8
## The twelve cell edges as pairs of corner numbers. Each pair differs
## in exactly one bit: four edges along x, four along y, four along z.
const EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
	Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]

## Mesh data after build(): one vertex per surface cell.
var positions := PackedVector3Array()
var normals := PackedVector3Array()
var indices := PackedInt32Array()
## For each cell, the index of its vertex in `positions`, or -1.
var cell_vertex := PackedInt32Array()
var vertex_milliseconds := 0.0
var face_milliseconds := 0.0


## Where along an edge does f cross zero?
##
## Q: Why f0 / (f0 - f1)?
## A: Model f on the edge as the straight line f(t) = f0 + t (f1 - f0),
##    t in [0, 1]. Setting f(t) = 0 gives t = f0 / (f0 - f1). The signs
##    differ, so f0 - f1 is never zero and t lies in [0, 1].
static func edge_crossing(f0: float, f1: float) -> float:
	return f0 / (f0 - f1)


static func is_inside(f: float) -> bool:
	return f < 0.0


## Pass 1 on the CPU: the cell table for every cell of the grid.
static func cell_table(grid: SdfGrid) -> PackedFloat32Array:
	var cells := grid.dims - Vector3i.ONE
	var table := PackedFloat32Array()
	table.resize(grid.cell_count() * CELL_FLOATS)
	var corner := PackedFloat64Array()
	corner.resize(8)
	var c := 0
	for k in cells.z:
		for j in cells.y:
			for i in cells.x:
				var inside_count := 0
				for n in 8:
					corner[n] = grid.value(i + (n & 1), j + ((n >> 1) & 1), k + ((n >> 2) & 1))
					if is_inside(corner[n]):
						inside_count += 1
				# Q: When does the cell hold no surface?
				# A: When all eight corners are inside or all are outside.
				#    (A surface could still pass between the corners and
				#    out again; the grid cannot see it. See P6.)
				if inside_count != 0 and inside_count != 8:
					_write_cell(table, c * CELL_FLOATS, corner, grid.point(i, j, k), grid.cell_size)
				c += 1
	return table


## Fills one row of the cell table from the eight corner values.
static func _write_cell(table: PackedFloat32Array, at: int, corner: PackedFloat64Array,
		cell_origin: Vector3, cell: float) -> void:
	# Average of the crossing points, in cell units (each coordinate 0..1).
	var sum_x := 0.0
	var sum_y := 0.0
	var sum_z := 0.0
	var crossings := 0
	for edge in EDGES:
		var f0 := corner[edge.x]
		var f1 := corner[edge.y]
		if is_inside(f0) == is_inside(f1):
			continue
		var t := edge_crossing(f0, f1)
		# Q: How does a crossing become a point in the cell?
		# A: The edge runs from corner a to corner b. Their bits give
		#    their positions (0 or 1 on each axis), and the point is
		#    a + t (b - a), one coordinate at a time.
		var a := edge.x
		var b := edge.y
		sum_x += (a & 1) + t * ((b & 1) - (a & 1))
		sum_y += ((a >> 1) & 1) + t * (((b >> 1) & 1) - ((a >> 1) & 1))
		sum_z += ((a >> 2) & 1) + t * (((b >> 2) & 1) - ((a >> 2) & 1))
		crossings += 1
	var u := sum_x / crossings
	var v := sum_y / crossings
	var w := sum_z / crossings
	var n := trilinear_gradient(corner, u, v, w).normalized()
	if n == Vector3.ZERO:
		n = Vector3.UP
	table[at] = cell_origin.x + u * cell
	table[at + 1] = cell_origin.y + v * cell
	table[at + 2] = cell_origin.z + w * cell
	table[at + 3] = 1.0
	table[at + 4] = n.x
	table[at + 5] = n.y
	table[at + 6] = n.z


## Gradient, in "per cell" units, of the trilinear interpolation of the
## eight corner values, at the point (u, v, w) of the unit cell.
##
## Q: Why this gradient and not shape.gradient()?
## A: shape.gradient() costs six more evaluations per vertex. The grid
##    already holds f at the corners; the trilinear function through them
##    is the smoothest guess the grid can make, and its derivative has a
##    closed form. Along x, the four x-edges each have a slope
##    (f_b - f_a), and the derivative at (u, v, w) blends those four
##    slopes with the weights of v and w. The same holds for y and z.
static func trilinear_gradient(f: PackedFloat64Array, u: float, v: float, w: float) -> Vector3:
	var dx := (1 - v) * (1 - w) * (f[1] - f[0]) + v * (1 - w) * (f[3] - f[2]) \
		+ (1 - v) * w * (f[5] - f[4]) + v * w * (f[7] - f[6])
	var dy := (1 - u) * (1 - w) * (f[2] - f[0]) + u * (1 - w) * (f[3] - f[1]) \
		+ (1 - u) * w * (f[6] - f[4]) + u * w * (f[7] - f[5])
	var dz := (1 - u) * (1 - v) * (f[4] - f[0]) + u * (1 - v) * (f[5] - f[1]) \
		+ (1 - u) * v * (f[6] - f[2]) + u * v * (f[7] - f[3])
	return Vector3(dx, dy, dz)


## Both passes. `table` may come from the GPU; an empty table means
## "compute it here".
func build(grid: SdfGrid, table: PackedFloat32Array = PackedFloat32Array()) -> void:
	var started := Time.get_ticks_usec()
	if table.is_empty():
		table = cell_table(grid)
	vertex_milliseconds = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	_read_table(grid, table)
	_connect_faces(grid)
	face_milliseconds = (Time.get_ticks_usec() - started) / 1000.0


## Gives every cell that has a vertex its index in `positions`.
func _read_table(grid: SdfGrid, table: PackedFloat32Array) -> void:
	var count := grid.cell_count()
	cell_vertex.resize(count)
	positions.clear()
	normals.clear()
	for c in count:
		var at := c * CELL_FLOATS
		if table[at + 3] > 0.5:
			cell_vertex[c] = positions.size()
			positions.append(Vector3(table[at], table[at + 1], table[at + 2]))
			normals.append(Vector3(table[at + 4], table[at + 5], table[at + 6]))
		else:
			cell_vertex[c] = -1


## Pass 2: one quad for each grid edge with a sign change.
func _connect_faces(grid: SdfGrid) -> void:
	indices.clear()
	var d := grid.dims
	var cells := d - Vector3i.ONE
	# Q: Which two axes span the quad around an edge along axis a?
	# A: The other two, taken in cyclic order (a, b, c) = (x, y, z),
	#    (y, z, x) or (z, x, y). Cyclic order makes e_b x e_c = e_a,
	#    which the winding rule below relies on.
	var unit: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	for k in d.z:
		for j in d.y:
			for i in d.x:
				var p := Vector3i(i, j, k)
				var f0 := grid.value(i, j, k)
				for a in 3:
					var b := (a + 1) % 3
					var c := (a + 2) % 3
					var q := p + unit[a]
					# Does the edge end inside the grid, and do the four
					# cells around it exist?
					if q[a] >= d[a] or p[b] < 1 or p[c] < 1 or p[b] >= cells[b] or p[c] >= cells[c]:
						continue
					var f1 := grid.value(q.x, q.y, q.z)
					if is_inside(f0) == is_inside(f1):
						continue
					var v0 := cell_vertex[_cell_index(p - unit[b] - unit[c], cells)]
					var v1 := cell_vertex[_cell_index(p - unit[c], cells)]
					var v2 := cell_vertex[_cell_index(p, cells)]
					var v3 := cell_vertex[_cell_index(p - unit[b], cells)]
					# Q: Which way round must the quad go?
					# A: v0 -> v1 steps along +b and v1 -> v2 along +c, so
					#    seen from +a the quad runs counterclockwise.
					#    Godot shows faces that run clockwise as seen by the
					#    camera. If p is inside, the outside lies toward +a
					#    and the viewer sees it from +a: reverse the order.
					#    If q is inside, the viewer looks from -a, where the
					#    same order already appears clockwise.
					if is_inside(f0):
						indices.append_array([v0, v2, v1, v0, v3, v2])
					else:
						indices.append_array([v0, v1, v2, v0, v2, v3])


static func _cell_index(c: Vector3i, cells: Vector3i) -> int:
	return c.x + cells.x * (c.y + cells.y * c.z)


func triangle_count() -> int:
	return indices.size() / 3


## Arrays for ArrayMesh.add_surface_from_arrays().
func mesh_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
