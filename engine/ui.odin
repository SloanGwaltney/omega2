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
	// Sampled by every quad this frame. Left nil the ui samples the font atlas.
	texture:      ^Texture,
	// Where the white texel sits in the bound texture, used by flat quads.
	white_uv:     Vec2,
	// Widget dragging the mouse, identified by the pointer it drives. Held
	// across frames until the button is released.
	active:       rawptr,
}

// Clears the geometry, runs the ui callback and uploads what it pushed.
ui_system :: proc(app: ^App) {
	ui := &app.ui
	ui.vertex_count = 0
	ui.index_count = 0
	ui.texture = nil
	ui.white_uv = app.render.font.white_uv
	if !app.input.mouse_down {
		ui.active = nil
	}

	if app.ui_callback != nil {
		app.ui_callback(app, ui)
	}
	if ui.index_count == 0 {
		return
	}
	gpu_buffer_write(app, &app.render.ui_vertices, ui.vertices[:ui.vertex_count])
	gpu_buffer_write(app, &app.render.ui_indices, ui.indices[:ui.index_count])
}

// Pushes a solid rectangle. Panics once the frame's ui geometry is full.
ui_rect :: proc(ui: ^Ui, r: Rect, color: Vec4) {
	ui_textured_rect(ui, r, {ui.white_uv.x, ui.white_uv.y, 0, 0}, color)
}

// Button colors, brightened while the cursor is over the button.
UI_BUTTON_COLOR :: Vec4{0.16, 0.16, 0.18, 0.9}
UI_BUTTON_HOVER_COLOR :: Vec4{0.28, 0.28, 0.32, 0.95}
UI_BUTTON_TEXT_COLOR :: Vec4{1, 1, 1, 1}

// Pushes a button filling r with text centred in it, and returns true on the
// frame the left button goes down inside it.
ui_button :: proc(app: ^App, ui: ^Ui, r: Rect, size: FontSize, text: string) -> bool {
	hovered := rect_contains(r, app.input.mouse_pos)
	ui_rect(ui, r, UI_BUTTON_HOVER_COLOR if hovered else UI_BUTTON_COLOR)

	face := &app.render.font.faces[size]
	pos := Vec2 {
		r.x + (r.w - font_measure(&app.render.font, size, text)) / 2,
		r.y + (r.h - face.line_height) / 2,
	}
	ui_text(app, ui, pos, size, text, UI_BUTTON_TEXT_COLOR)
	return hovered && app.input.mouse_click
}

// Slider colors, with the knob brightened while it is being dragged.
UI_SLIDER_TRACK_COLOR :: Vec4{0.12, 0.12, 0.14, 0.9}
UI_SLIDER_KNOB_COLOR :: Vec4{0.55, 0.55, 0.6, 1}
UI_SLIDER_KNOB_ACTIVE_COLOR :: Vec4{0.85, 0.85, 0.9, 1}
UI_SLIDER_KNOB_W :: 12

// Pushes a horizontal slider filling r that drives value over min to max, and
// returns true on frames the drag moved it.
ui_slider :: proc(app: ^App, ui: ^Ui, r: Rect, value: ^f32, min, max: f32) -> bool {
	if ui.active == nil && app.input.mouse_click && rect_contains(r, app.input.mouse_pos) {
		ui.active = value
	}

	changed := false
	if ui.active == value {
		t := clamp(
			(app.input.mouse_pos.x - r.x - UI_SLIDER_KNOB_W / 2) / (r.w - UI_SLIDER_KNOB_W),
			0,
			1,
		)
		next := min + t * (max - min)
		changed = next != value^
		value^ = next
	}

	ui_rect(ui, r, UI_SLIDER_TRACK_COLOR)
	t := clamp((value^ - min) / (max - min), 0, 1)
	knob := Rect{r.x + t * (r.w - UI_SLIDER_KNOB_W), r.y, UI_SLIDER_KNOB_W, r.h}
	ui_rect(ui, knob, UI_SLIDER_KNOB_ACTIVE_COLOR if ui.active == value else UI_SLIDER_KNOB_COLOR)
	return changed
}

// True when p is inside r.
rect_contains :: proc(r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

// Rect of cell index in a grid of cols columns filling r from the top left,
// cells cell_h tall and separated by gap on both axes.
ui_grid_cell :: proc(r: Rect, cols: int, cell_h, gap: f32, index: int) -> Rect {
	assert(cols > 0, "grid needs at least one column")
	w := (r.w - gap * f32(cols - 1)) / f32(cols)
	col := f32(index % cols)
	row := f32(index / cols)
	return {r.x + col * (w + gap), r.y + row * (cell_h + gap), w, cell_h}
}

// Pushes text with its top left corner at pos, and returns the pen's end. Only
// draws when the font atlas is bound, which is the default.
ui_text :: proc(app: ^App, ui: ^Ui, pos: Vec2, size: FontSize, text: string, color: Vec4) -> Vec2 {
	face := &app.render.font.faces[size]
	pen := Vec2{pos.x, pos.y + face.ascent}
	for ch in text {
		index := glyph_index(ch) or_continue
		quad := glyph_quad(face, index, &pen)
		ui_textured_rect(
			ui,
			{quad.x0, quad.y0, quad.x1 - quad.x0, quad.y1 - quad.y0},
			{quad.s0, quad.t0, quad.s1 - quad.s0, quad.t1 - quad.t0},
			color,
		)
	}
	return pen
}

// Pushes a rectangle sampling uv of ui.texture, tinted by color. The uv rect is
// in texture space, origin at the top left.
ui_textured_rect :: proc(ui: ^Ui, r: Rect, uv: Rect, color: Vec4) {
	assert(ui.vertex_count + 4 <= MAX_UI_VERTICES, "out of ui vertices")
	assert(ui.index_count + 6 <= MAX_UI_INDICES, "out of ui indices")

	base := ui.vertex_count
	ui.vertices[base + 0] = {pos = {r.x, r.y, 0}, color = color, uv = {uv.x, uv.y}}
	ui.vertices[base + 1] = {pos = {r.x, r.y + r.h, 0}, color = color, uv = {uv.x, uv.y + uv.h}}
	ui.vertices[base + 2] = {
		pos   = {r.x + r.w, r.y + r.h, 0},
		color = color,
		uv    = {uv.x + uv.w, uv.y + uv.h},
	}
	ui.vertices[base + 3] = {pos = {r.x + r.w, r.y, 0}, color = color, uv = {uv.x + uv.w, uv.y}}
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
	pass := app.render.frame.pass
	wgpu.RenderPassEncoderSetPipeline(pass, app.render.ui_pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, app.render.ui_vertices.handle, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.render.ui_indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.render.frame_bind_group)
	texture := app.ui.texture if app.ui.texture != nil else &app.render.font.atlas
	wgpu.RenderPassEncoderSetBindGroup(pass, 1, texture.bind_group)
	wgpu.RenderPassEncoderDrawIndexed(pass, app.ui.index_count, 1, 0, 0, 0)
}
