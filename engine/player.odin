package engine

import "core:math/linalg"

// Marks the entity the player drives. Needs a Transform, InputValues and
// Movement to move.
Player :: struct {}

// Movement rate of an entity.
Movement :: struct {
	// World units travelled per second.
	speed: f32,
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
