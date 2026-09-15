// Placing a bought item: its body follows the player's aim along the floor,
// the wheel turns it and a click drops it where it stands. Nothing is charged
// and nothing is activated until that click lands.
package main

import "../../../engine"
import "core:math"
import "core:math/linalg"

// How far from the player the floor may be aimed at, in world units.
PLACE_REACH :: 8.0
// How steeply the player must be looking down for the aim to reach the floor
// at all, as the downward part of a unit forward vector.
PLACE_MIN_PITCH :: 0.05
// Radians the item turns per wheel notch.
PLACE_YAW_STEP :: math.PI / 12
PLACE_PROMPT :: "[Click] Place  [Wheel] Rotate  [Esc] Cancel"

// The item the player is currently placing.
Placement :: struct {
	// Body being positioned, already in the world and drawing.
	entity:   engine.Entity,
	// What confirming it takes out of the bank.
	cost:     f32,
	// Run on the body once its placement is confirmed.
	activate: proc(app: ^engine.App, e: engine.Entity),
	// Radians about y, turned by the wheel.
	yaw:      f32,
	// True while the body stands on the floor clear of everything else, which
	// is what the confirming click needs.
	valid:    bool,
}

// Spawns item's body at the player's feet and hands it to the player to
// position. The caller has already checked the bank covers it.
placement_begin :: proc(app: ^engine.App, item: ShopItem) {
	g := (^Game)(app.world.user_ptr)
	pos: engine.Vec3
	if t := player_transform(app); t != nil {
		pos, _ = placement_target(t^)
	}
	g.placement = Placement {
		entity   = item.spawn(app, pos),
		cost     = item.cost,
		activate = item.activate,
	}
}

// Drops the item being placed and refunds nothing, since nothing was charged.
placement_cancel :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	p, ok := g.placement.?
	if !ok {
		return
	}
	engine.entity_destroy(app.world, p.entity)
	g.placement = nil
}

// Walks the item being placed along the player's aim, turns it with the wheel
// and confirms it on a click. Runs after interactor_system so its prompt is
// the one left standing.
placement_system :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	p, placing := &g.placement.?
	if !placing {
		return
	}
	player := player_transform(app)
	body := engine.pool_get(&app.world.transform, p.entity)
	if player == nil || body == nil {
		return
	}

	p.yaw += app.input.wheel * PLACE_YAW_STEP
	body.pos, p.valid = placement_target(player^)
	body.rot = linalg.quaternion_angle_axis_f32(p.yaw, engine.Vec3{0, 1, 0})
	p.valid = p.valid && !engine.aabb_overlaps_any(app.world, p.entity)
	g.prompt = PLACE_PROMPT

	if app.input.mouse_click && p.valid {
		g.bank -= p.cost
		if p.activate != nil {
			p.activate(app, p.entity)
		}
		g.placement = nil
	}
}

// Where on the floor the player is aiming, and whether that point is on the
// floor at all. An aim that misses the floor still returns a point out at
// PLACE_REACH, so the item stays in sight while it cannot be placed.
placement_target :: proc(player: engine.Transform) -> (engine.Vec3, bool) {
	forward := linalg.quaternion_mul_vector3(player.rot, engine.Vec3{0, 0, -1})
	if forward.y < -PLACE_MIN_PITCH {
		if dist := -player.pos.y / forward.y; dist <= PLACE_REACH {
			hit := player.pos + forward * dist
			on_floor := abs(hit.x) <= FLOOR_HALF && abs(hit.z) <= FLOOR_HALF
			return {hit.x, 0, hit.z}, on_floor
		}
	}
	flat := engine.Vec3{forward.x, 0, forward.z}
	if flat == {} {
		flat = {0, 0, -1}
	}
	ahead := player.pos + linalg.normalize(flat) * PLACE_REACH
	return {ahead.x, 0, ahead.z}, false
}

// The body being placed, or nil while nothing is. What the player must not
// collide with while walking it into position.
placement_entity :: proc(g: ^Game) -> Maybe(engine.Entity) {
	if p, ok := g.placement.?; ok {
		return p.entity
	}
	return nil
}

// The transform of the first player entity, or nil when there is none.
player_transform :: proc(app: ^engine.App) -> ^engine.Transform {
	g := (^Game)(app.world.user_ptr)
	for i in 0 ..< app.world.count {
		e := engine.Entity(i)
		if engine.pool_get(&g.player, e) == nil {
			continue
		}
		return engine.pool_get(&app.world.transform, e)
	}
	return nil
}
