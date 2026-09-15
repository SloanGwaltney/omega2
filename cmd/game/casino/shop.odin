// The buy menu: b opens a grid of the things the casino can buy, each cell a
// placeholder picture, a description and buy and details buttons. Buying does
// nothing yet, and details swaps the cell to its stats until back is clicked.
package main

import "../../../engine"
import "core:strings"
import "vendor:sdl3"

// One thing on offer. Stats are free text until the items are real, and an
// item without a spawn cannot be bought yet.
ShopItem :: struct {
	name:        string,
	description: string,
	stats:       string,
	// What buying one takes out of the bank.
	cost:        f32,
	// Spawns the item's body for the player to place, or nil while the item
	// has no model.
	spawn:       proc(app: ^engine.App, pos: engine.Vec3) -> engine.Entity,
	// Makes a spawned body do its job, run once its placement is confirmed.
	activate:    proc(app: ^engine.App, e: engine.Entity),
}

SHOP_ITEMS := [?]ShopItem {
	{
		"Slots",
		"Three reels, house edge.",
		"Cost $2500\nRTP 80-99%\nFootprint 1x1",
		2500,
		slot_machine_spawn,
		slot_machine_activate,
	},
	{"Blackjack", "Seats five players.", "Cost $6000\nEdge 0.5%\nFootprint 2x2", 6000, nil, nil},
	{"Roulette", "Single zero wheel.", "Cost $9000\nEdge 2.7%\nFootprint 2x2", 9000, nil, nil},
	{"Bar", "Holds patrons longer.", "Cost $4000\nUpkeep $50/day\nFootprint 3x1", 4000, nil, nil},
	{
		"Neon Sign",
		"Draws more patrons in.",
		"Cost $1200\nDraw +10%\nFootprint 1x1",
		1200,
		nil,
		nil,
	},
	{"Camera", "Catches cheating patrons.", "Cost $800\nCover 8m\nFootprint 1x1", 800, nil, nil},
}

SHOP_COLS :: 3
SHOP_PAD :: 24.0
SHOP_GAP :: 16.0
SHOP_CELL_WIDTH :: 260.0
SHOP_CELL_HEIGHT :: 300.0
SHOP_PICTURE_HEIGHT :: 150.0
SHOP_BUTTON_HEIGHT :: 40.0
SHOP_TEXT_GAP :: 8.0
SHOP_PANEL_COLOR :: engine.Vec4{0.08, 0.08, 0.1, 0.95}
SHOP_CELL_COLOR :: engine.Vec4{0.14, 0.14, 0.17, 1}
SHOP_PICTURE_COLOR :: engine.Vec4{0.45, 0.45, 0.45, 1}
SHOP_TEXT_COLOR :: engine.Vec4{1, 1, 1, 1}
SHOP_BUY_COLOR :: engine.Vec4{0.15, 0.5, 0.2, 1}
SHOP_BUY_HOVER_COLOR :: engine.Vec4{0.22, 0.7, 0.3, 1}
SHOP_DETAILS_COLOR :: engine.Vec4{0.15, 0.3, 0.6, 1}
SHOP_DETAILS_HOVER_COLOR :: engine.Vec4{0.24, 0.45, 0.85, 1}

// Opens or closes the shop on the frame b goes down, and captures the mouse to
// match. Closing forgets which cells were showing their stats.
shop_system :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	down := app.input.keys[sdl3.Scancode.B]
	defer g.shop_down = down
	if !down || g.shop_down || g.placement != nil || (game_ui_open(g) && !g.shop_open) {
		return
	}
	shop_set_open(app, !g.shop_open)
}

