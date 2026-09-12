package engine

import "core:math/linalg"
import "vendor:sdl3"

// Per entity input state, filled each frame by sample_input_system.
InputValues :: struct {
	// WASD movement on the xz plane, normalized. x is right, y is forward.
	movement: Vec2,
	// Mouse motion since the last frame, in pixels. x is right, y is down.
	look:     Vec2,
}

// Writes the current keyboard and relative mouse state into every
// InputValues component.
sample_input_system :: proc(app: ^App) {
	w := app.world
	keys := sdl3.GetKeyboardState(nil)

	movement: Vec2
	if keys[sdl3.Scancode.D] do movement.x += 1
	if keys[sdl3.Scancode.A] do movement.x -= 1
	if keys[sdl3.Scancode.W] do movement.y += 1
	if keys[sdl3.Scancode.S] do movement.y -= 1
	if movement != {} {
		movement = linalg.normalize(movement)
	}

	look: Vec2
	_ = sdl3.GetRelativeMouseState(&look.x, &look.y)

	for i in 0 ..< w.count {
		input := pool_get(&w.input, Entity(i))
		if input == nil {
			continue
		}
		input.movement = movement
		input.look = look
	}
}
