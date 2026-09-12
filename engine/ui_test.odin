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
