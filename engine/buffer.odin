package engine

import "core:mem"
import "vendor:wgpu"

UNLIT_VERTEX_BUFFER_SIZE :: 4 * mem.Megabyte
UI_VERTEX_BUFFER_SIZE :: MAX_UI_VERTICES * size_of(UiVertex)
UI_INDEX_BUFFER_SIZE :: MAX_UI_INDICES * size_of(Index)
INDEX_BUFFER_SIZE :: 1 * mem.Megabyte
MODEL_BUFFER_SIZE :: MAX_ENTITIES * size_of(Mat4)

// Every draw shares one index buffer, so every mesh must use this format.
Index :: u32
INDEX_FORMAT :: wgpu.IndexFormat.Uint32

// A fixed-size gpu buffer handed out by bump allocation. Never frees; used
// resets only when the whole buffer is reset.
GpuBuffer :: struct {
	handle: wgpu.Buffer,
	size:   u64,
	used:   u64,
}

// Creates the shared mesh buffers and the per frame camera and model buffers.
create_buffers :: proc(app: ^App) {
	app.unlit_vertices = gpu_buffer_create(app, "unlit vertices", UNLIT_VERTEX_BUFFER_SIZE, {.Vertex, .CopyDst})
	app.ui_vertices = gpu_buffer_create(app, "ui vertices", UI_VERTEX_BUFFER_SIZE, {.Vertex, .CopyDst})
	app.ui_indices = gpu_buffer_create(app, "ui indices", UI_INDEX_BUFFER_SIZE, {.Index, .CopyDst})
	app.indices = gpu_buffer_create(app, "indices", INDEX_BUFFER_SIZE, {.Index, .CopyDst})
	app.camera_uniform = gpu_buffer_create(app, "camera", size_of(Mat4), {.Uniform, .CopyDst})
	app.models = gpu_buffer_create(app, "models", MODEL_BUFFER_SIZE, {.Storage, .CopyDst})
	app.ui_uniform = gpu_buffer_create(app, "ui projection", size_of(Mat4), {.Uniform, .CopyDst})
}

delete_buffers :: proc(app: ^App) {
	wgpu.BufferRelease(app.unlit_vertices.handle)
	wgpu.BufferRelease(app.ui_vertices.handle)
	wgpu.BufferRelease(app.ui_indices.handle)
	wgpu.BufferRelease(app.indices.handle)
	wgpu.BufferRelease(app.camera_uniform.handle)
	wgpu.BufferRelease(app.models.handle)
	wgpu.BufferRelease(app.ui_uniform.handle)
}

// Uploads data at the current bump offset and returns that offset in bytes.
// Panics when the buffer is full.
@(private)
gpu_buffer_push :: proc(app: ^App, buf: ^GpuBuffer, data: []$T) -> u64 {
	size := u64(len(data) * size_of(T))
	offset := buf.used
	if offset + size > buf.size {
		panic("gpu buffer out of space")
	}
	wgpu.QueueWriteBuffer(app.queue, buf.handle, offset, raw_data(data), uint(size))
	buf.used = offset + size
	return offset
}

// Overwrites the start of a buffer, ignoring the bump offset. For buffers
// rewritten whole each frame rather than bump allocated.
@(private)
gpu_buffer_write :: proc(app: ^App, buf: ^GpuBuffer, data: []$T) {
	size := u64(len(data) * size_of(T))
	if size > buf.size {
		panic("gpu buffer out of space")
	}
	wgpu.QueueWriteBuffer(app.queue, buf.handle, 0, raw_data(data), uint(size))
}

@(private)
gpu_buffer_reset :: proc(buf: ^GpuBuffer) {
	buf.used = 0
}

@(private)
gpu_buffer_create :: proc(app: ^App, label: string, size: u64, usage: wgpu.BufferUsageFlags) -> GpuBuffer {
	handle := wgpu.DeviceCreateBuffer(app.device, &{label = label, size = size, usage = usage})
	if handle == nil {
		panic("failed to create gpu buffer")
	}
	return {handle = handle, size = size}
}
