package engine

import "vendor:sdl3"

System :: proc(app: ^App)

// Each frame run_app runs PRE_SYSTEMS, then the app's user_systems, then
// UPDATE_SYSTEMS, then RENDER_SYSTEMS, every list in order. PRE_SYSTEMS is
// everything a user system needs read ready: the frame's timing and input.

PRE_SYSTEMS :: [?]System{set_delta_time, sample_input_system}
UPDATE_SYSTEMS :: [?]System{upload_drawables_system, ui_system}
RENDER_SYSTEMS :: [?]System {
	upload_frame_uniforms_system,
	start_render_pass_system,
	draw_render_system,
	draw_ui_system,
	end_render_pass_system,
	profile_report_system,
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
