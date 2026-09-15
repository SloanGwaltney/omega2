package engine

import "core:mem"
import "core:mem/virtual"
import "vendor:sdl3"

WORLD_ARENA_SIZE :: 100 * mem.Megabyte

App :: struct {
	world_arena:  virtual.Arena,
	world:        ^World,
	window:       Window,
	render:       Render,
	// This frame's ui geometry, rebuilt by ui_system.
	ui:           Ui,
	// Called by ui_system to emit this frame's ui, if set.
	ui_callback:  UiCallback,
	// This frame's raw device state, refilled by sample_input_system.
	input:        Input,
	// The game's systems, run each frame after PRE_SYSTEMS and before the
	// engine's own. They get the whole app, engine components included.
	user_systems: []System,
}

// Allocates the app with a 100MB world arena and a world living on it, and opens the window.
new_app :: proc() -> ^App {
	app := new(App)
	if err := virtual.arena_init_static(&app.world_arena, WORLD_ARENA_SIZE); err != nil {
		panic("failed to reserve world arena")
	}
	app.world = world_create(virtual.arena_allocator(&app.world_arena))
	create_window(app)
	create_render(app)
	return app
}

// Releases the world arena and everything on it, the window and the wgpu handles.
delete_app :: proc(app: ^App) {
	delete_render(app)
	delete_window(&app.window)
	virtual.arena_destroy(&app.world_arena)
	free(app)
}

// Runs the event loop until the window is closed.
run_app :: proc(app: ^App) {
	event: sdl3.Event
	for {
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				return
			case .MOUSE_WHEEL:
				app.input.wheel_accum += event.wheel.y
			case .WINDOW_PIXEL_SIZE_CHANGED:
				resize_surface(app, u32(event.window.data1), u32(event.window.data2))
			}
		}

		for system in PRE_SYSTEMS {
			system(app)
		}
		for system in app.user_systems {
			system(app)
		}
		for system in UPDATE_SYSTEMS {
			system(app)
		}
		for system in RENDER_SYSTEMS {
			system(app)
		}
	}
}
