package engine

import "core:math"
import "core:math/linalg"

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

// Aims every player from its mouse motion, rebuilding the rotation as yaw
// then pitch so no roll can accumulate.
player_look_system :: proc(app: ^App) {
	w := app.world
	for i in 0 ..< w.count {
		e := Entity(i)
		input := pool_get(&w.input, e)
		look := pool_get(&w.mouse_look, e)
		transform := pool_get(&w.transform, e)
		if pool_get(&w.player, e) == nil || input == nil || look == nil || transform == nil {
			continue
		}
		look.yaw -= input.look.x * look.sensitivity
		look.pitch = clamp(look.pitch - input.look.y * look.sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		transform.rot =
			linalg.quaternion_angle_axis_f32(look.yaw, Vec3{0, 1, 0}) *
			linalg.quaternion_angle_axis_f32(look.pitch, Vec3{1, 0, 0})
	}
}

// Walks every player along its own right and forward axes, flattened to the
// xz plane so looking up or down never lifts it off the floor.
player_move_system :: proc(app: ^App) {
	w := app.world
	dt := f32(w.delta_time) / 1e9
	for i in 0 ..< w.count {
		e := Entity(i)
		input := pool_get(&w.input, e)
		movement := pool_get(&w.movement, e)
		transform := pool_get(&w.transform, e)
		if pool_get(&w.player, e) == nil || input == nil || movement == nil || transform == nil {
			continue
		}
		if input.movement == {} {
			continue
		}
		right := linalg.quaternion_mul_vector3(transform.rot, Vec3{1, 0, 0})
		forward := linalg.quaternion_mul_vector3(transform.rot, Vec3{0, 0, -1})
		dir := Vec3 {
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
