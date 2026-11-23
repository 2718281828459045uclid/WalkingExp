#[compute]
#version 450
// surface_nets.glsl: pass 1 of naive surface nets on the GPU (Lesson 08).
//
// How this file relates to the others:
//   src/sdf/sdf_grid.gd         samples f on the CPU into a flat float array
//   src/sdf/surface_nets_gpu.gd uploads that array, runs this shader once
//                               per cell, and reads the cell table back
//   src/sdf/surface_nets.gd     the CPU twin of this shader (cell_table()
//                               and _write_cell()), and pass 2 (the faces)
//
// The "#[compute]" line above is for Godot: it marks the file as a compute
// shader so the importer compiles it to SPIR-V (an RDShaderFile resource).
// "#version 450" selects the GLSL dialect that Vulkan-style drivers read.
//
// ---------------------------------------------------------------------
// What a compute shader is
// ---------------------------------------------------------------------
// A spatial shader (Lesson 03) runs once per vertex or per pixel, and the
// GPU decides what those are. A compute shader runs once per "invocation",
// and we decide how many: the CPU asks for a grid of workgroups, and each
// workgroup holds local_size_x * local_size_y * local_size_z invocations.
// Each invocation reads gl_GlobalInvocationID, a uvec3 that names its
// place in the whole grid of invocations. Here one invocation = one cell.
//
// Q: Why workgroups of 4 x 4 x 4 = 64?
// A: GPUs run invocations in batches of 32 or 64 that execute the same
//    instruction together. A workgroup of 64 fills one batch. A cube
//    shape keeps neighbouring cells, which read overlapping corners, in
//    the same batch.
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

// ---------------------------------------------------------------------
// Inputs and outputs
// ---------------------------------------------------------------------
// A storage buffer is a block of GPU memory that shaders may read or
// write at any index. "std430" fixes the memory layout: a float array is
// packed at 4 bytes per element, the same as PackedFloat32Array.
//
// binding 0: f at every grid point, x varying fastest:
//            index = i + dims.x * (j + dims.y * k)   (same as SdfGrid.index)
layout(set = 0, binding = 0, std430) restrict readonly buffer Values {
	float data[];
} grid_values;

// binding 1: the cell table, 8 floats per cell (SurfaceNets.CELL_FLOATS):
//            [x, y, z, has_vertex, nx, ny, nz, 0]
layout(set = 0, binding = 1, std430) restrict writeonly buffer Table {
	float data[];
} cell_table;

// A push constant is a small block of values sent with the dispatch
// itself, without a buffer. 32 bytes: the grid size and where it sits.
//   dims.xyz      grid points along each axis (dims.w unused)
//   origin_cell   xyz = position of grid point (0, 0, 0), w = cell size
layout(push_constant, std430) uniform Params {
	ivec4 dims;
	vec4 origin_cell;
} params;

float value_at(ivec3 g) {
	return grid_values.data[g.x + params.dims.x * (g.y + params.dims.y * g.z)];
}

// The position of corner n (0..7) in the unit cell. Bit 0 is +x, bit 1 is
// +y, bit 2 is +z, as in surface_nets.gd.
vec3 corner_offset(int n) {
	return vec3(float(n & 1), float((n >> 1) & 1), float((n >> 2) & 1));
}

