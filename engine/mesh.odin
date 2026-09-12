package engine

import "core:hash"

// Vertex format a mesh's data is packed in, which picks the gpu buffer it
// lands in. Many pipelines can share one layout.
VertexLayout :: enum {
	Unlit,
}

// Draw state a mesh is rendered with.
Pipeline :: enum {
	Unlit,
}

// The layout a pipeline reads its vertices in.
pipeline_layout :: proc(pipeline: Pipeline) -> VertexLayout {
	switch pipeline {
	case .Unlit:
		return .Unlit
	}
	panic("unknown pipeline")
}

// Size of one vertex in a layout, used to turn byte offsets into vertex indices.
layout_stride :: proc(layout: VertexLayout) -> u64 {
	switch layout {
	case .Unlit:
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
	if mesh, ok := app.meshes[key]; ok {
		return mesh.offsets
	}

	offsets := BufferOffsets {
		vertex = gpu_buffer_push(app, vertex_buffer(app, layout), data),
		index  = gpu_buffer_push(app, &app.indices, indices),
	}
	app.meshes[key] = Mesh {
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
	case .Unlit:
		return &app.unlit_vertices
	}
	panic("unknown vertex layout")
}
