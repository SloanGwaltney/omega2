package engine

import "vendor:sdl3"

System :: proc(app: ^App)

// The split between the two lists is cosmetic grouping only; each frame
// run_app runs every UPDATE_SYSTEMS entry in order, then every
// RENDER_SYSTEMS entry in order.

UPDATE_SYSTEMS :: [?]System{set_delta_time, upload_drawables_system}
RENDER_SYSTEMS :: [?]System {
	upload_frame_uniforms_system,
	start_render_pass_system,
	draw_render_system,
	end_render_pass_system,
}

/// Writes the nanoseconds elapsed since the last call into world.delta_time.
set_delta_time :: proc(app: ^App) {
	@(static) last: u64
	now := sdl3.GetTicksNS()
	if last != 0 {
		app.world.delta_time = now - last
	}
	last = now
}
