// Casino scratch scene: a first person camera that aims with the mouse and
// walks the xz plane with WASD over a flat floor.
package main

import "../../../engine"
import "core:fmt"
import "core:math"
import "core:slice"

EYE_HEIGHT :: 1.7
FLOOR_HALF :: 50.0
FLOOR_COLOR :: engine.Vec4{0.15, 0.35, 0.2, 1}
CROSSHAIR_LENGTH :: 18.0
CROSSHAIR_THICKNESS :: 2.0
CROSSHAIR_COLOR :: engine.Vec4{1, 1, 1, 0.75}
PROMPT_OFFSET :: 48.0
PROMPT_COLOR :: engine.Vec4{1, 1, 1, 1}
BANK_MARGIN :: 16.0
BANK_COLOR :: engine.Vec4{1, 0.9, 0.4, 1}

// The player, spawned through the json loader. Embedded at compile time, so
// a renamed scene fails the build rather than the launch.
PLAYER_JSON :: #load("scenes/player.json", string)

FLOOR_VERTICES := [?]engine.Vertex {
	{pos = {-FLOOR_HALF, 0, FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {FLOOR_HALF, 0, FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {FLOOR_HALF, 0, -FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {-FLOOR_HALF, 0, -FLOOR_HALF}, color = FLOOR_COLOR},
}
FLOOR_INDICES := [?]engine.Index{0, 1, 2, 0, 2, 3}

// Draws a centred crosshair, or the slot machine screen in place of the
// world ui while a machine is open.
casino_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	if (^Game)(app.world.user_ptr).open_machine != nil {
		slot_machine_ui(app, ui)
		return
	}
	w := f32(app.window.config.width)
	h := f32(app.window.config.height)
	cx := w / 2 - CROSSHAIR_LENGTH / 2
	cy := h / 2 - CROSSHAIR_LENGTH / 2
	engine.ui_rect(
		ui,
		{cx, h / 2 - CROSSHAIR_THICKNESS / 2, CROSSHAIR_LENGTH, CROSSHAIR_THICKNESS},
		CROSSHAIR_COLOR,
	)
	engine.ui_rect(
		ui,
		{w / 2 - CROSSHAIR_THICKNESS / 2, cy, CROSSHAIR_THICKNESS, CROSSHAIR_LENGTH},
		CROSSHAIR_COLOR,
	)
	prompt_ui(app, ui)
	clock_ui(app, ui)
	bank_ui(app, ui)
	menu_ui(app, ui)
	shop_ui(app, ui)
}

// Draws the prompt raised by whatever the player is aimed at, centred below
// the crosshair.
prompt_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	if g.prompt == "" {
		return
	}
	pos := engine.Vec2 {
		f32(app.window.config.width) / 2 - engine.font_measure(&app.render.font, .Large, g.prompt) / 2,
		f32(app.window.config.height) / 2 + PROMPT_OFFSET,
	}
	engine.ui_text(app, ui, pos, .Large, g.prompt, PROMPT_COLOR)
}

// Draws the house's bank in the top right corner.
bank_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	text := fmt.tprintf("$%.0f", g.bank)
	x := f32(app.window.config.width) - BANK_MARGIN - engine.font_measure(&app.render.font, .Large, text)
	engine.ui_text(app, ui, {x, BANK_MARGIN}, .Large, text, BANK_COLOR)
}

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)
	shop_bake_icons(app)
	defer shop_delete_icons()

	// Too large for the stack.
	game := new(Game)
	defer free(game)
	game.clock = clock_init()
	app.world.user_ptr = game
	app.world.on_destroy = game_on_destroy
	app.user_systems = GAME_SYSTEMS[:]

	if _, ok := engine.entity_from_json(app.world, PLAYER_JSON, casino_component_loader); !ok {
		panic("bad player json")
	}

	floor := engine.entity_create(app.world)
	engine.pool_add(&app.world.transform, floor, engine.transform_identity())
	engine.pool_add(
		&app.world.drawable_upload,
		floor,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(FLOOR_VERTICES[:]),
			indices = FLOOR_INDICES[:],
		},
	)

	slot_machine_create(app, {-1.5, 0, 0})
	slot_machine_create(app, {1.5, 0, 0})

	patron_create(app, {-6, 0, 8})
	patron_create(app, {6, 0, 8})
	patron_create(app, {0, 0, 12})

	app.ui_callback = casino_ui

	engine.run_app(app)
}
