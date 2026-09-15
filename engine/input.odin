package engine

import "vendor:sdl3"

// Raw device state for this frame. Sampled before any user system runs, so
// user systems read the same snapshot the whole frame. Mapping this to
// intent is the game's job.
Input :: struct {
	// Key state indexed by sdl3.Scancode. Owned by SDL.
	keys:        [^]bool,
	// Mouse motion since the last frame, in pixels. x is right, y is down.
	mouse_delta: Vec2,
	// Cursor position in window pixels, origin at the top left. Frozen while
	// the mouse is captured in relative mode.
	mouse_pos:   Vec2,
	// Left button state this frame, and whether it went down this frame.
	mouse_down:  bool,
	mouse_click: bool,
}

// Snapshots the keyboard and relative mouse state into app.input.
sample_input_system :: proc(app: ^App) {
	app.input.keys = sdl3.GetKeyboardState(nil)
	_ = sdl3.GetRelativeMouseState(&app.input.mouse_delta.x, &app.input.mouse_delta.y)

	buttons := sdl3.GetMouseState(&app.input.mouse_pos.x, &app.input.mouse_pos.y)
	was_down := app.input.mouse_down
	app.input.mouse_down = .LEFT in buttons
	app.input.mouse_click = app.input.mouse_down && !was_down
}

// Captures the mouse for relative aiming, hiding the cursor and freezing
// input.mouse_pos, or releases it so the cursor and the ui can be used.
set_mouse_captured :: proc(app: ^App, captured: bool) {
	if !sdl3.SetWindowRelativeMouseMode(app.window.handle, captured) {
		panic("failed to set mouse capture")
	}
}
