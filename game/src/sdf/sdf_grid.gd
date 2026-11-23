class_name SdfGrid
extends RefCounted
## Samples of an SdfShape on a regular 3D grid (Lesson 08).
##
## How the files relate:
##   SdfShape (src/sdf/sdf_shape.gd)   the function f being sampled
##   SdfGrid (this file)               f at every grid point, nothing more
##   SurfaceNets (surface_nets.gd)     reads the grid on the CPU
##   SurfaceNetsGpu (surface_nets_gpu.gd)
##                                     uploads `values` to the GPU and runs
##                                     shaders/compute/surface_nets.glsl
##   SdfMesher (sdf_mesher.gd)         the node that drives all of the above
##
## Layout. Grid point (i, j, k) sits at origin + cell_size * (i, j, k).
## Its value is values[index(i, j, k)], with x varying fastest:
##   index = i + dims.x * (j + dims.y * k)
## The same formula appears in the compute shader. A cell is the cube
## between grid points (i, j, k) and (i + 1, j + 1, k + 1), so there are
## dims - (1, 1, 1) cells along each axis.
##
## Values are 32-bit floats (PackedFloat32Array) because that is what the
## GPU reads; the CPU path reads the same numbers, so the two paths start
## from identical input.

var origin := Vector3.ZERO
var cell_size := 1.0
var dims := Vector3i.ZERO
var values := PackedFloat32Array()
## Wall-clock time of the last sample() call.
var sample_milliseconds := 0.0


## Samples `shape` on a grid that covers shape.bounds() with one spare
## layer of cells on every side.
##
## Q: Why the spare layer?
## A: bounds() promises f > 0 outside the box, so a grid that ends on the
##    box already has no inside point on its border, and the mesh closes
##    (P7). The layer costs about 14 % more samples for this pile and
##    guards against a bounds() that is slightly too small: a solid point
##    beyond the last grid point would leave the mesh open there (T3).
static func sample(shape: SdfShape, cell: float) -> SdfGrid:
	var grid := SdfGrid.new()
	var box := shape.bounds()
	grid.cell_size = cell
	grid.origin = box.position - Vector3.ONE * cell
	grid.dims = Vector3i(
		ceili(box.size.x / cell) + 3,
		ceili(box.size.y / cell) + 3,
		ceili(box.size.z / cell) + 3)
	grid.fill(shape)
	return grid


## Evaluates `shape` at every grid point.
func fill(shape: SdfShape) -> void:
	var started := Time.get_ticks_usec()
	values.resize(dims.x * dims.y * dims.z)
	var n := 0
	for k in dims.z:
		for j in dims.y:
			for i in dims.x:
				values[n] = shape.evaluate(point(i, j, k))
				n += 1
	# EXERCISE (lesson 08): E3. Skip the far-away points. A value f(p) and
	# the Lipschitz bound L promise that no surface lies within f(p) / L
	# of p; use that to fill whole blocks with a positive placeholder
	# without calling evaluate().
	sample_milliseconds = (Time.get_ticks_usec() - started) / 1000.0


func index(i: int, j: int, k: int) -> int:
	return i + dims.x * (j + dims.y * k)


func point(i: int, j: int, k: int) -> Vector3:
	return origin + Vector3(i, j, k) * cell_size


func value(i: int, j: int, k: int) -> float:
	return values[index(i, j, k)]


func cell_count() -> int:
	return (dims.x - 1) * (dims.y - 1) * (dims.z - 1)
