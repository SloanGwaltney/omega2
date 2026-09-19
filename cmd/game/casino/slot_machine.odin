// Placeholder slot machine: an imported cabinet with its screen on the front
// face. Its origin sits at the base so it can be placed straight onto the
// floor plane.
package main

import "../../../engine"
import "core:fmt"
import "core:math/rand"

// The machine's body, named by a scene so the mesh comes out of the importer
// rather than being written by hand. Embedded at compile time, so a renamed
// scene fails the build rather than the launch.
SLOT_JSON :: #load("scenes/slot_machine.json", string)

// The model the scene names, repeated here for the shop icon until an item
// carries its scene.
SLOT_MODEL_PATH :: "models/demo_slot.glb"

// A playable machine. Needs the drawable and Aabb slot_machine_spawn gives
// it, which is what the player's ray hits.
SlotMachine :: struct {
	// Percent of stakes this machine pays back, driven by its screen slider.
	rtp:    f32,
	// Patron playing this machine, or nil while it is free.
	patron: Maybe(engine.Entity),
}

// Spawns a playable slot machine standing on the floor at pos.
slot_machine_create :: proc(app: ^engine.App, pos: engine.Vec3) -> engine.Entity {
	e := slot_machine_spawn(app, pos)
	slot_machine_activate(app, e)
	return e
}

// Spawns a slot machine's body standing on the floor at pos. It draws and
// collides but cannot be played until slot_machine_activate runs, which is
// what placement wants while the machine is still being positioned.
slot_machine_spawn :: proc(app: ^engine.App, pos: engine.Vec3) -> engine.Entity {
	e, ok := engine.entity_from_json(app.world, SLOT_JSON, casino_component_loader)
	if !ok {
		panic("bad slot machine json")
	}
	// The scene has no position of its own, so move it here.
	engine.pool_get(&app.world.transform, e).pos = pos
	return e
}

// Makes a spawned machine playable.
slot_machine_activate :: proc(app: ^engine.App, e: engine.Entity) {
	g := (^Game)(app.world.user_ptr)
	engine.pool_add(
		&g.interactable,
		e,
		Interactable{on_hover = slot_machine_hover, on_interact = slot_machine_interact},
	)
	engine.pool_add(&g.slot_machine, e, SlotMachine{rtp = SLOT_MAX_RTP})
}

// Raises the slot machine's prompt while the player is aimed at it.
@(private = "file")
slot_machine_hover :: proc(app: ^engine.App, e: engine.Entity) {
	(^Game)(app.world.user_ptr).prompt = "[E] Play"
}

// Stake a single play costs.
SLOT_STAKE :: 10.0
// Multiple of the stake a winning play pays back.
SLOT_WIN_MULTIPLIER :: 2.0

// Rolls one play on slot and returns what it paid out, which is either the
// stake times SLOT_WIN_MULTIPLIER or nothing. The win chance is whatever
// makes the average payout match the machine's return to player.
slot_machine_play :: proc(slot: ^SlotMachine) -> f32 {
	win_chance := slot.rtp / 100 / SLOT_WIN_MULTIPLIER
	if rand.float32() < win_chance {
		return SLOT_STAKE * SLOT_WIN_MULTIPLIER
	}
	return 0
}

// Opens the machine's screen, which frees the mouse for its ui.
@(private = "file")
slot_machine_interact :: proc(app: ^engine.App, e: engine.Entity) {
	slot_machine_set_open(app, e)
}

// Opens machine's screen, or closes the open one when it is nil, and captures
// the mouse to match.
slot_machine_set_open :: proc(app: ^engine.App, machine: Maybe(engine.Entity)) {
	g := (^Game)(app.world.user_ptr)
	g.open_machine = machine
	engine.set_mouse_captured(app, machine == nil)
}

SLOT_PANEL_WIDTH :: 420.0
SLOT_PANEL_HEIGHT :: 260.0
SLOT_PANEL_PAD :: 24.0
SLOT_SLIDER_HEIGHT :: 24.0
SLOT_BUTTON_HEIGHT :: 48.0
SLOT_PANEL_COLOR :: engine.Vec4{0.08, 0.08, 0.1, 0.95}
SLOT_PANEL_TEXT_COLOR :: engine.Vec4{1, 1, 1, 1}
SLOT_MIN_RTP :: 80.0
SLOT_MAX_RTP :: 99.0

// Draws the open machine's screen: a return to player slider over a spin and
// a close button.
slot_machine_ui :: proc(app: ^engine.App, ui: ^engine.Ui) {
	g := (^Game)(app.world.user_ptr)
	machine, open := g.open_machine.?
	if !open {
		return
	}
	slot := engine.pool_get(&g.slot_machine, machine)
	panel := engine.Rect {
		f32(app.window.config.width) / 2 - SLOT_PANEL_WIDTH / 2,
		f32(app.window.config.height) / 2 - SLOT_PANEL_HEIGHT / 2,
		SLOT_PANEL_WIDTH,
		SLOT_PANEL_HEIGHT,
	}
	engine.ui_rect(ui, panel, SLOT_PANEL_COLOR)

	x := panel.x + SLOT_PANEL_PAD
	w := panel.w - SLOT_PANEL_PAD * 2
	y := panel.y + SLOT_PANEL_PAD
	label := fmt.tprintf("Return to player: %.0f%%", slot.rtp)
	y = engine.ui_text(app, ui, {x, y}, .Large, label, SLOT_PANEL_TEXT_COLOR).y + SLOT_PANEL_PAD
	engine.ui_slider(app, ui, {x, y, w, SLOT_SLIDER_HEIGHT}, &slot.rtp, SLOT_MIN_RTP, SLOT_MAX_RTP)

	y += SLOT_SLIDER_HEIGHT + SLOT_PANEL_PAD
	if engine.ui_button(app, ui, {x, y, w, SLOT_BUTTON_HEIGHT}, .Large, "Spin") {
		fmt.printfln("machine %d spun at %.0f%% rtp", machine, slot.rtp)
	}
	y += SLOT_BUTTON_HEIGHT + SLOT_PANEL_PAD
	if engine.ui_button(app, ui, {x, y, w, SLOT_BUTTON_HEIGHT}, .Large, "Leave") {
		slot_machine_set_open(app, nil)
	}
}
