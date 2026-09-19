package engine

@(require) import "core:fmt"

// Frame stats hud, off unless asked for at build time with
// -define:FRAME_DEBUG=true. When off none of this compiles in.
FRAME_DEBUG :: #config(FRAME_DEBUG, false)

@(private)
FRAME_DEBUG_MARGIN :: 8
@(private)
FRAME_DEBUG_PANEL_W :: 200
@(private)
FRAME_DEBUG_COLOR :: Vec4{1, 1, 1, 1}
@(private)
FRAME_DEBUG_PANEL_COLOR :: Vec4{0, 0, 0, 0.6}

// Draws the frame rate, frame time, entity and drawable counts in a panel
// centred along the top edge. Run by ui_system after the game's callback, so it
// sits on top.
frame_debug_ui :: proc(app: ^App, ui: ^Ui) {
	when FRAME_DEBUG {
		dt := f64(app.world.delta_time) / 1e9
		drawables: int
		for i in 0 ..< app.world.count {
			if app.world.drawable.has[i] {
				drawables += 1
			}
		}
		line := font_line_height(&app.render.font, .Large)
		x := (f32(app.window.config.width) - FRAME_DEBUG_PANEL_W) / 2
		panel := Rect{x, 0, FRAME_DEBUG_PANEL_W, FRAME_DEBUG_MARGIN * 2 + line * 4}
		ui_rect(ui, panel, FRAME_DEBUG_PANEL_COLOR)
		lines := [?]string {
			fmt.tprintf("fps %.0f", dt > 0 ? 1 / dt : 0),
			fmt.tprintf("dt %.2fms", dt * 1000),
			fmt.tprintf("entities %d", app.world.count),
			fmt.tprintf("drawables %d", drawables),
		}
		for text, i in lines {
			ui_text(
				app,
				ui,
				{x + FRAME_DEBUG_MARGIN, FRAME_DEBUG_MARGIN + line * f32(i)},
				.Large,
				text,
				FRAME_DEBUG_COLOR,
			)
		}
	}
}