// Draws the item grid over the world while the shop is up.
shop_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	if !g.shop_open {
		return
	}
	rows := f32((len(SHOP_ITEMS) + SHOP_COLS - 1) / SHOP_COLS)
	panel := engine.Rect {
		w = SHOP_COLS * SHOP_CELL_WIDTH + (SHOP_COLS - 1) * SHOP_GAP + SHOP_PAD * 2,
		h = rows * SHOP_CELL_HEIGHT + (rows - 1) * SHOP_GAP + SHOP_PAD * 2,
	}
	panel.x = f32(app.window.config.width) / 2 - panel.w / 2
	panel.y = f32(app.window.config.height) / 2 - panel.h / 2
	engine.ui_rect(ui, panel, SHOP_PANEL_COLOR)

	grid := engine.Rect {
		panel.x + SHOP_PAD,
		panel.y + SHOP_PAD,
		panel.w - SHOP_PAD * 2,
		panel.h - SHOP_PAD * 2,
	}
	for item, i in SHOP_ITEMS {
		cell := engine.ui_grid_cell(grid, SHOP_COLS, SHOP_CELL_HEIGHT, SHOP_GAP, i)
		shop_cell_ui(app, ui, cell, item, &g.shop_details[i])
	}
}

// Draws one item's cell, showing its stats in place of the picture and
// description while details is set.
@(private = "file")
shop_cell_ui :: proc(
	app: ^engine.App,
	ui: ^engine.Ui,
	cell: engine.Rect,
	item: ShopItem,
	details: ^bool,
) {
	engine.ui_rect(ui, cell, SHOP_CELL_COLOR)

	x := cell.x + SHOP_TEXT_GAP
	y := cell.y + SHOP_TEXT_GAP
	w := cell.w - SHOP_TEXT_GAP * 2
	if details^ {
		y = engine.ui_text(app, ui, {x, y}, .Large, item.name, SHOP_TEXT_COLOR).y + SHOP_TEXT_GAP
		shop_lines_ui(app, ui, {x, y, w, 0}, item.stats)
	} else {
		engine.ui_rect(ui, {x, y, w, SHOP_PICTURE_HEIGHT}, SHOP_PICTURE_COLOR)
		y += SHOP_PICTURE_HEIGHT + SHOP_TEXT_GAP
		y = engine.ui_text(app, ui, {x, y}, .Large, item.name, SHOP_TEXT_COLOR).y + SHOP_TEXT_GAP
		shop_lines_ui(app, ui, {x, y, w, 0}, item.description)
	}

	button_w := (w - SHOP_TEXT_GAP) / 2
	button_y := cell.y + cell.h - SHOP_TEXT_GAP - SHOP_BUTTON_HEIGHT
	if engine.ui_button_colored(
		app,
		ui,
		{x, button_y, button_w, SHOP_BUTTON_HEIGHT},
		.Large,
		"Buy",
		SHOP_BUY_COLOR,
		SHOP_BUY_HOVER_COLOR,
	) {
		shop_buy(app, item)
	}
	if engine.ui_button_colored(
		app,
		ui,
		{x + button_w + SHOP_TEXT_GAP, button_y, button_w, SHOP_BUTTON_HEIGHT},
		.Large,
		"Back" if details^ else "Details",
		SHOP_DETAILS_COLOR,
		SHOP_DETAILS_HOVER_COLOR,
	) {
		details^ = !details^
	}
}

// Closes the shop and hands the item to the player to place, if the item can
// be spawned at all and the bank covers it. The bank is not charged until the
// placement is confirmed.
@(private = "file")
shop_buy :: proc(app: ^engine.App, item: ShopItem) {
	g := (^Game)(app.world.user_ptr)
	if item.spawn == nil || g.bank < item.cost {
		return
	}
	shop_set_open(app, false)
	placement_begin(app, item)
}

// Draws text one small line per newline, starting at r's top left.
@(private = "file")
shop_lines_ui :: proc(app: ^engine.App, ui: ^engine.Ui, r: engine.Rect, text: string) {
	face := &app.render.font.faces[engine.FontSize.Small]
	y := r.y
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		engine.ui_text(app, ui, {r.x, y}, .Small, line, SHOP_TEXT_COLOR)
		y += face.line_height
	}
}

// Opens or closes the shop, freeing or recapturing the mouse.
shop_set_open :: proc(app: ^engine.App, open: bool) {
	g := (^Game)(app.world.user_ptr)
	g.shop_open = open
	if !open {
		g.shop_details = {}
	}
	engine.set_mouse_captured(app, !open)
}