void main() {
	ivec3 cell = ivec3(gl_GlobalInvocationID);
	ivec3 cells = params.dims.xyz - ivec3(1);

	// Q: Why can an invocation lie outside the grid?
	// A: The CPU dispatches whole workgroups. With 61 cells along x and
	//    groups of 4, it asks for 16 groups = 64 invocations; the last 3
	//    have no cell and must return before reading memory.
	if (any(greaterThanEqual(cell, cells))) {
		return;
	}
	int row = (cell.x + cells.x * (cell.y + cells.y * cell.z)) * 8;

	// Read the eight corners and count how many are inside (f < 0).
	float f[8];
	int inside_count = 0;
	for (int n = 0; n < 8; n++) {
		f[n] = value_at(cell + ivec3(corner_offset(n)));
		if (f[n] < 0.0) {
			inside_count++;
		}
	}

	// A cell with all corners on one side holds no vertex. Every row must
	// still be written: GPU memory starts with arbitrary contents, unlike
	// a resized PackedFloat32Array, which starts at zero.
	if (inside_count == 0 || inside_count == 8) {
		for (int m = 0; m < 8; m++) {
			cell_table.data[row + m] = 0.0;
		}
		return;
	}

	// The twelve edges as corner pairs, in the order of SurfaceNets.EDGES.
	// Each pair differs in one bit, so the edge is parallel to one axis.
	const ivec2 edges[12] = ivec2[12](
		ivec2(0, 1), ivec2(2, 3), ivec2(4, 5), ivec2(6, 7),
		ivec2(0, 2), ivec2(1, 3), ivec2(4, 6), ivec2(5, 7),
		ivec2(0, 4), ivec2(1, 5), ivec2(2, 6), ivec2(3, 7));

	// The vertex is the average of the zero crossings on the edges whose
	// ends have different signs. On such an edge f runs from f0 to f1; the
	// straight line through those values is zero at t = f0 / (f0 - f1),
	// and the crossing point is a + t (b - a). mix(a, b, t) computes
	// exactly a + t (b - a), for vectors one component at a time.
	vec3 sum = vec3(0.0);
	int crossings = 0;
	for (int e = 0; e < 12; e++) {
		float f0 = f[edges[e].x];
		float f1 = f[edges[e].y];
		if ((f0 < 0.0) == (f1 < 0.0)) {
			continue;
		}
		float t = f0 / (f0 - f1);
		sum += mix(corner_offset(edges[e].x), corner_offset(edges[e].y), t);
		crossings++;
	}
	vec3 uvw = sum / float(crossings);

	// Normal: the gradient of the trilinear interpolation of the eight
	// corner values, evaluated at the vertex (u, v, w). Along x the cell
	// has four edges with slopes f[1]-f[0], f[3]-f[2], f[5]-f[4], f[7]-f[6]
	// (per cell width); the derivative at the vertex blends them with the
	// bilinear weights of the other two coordinates. Same for y and z.
	// The scale (per cell, not per meter) disappears in normalize().
	float u = uvw.x;
	float v = uvw.y;
	float w = uvw.z;
	vec3 g;
	g.x = (1.0 - v) * (1.0 - w) * (f[1] - f[0]) + v * (1.0 - w) * (f[3] - f[2])
		+ (1.0 - v) * w * (f[5] - f[4]) + v * w * (f[7] - f[6]);
	g.y = (1.0 - u) * (1.0 - w) * (f[2] - f[0]) + u * (1.0 - w) * (f[3] - f[1])
		+ (1.0 - u) * w * (f[6] - f[4]) + u * w * (f[7] - f[5]);
	g.z = (1.0 - u) * (1.0 - v) * (f[4] - f[0]) + u * (1.0 - v) * (f[5] - f[1])
		+ (1.0 - u) * v * (f[6] - f[2]) + u * v * (f[7] - f[3]);
	// A zero gradient cannot be normalized (0 / 0); the CPU path uses "up"
	// in that case, and so does this one.
	vec3 normal = length(g) > 0.0 ? normalize(g) : vec3(0.0, 1.0, 0.0);

	vec3 position = params.origin_cell.xyz + (vec3(cell) + uvw) * params.origin_cell.w;
	cell_table.data[row + 0] = position.x;
	cell_table.data[row + 1] = position.y;
	cell_table.data[row + 2] = position.z;
	cell_table.data[row + 3] = 1.0;
	cell_table.data[row + 4] = normal.x;
	cell_table.data[row + 5] = normal.y;
	cell_table.data[row + 6] = normal.z;
	cell_table.data[row + 7] = 0.0;
}
