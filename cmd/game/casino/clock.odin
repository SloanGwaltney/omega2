// The day clock: one per game, started from the pause menu and stopped once
// closing time is reached.
package main

import "../../../engine"
import "core:fmt"

// Hours, on a 24 hour clock, the casino opens and closes at.
DAY_OPEN_HOUR :: 8.0
DAY_CLOSE_HOUR :: 20.0
// Real seconds spent per in game hour.
REAL_SECONDS_PER_HOUR :: 5.0

CLOCK_MARGIN :: 16.0
CLOCK_COLOR :: engine.Vec4{1, 1, 1, 1}

// The game's clock, counting hours from midnight while a day runs.
Clock :: struct {
	// Hours since midnight, between DAY_OPEN_HOUR and DAY_CLOSE_HOUR.
	hour:    f32,
	// Day number, incremented by each start. Zero before the first day.
	day:     int,
	// True while the clock is ticking, cleared at closing time.
	running: bool,
}

// A clock reset to opening time, before any day has started.
clock_init :: proc() -> Clock {
	return Clock{hour = DAY_OPEN_HOUR}
}

// Resets the clock to opening time and starts the next day.
clock_start_day :: proc(g: ^Game) {
	g.clock.hour = DAY_OPEN_HOUR
	g.clock.day += 1
	g.clock.running = true
}

// Advances the clock, stopping it at closing time. Held while the menu is up.
clock_system :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	if !g.clock.running || g.menu_open {
		return
	}
	dt := f32(app.world.delta_time) / 1e9
	g.clock.hour += dt / REAL_SECONDS_PER_HOUR
	if g.clock.hour >= DAY_CLOSE_HOUR {
		g.clock.hour = DAY_CLOSE_HOUR
		g.clock.running = false
	}
}

// Draws the time and day number in the top left corner.
clock_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	hour := int(g.clock.hour)
	minute := int((g.clock.hour - f32(hour)) * 60)
	time := fmt.tprintf("%2d:%02d", hour, minute)
	line := engine.font_line_height(&app.font, .Large)
	engine.ui_text(app, ui, {CLOCK_MARGIN, CLOCK_MARGIN}, .Large, time, CLOCK_COLOR)
	day := fmt.tprintf("Day %d", g.clock.day)
	engine.ui_text(app, ui, {CLOCK_MARGIN, CLOCK_MARGIN + line}, .Large, day, CLOCK_COLOR)
}
