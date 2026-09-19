// The buy menu: b opens a grid of the things the casino can buy, each cell a
// placeholder picture, a description and buy and details buttons. Buying does
// nothing yet, and details swaps the cell to its stats until back is clicked.
// The items themselves come from shop.json.
package main

import "../../../engine"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "vendor:sdl3"

// The item list, embedded at compile time so a renamed file fails the build
// rather than the launch.
SHOP_JSON :: #load("scenes/shop.json", string)
// How many items the menu can hold, the size of the per cell state the game
// carries. Loading more than this is a content bug.
SHOP_MAX_ITEMS :: 12

// Makes a placed body do its job, run once its placement is confirmed.
ShopActivate :: proc(app: ^engine.App, e: engine.Entity)

// One thing on offer. An item without a scene cannot be bought yet.
ShopItem :: struct {
	name:        string,
	description: string,
	// What buying one takes out of the bank.
	price:       f32,
	// Path of the scene buying one builds, empty while the item has none. Also
	// where the cell's picture comes from.
	scene:       string,
	// Picture of the item's scene shown in its cell, nil until it is baked.
	icon:        ^engine.Texture,
	activate:    ShopActivate,
}

// The items on offer, filled by shop_load.
shop_items: []ShopItem

// An item as shop.json writes it. Behavior names the code that makes the item
// work, since a proc cannot come from json.
@(private = "file")
ShopItemJson :: struct {
	name:        string,
	description: string,
	price:       f32,
	scene:       string,
	behavior:    string,
}

// The proc a behavior name stands for, nil for an item that names none. Panics
// on a name no one owns, which is a content bug worth failing loudly for.
@(private = "file")
shop_behavior :: proc(name: string) -> ShopActivate {
	switch name {
	case "":
		return nil
	case "slots":
		return slot_machine_activate
	}
	fmt.panicf("unknown shop behavior %q", name)
}

// Fills shop_items from shop.json. Run once at startup, before the icons are
// baked.
shop_load :: proc() {
	specs: []ShopItemJson
	if json.unmarshal(transmute([]byte)SHOP_JSON, &specs) != nil {
		panic("bad shop json")
	}
	defer delete(specs)
	if len(specs) > SHOP_MAX_ITEMS {
		fmt.panicf("shop has %d items, at most %d fit", len(specs), SHOP_MAX_ITEMS)
	}
	shop_items = make([]ShopItem, len(specs))
	for spec, i in specs {
		shop_items[i] = ShopItem {
			name        = spec.name,
			description = spec.description,
			price       = spec.price,
			scene       = spec.scene,
			activate    = shop_behavior(spec.behavior),
		}
	}
}

// Baked at twice the picture's size, in its aspect so it is not stretched.
SHOP_ICON_WIDTH :: u32((SHOP_CELL_WIDTH - SHOP_TEXT_GAP * 2) * 2)
SHOP_ICON_HEIGHT :: u32(SHOP_PICTURE_HEIGHT * 2)

// Renders the model of every item that has a scene into its shop icon. Run
// once at startup, before the first frame.
shop_bake_icons :: proc(app: ^engine.App) {
	for &item in shop_items {
		if item.scene == "" {
			continue
		}
		path := scene_model_path(item.scene)
		if path == "" {
			continue
		}
		mesh, ok := model_mesh(path)
		if !ok {
			fmt.panicf("unknown model %q", path)
		}
		item.icon = new(engine.Texture)
		item.icon^ = engine.icon_bake(
			app,
			item.name,
			.Unlit,
			mesh.data,
			mesh.indices,
			mesh.bounds,
			SHOP_ICON_WIDTH,
			SHOP_ICON_HEIGHT,
		)
	}
}

// Releases the baked icons and the item list.
shop_unload :: proc() {
	for &item in shop_items {
		if item.icon == nil {
			continue
		}
		engine.delete_texture(item.icon)
		free(item.icon)
		item.icon = nil
	}
	delete(shop_items)
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
	rows := f32((len(shop_items) + SHOP_COLS - 1) / SHOP_COLS)
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
	for item, i in shop_items {
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
		shop_lines_ui(app, ui, {x, y, w, 0}, fmt.tprintf("Cost $%.0f", item.price))
	} else {
		picture := engine.Rect{x, y, w, SHOP_PICTURE_HEIGHT}
		engine.ui_rect(ui, picture, SHOP_PICTURE_COLOR)
		if item.icon != nil {
			engine.ui_image(ui, picture, item.icon)
		}
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
	if item.scene == "" || g.bank < item.price {
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
