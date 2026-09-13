// Player interaction: an interactor casts a ray forward from its own
// transform every frame and drives the interactable it is aimed at through
// that interactable's own callbacks.
package main

import "../../../engine"
import "core:math/linalg"

// Casts forward each frame and remembers what it is aimed at. Needs a
// Transform, which supplies both the ray origin and its direction.
Interactor :: struct {
	// How far the ray reaches, in world units.
	reach:  f32,
	// Entity aimed at, or nil when the ray hit nothing interactable.
	target: Maybe(engine.Entity),
}

// Marks an entity an interactor can aim at. Needs a Transform and an Aabb,
// which is what the ray is actually tested against. Both callbacks run
// before the ui callback, so they set the state the ui reads rather than
// drawing themselves.
Interactable :: struct {
	// Runs every frame an interactor is aimed at e, to raise its prompt.
	on_hover:    proc(app: ^engine.App, e: engine.Entity),
	// Runs on the frame the interact key goes down while aimed at e.
	on_interact: proc(app: ^engine.App, e: engine.Entity),
}

// Aims every interactor and runs its target's callbacks. Anything with an
// Aabb blocks the ray, so a wall hides the interactable behind it.
interactor_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	g.prompt = ""
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		interactor := engine.pool_get(&g.interactor, e)
		input := engine.pool_get(&g.input, e)
		transform := engine.pool_get(&w.transform, e)
		if interactor == nil || input == nil || transform == nil {
			continue
		}
		forward := linalg.quaternion_mul_vector3(transform.rot, engine.Vec3{0, 0, -1})
		interactor.target = nil
		hit, _, ok := engine.raycast(w, transform.pos, forward, interactor.reach, e)
		if !ok {
			continue
		}
		interactable := engine.pool_get(&g.interactable, hit)
		if interactable == nil {
			continue
		}
		interactor.target = hit
		if interactable.on_hover != nil {
			interactable.on_hover(app, hit)
		}
		if input.interact && interactable.on_interact != nil {
			interactable.on_interact(app, hit)
		}
	}
}
