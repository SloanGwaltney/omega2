// Player interaction: an interactor casts a ray forward from its own
// transform every frame and tracks the interactable it is aimed at.
package main

import "../../../engine"
import "core:fmt"
import "core:math/linalg"

// Casts forward each frame and remembers what it is aimed at. Needs a
// Transform, which supplies both the ray origin and its direction.
Interactor :: struct {
	// How far the ray reaches, in world units.
	reach:  f32,
	// Entity aimed at last frame, or nil when nothing was.
	target: Maybe(engine.Entity),
}

// Marks an entity an interactor can aim at. Needs a Transform and an Aabb,
// which is what the ray is actually tested against.
Interactable :: struct {}

// Aims every interactor and logs whenever its target changes. Anything with
// an Aabb blocks the ray, so a wall hides the interactable behind it.
interactor_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		interactor := engine.pool_get(&g.interactor, e)
		transform := engine.pool_get(&w.transform, e)
		if interactor == nil || transform == nil {
			continue
		}
		forward := linalg.quaternion_mul_vector3(transform.rot, engine.Vec3{0, 0, -1})
		target: Maybe(engine.Entity)
		if hit, _, ok := engine.raycast(w, transform.pos, forward, interactor.reach, e); ok {
			if engine.pool_get(&g.interactable, hit) != nil {
				target = hit
			}
		}
		if target == interactor.target {
			continue
		}
		interactor.target = target
		if hit, ok := target.?; ok {
			fmt.printfln("looking at interactable %d", hit)
		} else {
			fmt.println("looking at nothing")
		}
	}
}
