package engine

import "core:hash"
import "core:slice"

// Vertex format a mesh's data is packed in, which picks the gpu buffer it
// lands in. Many pipelines can share one layout.
VertexLayout :: enum {
	Mesh,
}

// Draw state a mesh is rendered with.
Pipeline :: enum {
	Unlit,
	Lit,
}

// The layout a pipeline reads its vertices in. Unlit and Lit share one, so the
// same mesh can be drawn either way without being uploaded twice.
pipeline_layout :: proc(pipeline: Pipeline) -> VertexLayout {
	switch pipeline {
	case .Unlit, .Lit:
		return .Mesh
	}
	panic("unknown pipeline")
}

// Size of one vertex in a layout, used to turn byte offsets into vertex indices.
layout_stride :: proc(layout: VertexLayout) -> u64 {
	switch layout {
	case .Mesh:
		return size_of(Vertex)
	}
	panic("unknown vertex layout")
}

// Where a mesh's data landed in the shared gpu buffers, in bytes.
BufferOffsets :: struct {
	vertex: u64,
	index:  u64,
}

// Cpu-side mesh. data holds vertices packed for layout, indices reference them.
Mesh :: struct {
	layout:  VertexLayout,
	data:    []byte,
	indices: []Index,
	offsets: BufferOffsets,
}

// Identifies mesh data by layout and content hash.
MeshKey :: struct {
	layout: VertexLayout,
	hash:   u64,
}

// Meshes already uploaded, keyed by layout and the hash of their vertex data.
MeshStorage :: map[MeshKey]Mesh

delete_mesh_storage :: proc(storage: ^MeshStorage) {
	delete(storage^)
}

// Uploads a mesh to the shared gpu buffers and returns where it landed. A mesh
// whose data was already uploaded is not uploaded twice; its offsets are reused.
mesh_upload :: proc(app: ^App, layout: VertexLayout, data: []byte, indices: []Index) -> BufferOffsets {
	key := MeshKey{layout, hash.fnv64a(data)}
	if mesh, ok := app.render.meshes[key]; ok {
		return mesh.offsets
	}

	offsets := BufferOffsets {
		vertex = gpu_buffer_push(app, vertex_buffer(app, layout), data),
		index  = gpu_buffer_push(app, &app.render.indices, indices),
	}
	app.render.meshes[key] = Mesh {
		layout  = layout,
		data    = data,
		indices = indices,
		offsets = offsets,
	}
	return offsets
}

@(private)
vertex_buffer :: proc(app: ^App, layout: VertexLayout) -> ^GpuBuffer {
	switch layout {
	case .Mesh:
		return &app.render.mesh_vertices
	}
	panic("unknown vertex layout")
}

// A mesh's cpu side data before it is uploaded: vertices packed for a layout,
// the indices into them, and the box they fill. What a hand written mesh and
// an imported one both look like, so either can feed DrawableUpload,
// icon_bake and the Aabb pool.
MeshData :: struct {
	data:    []byte,
	indices: []Index,
	bounds:  Aabb,
}

// Moves a mesh's vertices so its footprint is centred on the origin with its
// base at y zero, which is where a transform, an Aabb and a seat in front of
// a prop all expect the origin to be. An exporter is free to model about any
// point, so an imported mesh goes through this before it is used.
mesh_ground :: proc(mesh: ^MeshData) {
	offset := Vec3 {
		(mesh.bounds.min.x + mesh.bounds.max.x) / 2,
		mesh.bounds.min.y,
		(mesh.bounds.min.z + mesh.bounds.max.z) / 2,
	}
	for &v in slice.reinterpret([]Vertex, mesh.data) {
		v.pos -= offset
	}
	mesh.bounds.min -= offset
	mesh.bounds.max -= offset
}
