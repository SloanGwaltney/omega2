// Patrons: cube customers that walk the floor, claim a free slot machine and
// stand at it. Their origin sits at the base so they rest on the floor plane.
package main

import "../../../engine"
import "core:math/linalg"
import "core:slice"

PATRON_HALF :: 0.3
PATRON_HEIGHT :: 1.2
PATRON_SPEED :: 2.0
// How far in front of a machine a patron stands once it arrives.
PATRON_SEAT_DISTANCE :: 0.9
// Distance at which a patron counts as arrived.
PATRON_ARRIVE_EPSILON :: 0.05

PATRON_COLOR :: engine.Vec4{0.2, 0.4, 0.75, 1}
PATRON_TOP_COLOR :: engine.Vec4{0.28, 0.5, 0.85, 1}

@(private = "file")
P :: PATRON_HALF
@(private = "file")
PH :: PATRON_HEIGHT

PATRON_VERTICES := [?]engine.Vertex {
	{pos = {-P, 0, P}, color = PATRON_COLOR},
	{pos = {P, 0, P}, color = PATRON_COLOR},
	{pos = {P, PH, P}, color = PATRON_COLOR},
	{pos = {-P, PH, P}, color = PATRON_COLOR},
	{pos = {-P, 0, -P}, color = PATRON_COLOR},
	{pos = {P, 0, -P}, color = PATRON_COLOR},
	{pos = {P, PH, -P}, color = PATRON_TOP_COLOR},
	{pos = {-P, PH, -P}, color = PATRON_TOP_COLOR},
}

PATRON_INDICES := [?]engine.Index {
	0, 1, 2, 0, 2, 3,
	1, 5, 6, 1, 6, 2,
	5, 4, 7, 5, 7, 6,
	4, 0, 3, 4, 3, 7,
	3, 2, 6, 3, 6, 7,
	4, 5, 1, 4, 1, 0,
}

// A customer walking to a machine. Needs a Transform, which is what
// patron_system walks.
Patron :: struct {
	// World units travelled per second.
	speed:   f32,
	// Machine this patron has claimed, or nil while it is still looking.
	machine: Maybe(engine.Entity),
	// True once the patron has reached its machine.
	arrived: bool,
}

// Spawns a patron standing on the floor at pos.
patron_create :: proc(app: ^engine.App, pos: engine.Vec3) -> engine.Entity {
	e := engine.entity_create(app.world)
	t := engine.transform_identity()
	t.pos = pos
	engine.pool_add(&app.world.transform, e, t)
	engine.pool_add(
		&app.world.drawable_upload,
		e,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(PATRON_VERTICES[:]),
			indices = PATRON_INDICES[:],
		},
	)
	g := (^Game)(app.world.user_ptr)
	engine.pool_add(&g.patron, e, Patron{speed = PATRON_SPEED})
	return e
}

// Where a patron stands to play machine, in front of its screen.
@(private = "file")
patron_seat :: proc(w: ^engine.World, machine: engine.Entity) -> engine.Vec3 {
	t := engine.pool_get(&w.transform, machine)
	front := linalg.quaternion_mul_vector3(t.rot, engine.Vec3{0, 0, 1})
	return t.pos + front * (SLOT_HALF_DEPTH + PATRON_SEAT_DISTANCE)
}

// Claims the first unoccupied machine for each free patron, then walks every
// claimed patron to its seat. Held while the menu is up.
patron_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	if g.menu_open {
		return
	}
	dt := f32(w.delta_time) / 1e9
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		patron := engine.pool_get(&g.patron, e)
		transform := engine.pool_get(&w.transform, e)
		if patron == nil || transform == nil {
			continue
		}
		machine, claimed := patron.machine.?
		if !claimed {
			machine, claimed = patron_claim(g, w, e)
			if !claimed {
				continue
			}
		}
		if patron.arrived {
			continue
		}
		seat := patron_seat(w, machine)
		to_seat := engine.Vec3{seat.x - transform.pos.x, 0, seat.z - transform.pos.z}
		distance := linalg.length(to_seat)
		if distance <= PATRON_ARRIVE_EPSILON {
			patron.arrived = true
			continue
		}
		step := min(patron.speed * dt, distance)
		transform.pos += to_seat / distance * step
	}
}

// Claims the first machine no other patron holds for e, recording the claim
// on both ends.
@(private = "file")
patron_claim :: proc(
	g: ^Game,
	w: ^engine.World,
	e: engine.Entity,
) -> (
	machine: engine.Entity,
	ok: bool,
) {
	for i in 0 ..< w.count {
		candidate := engine.Entity(i)
		slot := engine.pool_get(&g.slot_machine, candidate)
		if slot == nil || slot.patron != nil {
			continue
		}
		slot.patron = e
		engine.pool_get(&g.patron, e).machine = candidate
		return candidate, true
	}
	return 0, false
}
