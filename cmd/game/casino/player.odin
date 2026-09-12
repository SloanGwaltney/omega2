// The player: a first person entity that maps raw input to an intent, walks
// the xz plane and aims with the mouse.
package main

import "../../../engine"
import "core:math"
import "core:math/linalg"
import "vendor:sdl3"

// The game's state, reached from app.world.user_ptr. Pools are keyed by the
// same Entity ids the engine hands out.
Game :: struct {
	input:      engine.Pool(InputValues),
	player:     engine.Pool(Player),
	movement:   engine.Pool(Movement),
	mouse_look: engine.Pool(MouseLook),
}

GAME_SYSTEMS := [?]engine.System{player_input_system, player_look_system, player_move_system}

// Drops e from the game's pools. Hooked to world.on_destroy.
game_on_destroy :: proc(w: ^engine.World, e: engine.Entity) {
	g := (^Game)(w.user_ptr)
	engine.pool_remove(&g.input, e)
	engine.pool_remove(&g.player, e)
	engine.pool_remove(&g.movement, e)
	engine.pool_remove(&g.mouse_look, e)
}

// What an entity wants to do this frame, read off the raw device state.
InputValues :: struct {
	// WASD movement on the xz plane, normalized. x is right, y is forward.
	movement: engine.Vec2,
	// Mouse motion since the last frame, in pixels. x is right, y is down.
	look:     engine.Vec2,
}

// Marks the entity the player drives. Needs a Transform and InputValues,
// plus Movement to walk and MouseLook to turn.
Player :: struct {}

// Movement rate of an entity.
Movement :: struct {
	// World units travelled per second.
	speed: f32,
}

// Turn rate and accumulated aim of an entity steered by the mouse. The yaw
// and pitch are the source of truth for the entity's rotation, which
// player_look_system rewrites from them.
MouseLook :: struct {
	// Radians turned per pixel of mouse motion.
	sensitivity: f32,
	// Radians about y, counterclockwise from looking down -z.
	yaw:         f32,
	// Radians about x, clamped to PITCH_LIMIT either side of level.
	pitch:       f32,
}

// How far a player may look up or down, just short of straight up so the
// forward axis never degenerates.
PITCH_LIMIT :: math.PI / 2 - 0.01

// Maps this frame's keyboard and mouse into every InputValues component.
player_input_system :: proc(app: ^engine.App) {
	g := (^Game)(app.world.user_ptr)
	keys := app.input.keys

	movement: engine.Vec2
	if keys[sdl3.Scancode.D] do movement.x += 1
	if keys[sdl3.Scancode.A] do movement.x -= 1
	if keys[sdl3.Scancode.W] do movement.y += 1
	if keys[sdl3.Scancode.S] do movement.y -= 1
	if movement != {} {
		movement = linalg.normalize(movement)
	}

	for i in 0 ..< app.world.count {
		input := engine.pool_get(&g.input, engine.Entity(i))
		if input == nil {
			continue
		}
		input.movement = movement
		input.look = app.input.mouse_delta
	}
}

// Aims every player from its mouse motion, rebuilding the rotation as yaw
// then pitch so no roll can accumulate.
player_look_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		input := engine.pool_get(&g.input, e)
		look := engine.pool_get(&g.mouse_look, e)
		transform := engine.pool_get(&w.transform, e)
		if engine.pool_get(&g.player, e) == nil || input == nil || look == nil || transform == nil {
			continue
		}
		look.yaw -= input.look.x * look.sensitivity
		look.pitch = clamp(look.pitch - input.look.y * look.sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		transform.rot =
			linalg.quaternion_angle_axis_f32(look.yaw, engine.Vec3{0, 1, 0}) *
			linalg.quaternion_angle_axis_f32(look.pitch, engine.Vec3{1, 0, 0})
	}
}

// Walks every player along its own right and forward axes, flattened to the
// xz plane so looking up or down never lifts it off the floor.
player_move_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	dt := f32(w.delta_time) / 1e9
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		input := engine.pool_get(&g.input, e)
		movement := engine.pool_get(&g.movement, e)
		transform := engine.pool_get(&w.transform, e)
		if engine.pool_get(&g.player, e) == nil || input == nil || movement == nil || transform == nil {
			continue
		}
		if input.movement == {} {
			continue
		}
		right := linalg.quaternion_mul_vector3(transform.rot, engine.Vec3{1, 0, 0})
		forward := linalg.quaternion_mul_vector3(transform.rot, engine.Vec3{0, 0, -1})
		dir := engine.Vec3 {
			right.x * input.movement.x + forward.x * input.movement.y,
			0,
			right.z * input.movement.x + forward.z * input.movement.y,
		}
		if dir == {} {
			continue
		}
		transform.pos += linalg.normalize(dir) * movement.speed * dt
	}
}
