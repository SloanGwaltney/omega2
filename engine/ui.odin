package engine

import "vendor:wgpu"

// Immediate mode ui. Every frame ui_system clears the geometry, hands the Ui
// to the game's callback to refill, and uploads it. Nothing here is retained
// between frames, so ui lives outside the ecs: the game owns the state the
// callback reads, and this owns only the quads it produced.

MAX_UI_VERTICES :: 4096
MAX_UI_INDICES :: 6144

// Axis aligned rectangle in pixels, origin at the top left of the window.
Rect :: struct {
	x, y, w, h: f32,
}

// Emits a frame of ui. Called by ui_system with a cleared Ui to push into.
UiCallback :: proc(app: ^App, ui: ^Ui)

// This frame's ui geometry, refilled from scratch each frame.
Ui :: struct {
	vertices:     [MAX_UI_VERTICES]UiVertex,
	indices:      [MAX_UI_INDICES]Index,
	vertex_count: u32,
	index_count:  u32,
}

// Clears the geometry, runs the ui callback and uploads what it pushed.
ui_system :: proc(app: ^App) {
	ui := &app.ui
	ui.vertex_count = 0
	ui.index_count = 0

	if app.ui_callback != nil {
		app.ui_callback(app, ui)
	}
	if ui.index_count == 0 {
		return
	}
	gpu_buffer_write(app, &app.ui_vertices, ui.vertices[:ui.vertex_count])
	gpu_buffer_write(app, &app.ui_indices, ui.indices[:ui.index_count])
}

// Pushes a solid rectangle. Panics once the frame's ui geometry is full.
ui_rect :: proc(ui: ^Ui, r: Rect, color: Vec4) {
	assert(ui.vertex_count + 4 <= MAX_UI_VERTICES, "out of ui vertices")
	assert(ui.index_count + 6 <= MAX_UI_INDICES, "out of ui indices")

	base := ui.vertex_count
	ui.vertices[base + 0] = {pos = {r.x, r.y, 0}, color = color}
	ui.vertices[base + 1] = {pos = {r.x, r.y + r.h, 0}, color = color}
	ui.vertices[base + 2] = {pos = {r.x + r.w, r.y + r.h, 0}, color = color}
	ui.vertices[base + 3] = {pos = {r.x + r.w, r.y, 0}, color = color}
	ui.vertex_count += 4

	quad := [?]Index{0, 1, 2, 0, 2, 3}
	for offset, i in quad {
		ui.indices[ui.index_count + u32(i)] = base + offset
	}
	ui.index_count += 6
}

// Draws this frame's ui as one call, on top of the world.
draw_ui_system :: proc(app: ^App) {
	if app.ui.index_count == 0 {
		return
	}
	pass := app.frame.pass
	wgpu.RenderPassEncoderSetPipeline(pass, app.ui_pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, app.ui_vertices.handle, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.ui_indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.frame_bind_group)
	wgpu.RenderPassEncoderDrawIndexed(pass, app.ui.index_count, 1, 0, 0, 0)
}
