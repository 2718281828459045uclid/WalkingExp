extends SceneTree
## Compares pass 1 of surface nets on the GPU and the CPU (Lesson 08)
## and prints the timings of every stage. Called by tools/mesher_compare.sh.
##
## Needs a window: headless runs have no RenderingDevice.
##
## Arguments after "--":  <res:// shape .tres> <cell size> [cell size ...]
## Each cell size is run three times; the table lists every run.
## Differences are printed in millionths: micrometers for positions,
## 1e-6 for the length of the difference of two unit normals.

const RUNS := 3


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -s mesher_compare.gd -- <shape.tres> <cell> [cell ...]")
		quit(2)
		return
	var shape := load(args[0]) as SdfShape
	var shader := load("res://shaders/compute/surface_nets.glsl") as RDShaderFile
	var gpu := SurfaceNetsGpu.new(shader)
	if not gpu.is_available():
		push_error("no RenderingDevice: run with a window")
		quit(1)
		return
	print("cell_m  points  cells  vertices  triangles  sample_ms  cpu_pass1_ms  gpu_pass1_ms  (upload dispatch download)  faces_ms  flag_diff  max_dpos_um  max_dnormal_e6")
	for a in range(1, args.size()):
		var cell := float(args[a])
		for run in RUNS:
			var grid := SdfGrid.sample(shape, cell)
			var started := Time.get_ticks_usec()
			var gpu_table := gpu.run(grid)
			var gpu_ms := (Time.get_ticks_usec() - started) / 1000.0
			started = Time.get_ticks_usec()
			var cpu_table := SurfaceNets.cell_table(grid)
			var cpu_ms := (Time.get_ticks_usec() - started) / 1000.0
			var nets := SurfaceNets.new()
			nets.build(grid, gpu_table)

			# Q: What counts as "the same"?
			# A: The same set of cells with a vertex (flag), and the
			#    largest distance between GPU and CPU positions and normals.
			var flags := 0
			var dpos := 0.0
			var dnormal := 0.0
			for c in grid.cell_count():
				var at := c * SurfaceNets.CELL_FLOATS
				if gpu_table[at + 3] != cpu_table[at + 3]:
					flags += 1
					continue
				if cpu_table[at + 3] < 0.5:
					continue
				dpos = maxf(dpos, Vector3(gpu_table[at] - cpu_table[at], gpu_table[at + 1] - cpu_table[at + 1], gpu_table[at + 2] - cpu_table[at + 2]).length())
				dnormal = maxf(dnormal, Vector3(gpu_table[at + 4] - cpu_table[at + 4], gpu_table[at + 5] - cpu_table[at + 5], gpu_table[at + 6] - cpu_table[at + 6]).length())
			print("%.3f  %d  %d  %d  %d  %.0f  %.0f  %.2f  (%.2f %.2f %.2f)  %.0f  %d  %.2f  %.2f" % [
				cell, grid.values.size(), grid.cell_count(), nets.positions.size(), nets.triangle_count(),
				grid.sample_milliseconds, cpu_ms, gpu_ms, gpu.upload_milliseconds, gpu.dispatch_milliseconds,
				gpu.download_milliseconds, nets.face_milliseconds, flags, dpos * 1e6, dnormal * 1e6])
	quit(0)
