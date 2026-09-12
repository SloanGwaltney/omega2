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
}

// Snapshots the keyboard and relative mouse state into app.input.
sample_input_system :: proc(app: ^App) {
	app.input.keys = sdl3.GetKeyboardState(nil)
	_ = sdl3.GetRelativeMouseState(&app.input.mouse_delta.x, &app.input.mouse_delta.y)
}
