package engine

import "core:testing"

@(private = "file")
corners :: proc(ui: ^Ui, base: u32) -> [4]Vec3 {
	return {
		ui.vertices[base + 0].pos,
		ui.vertices[base + 1].pos,
		ui.vertices[base + 2].pos,
		ui.vertices[base + 3].pos,
	}
}

@(private = "file")
quad_indices :: proc(ui: ^Ui, at: u32) -> (q: [6]Index) {
	copy(q[:], ui.indices[at:at + 6])
	return
}

@(test)
test_ui_rect_corners :: proc(t: ^testing.T) {
	ui := new(Ui)
	defer free(ui)

	ui_rect(ui, {10, 20, 30, 40}, {1, 0, 0, 1})

	testing.expect_value(t, ui.vertex_count, u32(4))
	testing.expect_value(t, ui.index_count, u32(6))
	testing.expect_value(
		t,
		corners(ui, 0),
		[4]Vec3{{10, 20, 0}, {10, 60, 0}, {40, 60, 0}, {40, 20, 0}},
	)
	for v in ui.vertices[:4] {
		testing.expect_value(t, v.color, Vec4{1, 0, 0, 1})
	}
	testing.expect_value(t, quad_indices(ui, 0), [6]Index{0, 1, 2, 0, 2, 3})
}

// The second rect's indices must be offset by the first rect's vertices, or
// both quads draw over the same corners.
@(test)
test_ui_rect_indices_are_absolute :: proc(t: ^testing.T) {
	ui := new(Ui)
	defer free(ui)

	ui_rect(ui, {0, 0, 1, 1}, {1, 1, 1, 1})
	ui_rect(ui, {5, 5, 1, 1}, {1, 1, 1, 1})

	testing.expect_value(t, ui.vertex_count, u32(8))
	testing.expect_value(t, ui.index_count, u32(12))
	testing.expect_value(t, quad_indices(ui, 6), [6]Index{4, 5, 6, 4, 6, 7})
	testing.expect_value(t, corners(ui, 4)[0], Vec3{5, 5, 0})
}

// ui_system clears before the callback runs, so a frame that pushes nothing
// leaves no geometry from the frame before it.
@(test)
test_ui_rect_accumulates_until_cleared :: proc(t: ^testing.T) {
	ui := new(Ui)
	defer free(ui)

	ui_rect(ui, {0, 0, 1, 1}, {1, 1, 1, 1})
	ui.vertex_count = 0
	ui.index_count = 0
	ui_rect(ui, {2, 2, 3, 3}, {1, 1, 1, 1})

	testing.expect_value(t, ui.vertex_count, u32(4))
	testing.expect_value(t, ui.index_count, u32(6))
	testing.expect_value(t, quad_indices(ui, 0), [6]Index{0, 1, 2, 0, 2, 3})
	testing.expect_value(t, corners(ui, 0)[0], Vec3{2, 2, 0})
}

@(test)
test_rect_contains_edges_are_half_open :: proc(t: ^testing.T) {
	r := Rect{10, 20, 30, 40}

	testing.expect(t, rect_contains(r, {10, 20}))
	testing.expect(t, rect_contains(r, {39.9, 59.9}))
	testing.expect(t, !rect_contains(r, {40, 40}))
	testing.expect(t, !rect_contains(r, {20, 60}))
	testing.expect(t, !rect_contains(r, {9.9, 40}))
}

@(test)
test_ui_textured_rect_uv_corners :: proc(t: ^testing.T) {
	ui := new(Ui)
	defer free(ui)

	ui_textured_rect(ui, {0, 0, 10, 10}, {0.25, 0.5, 0.25, 0.5}, {1, 1, 1, 1})

	uvs: [4]Vec2
	for v, i in ui.vertices[:4] {
		uvs[i] = v.uv
	}
	testing.expect_value(t, uvs, [4]Vec2{{0.25, 0.5}, {0.25, 1}, {0.5, 1}, {0.5, 0.5}})
}

// A zeroed app is enough for the slider: it reads only the mouse.
@(private = "file")
slider_app :: proc(pos: Vec2, down, click: bool) -> ^App {
	app := new(App)
	app.input.mouse_pos = pos
	app.input.mouse_down = down
	app.input.mouse_click = click
	return app
}

@(private = "file")
SLIDER_RECT :: Rect{100, 0, 100 + UI_SLIDER_KNOB_W, 20}

@(test)
test_ui_slider_click_inside_claims_active :: proc(t: ^testing.T) {
	app := slider_app({150, 10}, true, true)
	defer free(app)
	value: f32 = 0

	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 1)

	testing.expect(t, app.ui.active == &value)
}

@(test)
test_ui_slider_click_outside_is_ignored :: proc(t: ^testing.T) {
	app := slider_app({10, 10}, true, true)
	defer free(app)
	value: f32 = 0.25

	changed := ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 1)

	testing.expect(t, app.ui.active == nil)
	testing.expect(t, !changed)
	testing.expect_value(t, value, f32(0.25))
}

// The knob is dragged by its centre, so the track runs from half a knob in to
// half a knob short of the end.
@(test)
test_ui_slider_drag_maps_mouse_to_value :: proc(t: ^testing.T) {
	app := slider_app({100 + UI_SLIDER_KNOB_W / 2 + 25, 10}, true, true)
	defer free(app)
	value: f32 = 0

	changed := ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)

	testing.expect(t, changed)
	testing.expect_value(t, value, f32(25))
}

@(test)
test_ui_slider_drag_clamps_at_both_ends :: proc(t: ^testing.T) {
	app := slider_app({150, 10}, true, true)
	defer free(app)
	value: f32 = 50
	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)

	app.input.mouse_click = false
	app.input.mouse_pos.x = -500
	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)
	testing.expect_value(t, value, f32(0))

	app.input.mouse_pos.x = 500
	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)
	testing.expect_value(t, value, f32(100))
}

// changed reports movement, not that the knob is held, so a drag that stays
// put does not read as a change.
@(test)
test_ui_slider_unmoved_drag_is_not_a_change :: proc(t: ^testing.T) {
	app := slider_app({100 + UI_SLIDER_KNOB_W / 2 + 40, 10}, true, true)
	defer free(app)
	value: f32 = 0

	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)
	app.input.mouse_click = false
	changed := ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)

	testing.expect(t, !changed)
	testing.expect_value(t, value, f32(40))
}

// The grab is held across frames, so the value keeps following a cursor that
// has left the rect until the button is released.
@(test)
test_ui_slider_drag_holds_outside_the_rect :: proc(t: ^testing.T) {
	app := slider_app({100 + UI_SLIDER_KNOB_W / 2 + 40, 10}, true, true)
	defer free(app)
	value: f32 = 0
	ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)

	app.input.mouse_click = false
	app.input.mouse_pos = {100 + UI_SLIDER_KNOB_W / 2 + 60, 400}
	changed := ui_slider(app, &app.ui, SLIDER_RECT, &value, 0, 100)

	testing.expect(t, changed)
	testing.expect(t, abs(value - 60) < EPSILON, "value should follow the cursor")
	testing.expect(t, app.ui.active == &value)
}
