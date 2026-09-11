# Omega 2

A fun simple FPS game and engine

## Requirements

`SDL3.dll` must sit next to the executable. Copy it from your Odin
installation at `vendor/sdl3/SDL3.dll`.

## Adding a component

A component is a plain struct stored in a `Pool` on the `World`. Three edits:

1. Define the struct next to the code that uses it.
2. Add a `Pool(T)` field to `World` in `engine/ecs.odin`.
3. Clear it in `entity_destroy` — every pool must be listed there or a
   destroyed entity keeps stale components.

```odin
Health :: struct {
	current: f32,
	max:     f32,
}
```

Pools are direct mapped: `data` is indexed by entity id with a parallel `has`
array, so every pool costs `MAX_ENTITIES * size_of(T)` whether or not anything
uses it. Keep components small.

Attach with `pool_add(&w.health, e, Health{100, 100})`, read with `pool_get`,
which returns `nil` when the entity has none. Pools are zeroed, so a component
whose zero value is not a valid state needs a seeding helper — see
`transform_identity`.

## Adding a system

A system is a `proc(app: ^App)` listed in `engine/systems.odin`. Add it to
`UPDATE_SYSTEMS` or `RENDER_SYSTEMS`; the split is cosmetic grouping, each
frame runs every entry of both in order.

```odin
damage_system :: proc(app: ^App) {
	w := app.world
	for i in 0 ..< w.count {
		e := Entity(i)
		health := pool_get(&w.health, e)
		if health == nil {
			continue
		}
		// ...
	}
}
```

Iterating means walking `0 ..< w.count` and skipping entities that lack the
component. Systems needing two components fetch both and skip when either is
`nil`, as `camera_view_proj` does.

`app.user_update` runs once per frame before either list. It is not an
engine/game seam — the engine is purpose built for this game and no such seam
exists yet. It is an escape hatch so integration level harnesses can drive the
world without their setup being baked into the engine: the cube stress demo
spawns and spins its cubes from there, which keeps a performance test out of
`engine/`.

## Performance testing

Timing lives in `engine/profile.odin` and compiles to nothing unless asked for
at build time.

To time a region, call `zone_begin` at the top of the scope you want measured.
It stops when that scope exits, so wrap a sub-region in its own block:

```odin
some_system :: proc(app: ^App) {
	zone_begin(.SomeSystem)
	// ...
	{
		zone_begin(.SomeUpload)
		gpu_buffer_write(app, &app.models, data)
	}
}
```

Adding a zone means three edits in `engine/profile.odin`: the `Zone` enum, a
`PROFILE_<ZONE>` config const defaulting to `PROFILE`, and its `zone_enabled`
entry.

Build with zones on:

```
odin build cmd/demos/cube_stress -o:speed -define:PROFILE=true -out:demo.exe
odin build cmd/demos/cube_stress -o:speed -define:PROFILE_MODEL_UPLOAD=true -out:demo.exe
```

`PROFILE=true` enables every zone; a single `PROFILE_<ZONE>` enables just that
one. `profile_report_system` prints each enabled zone's average and worst case
every `PROFILE_REPORT_FRAMES` frames, then clears the accumulators.

Two things to hold to when reading the numbers:

- **Always build `-o:speed`.** Unoptimized builds emit every bounds check and
  skip inlining; they have been worth 3x on hot paths here, which swamps
  whatever you are trying to measure.
- **Compare two builds, not one build against a memory.** Build the before and
  after source with identical flags, run the same scene, and compare the
  averages. Keeping an unchanged zone in the run as a control tells you whether
  the machine is quiet enough to trust the delta.

Ignore the `fps` line in the demos. It is a vanity number: satisfying to watch
climb, but past about 1000 it carries far less meaning than the zone timings. It
is `1/dt` of a single frame, so taking the reciprocal of an already tiny number
turns a 0.1ms wobble into a swing of hundreds of apparent frames per second.
Read the zone averages.
