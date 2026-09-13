// The pause menu: escape opens it, releasing the mouse, and the resume button
// closes it and recaptures.
package main

import "../../../engine"
import "vendor:sdl3"

MENU_BUTTON_WIDTH :: 240.0
MENU_BUTTON_HEIGHT :: 56.0

// Opens or closes the menu on the frame escape goes down, and captures the
// mouse to match.
menu_system :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	down := app.input.keys[sdl3.Scancode.ESCAPE]
	defer g.escape_down = down
	if !down || g.escape_down {
		return
	}
	menu_set_open(app, !g.menu_open)
}

// Draws the menu's buttons, closing it when resume is clicked.
menu_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	if !g.menu_open {
		return
	}
	r := engine.Rect {
		f32(app.surface_config.width) / 2 - MENU_BUTTON_WIDTH / 2,
		f32(app.surface_config.height) / 2 - MENU_BUTTON_HEIGHT / 2,
		MENU_BUTTON_WIDTH,
		MENU_BUTTON_HEIGHT,
	}
	if engine.ui_button(app, ui, r, .Large, "Resume") {
		menu_set_open(app, false)
	}
}

@(private = "file")
menu_set_open :: proc(app: ^engine.App, open: bool) {
	g := (^Game)(app.world.user_ptr)
	g.menu_open = open
	engine.set_mouse_captured(app, !open)
}
