package engine

import "core:mem"
import "core:mem/virtual"

WORLD_ARENA_SIZE :: 100 * mem.Megabyte

App :: struct {
	world_arena: virtual.Arena,
	world:       ^World,
}

/// Allocates the app with a 100MB world arena and a world living on it.
new_app :: proc() -> ^App {
	app := new(App)
	if err := virtual.arena_init_static(&app.world_arena, WORLD_ARENA_SIZE); err != nil {
		panic("failed to reserve world arena")
	}
	app.world = world_create(virtual.arena_allocator(&app.world_arena))
	return app
}

/// Releases the world arena and everything on it, including the world.
delete_app :: proc(app: ^App) {
	virtual.arena_destroy(&app.world_arena)
	free(app)
}

start_app :: proc(app: ^App) {}
