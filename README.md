# Omega 2

A small 3D engine in Odin and `casino`, the game built on it.

## Requirements

`SDL3.dll` must sit next to the executable. Copy it from your Odin
installation at `vendor/sdl3/SDL3.dll`.

## Fonts

`engine/fonts/mono.ttf` is Cascadia Mono, baked into the binary with `#load`
and packed into one atlas at startup. Every size in `FontSize` is packed into
that same atlas along with a white texel, so text and solid rects sample one
texture and the whole frame's ui stays a single draw call.

It is `ttf/static/CascadiaMono-Regular.ttf` from the upstream `v2407.24`
release, renamed but otherwise unmodified, under the SIL Open Font License 1.1
in `engine/fonts/LICENSE`. The OFL reserves the name "Cascadia Code", so a
modified build of the font may not ship under that name; this repo ships it
unmodified, which the license permits. Redistributing this repo, in source or
binary, must carry that LICENSE file with it.

Swapping the font is a file replacement: drop any `.ttf` at that path. The
`#load` is resolved at compile time, so a missing file is a build error rather
than a runtime one. Adding a size means one entry in `FontSize` and its pixel
height in `FONT_PIXEL_HEIGHTS`; if the atlas overflows, raise
`FONT_ATLAS_SIZE`.

## Engine and game

`engine/` is a general purpose library: window, wgpu renderer, ui, ecs storage,
input, collision, profiling. It knows nothing about any particular game.

`cmd/` holds the executables built on it. `cmd/game/casino` is the casino sim;
`cmd/demos/*` are harnesses like the cube stress test.

The seam is four fields on the engine, all set before `run_app`:

- `app.user_systems` — the game's systems, run every frame after the engine's
  `PRE_SYSTEMS` and before `UPDATE_SYSTEMS`.
- `app.world.user_ptr` — the game's own state, including its component pools.
  The engine only stores it; systems cast it back.
- `app.world.on_destroy` — called by `entity_destroy` after the engine pools
  are cleared, so the game can clear its own.
- `app.ui_callback` — a `proc(app: ^App, ui: ^Ui)` the engine's `ui_system`
  calls each frame to emit that frame's ui geometry. `casino_ui` is the
  game's.

Entity ids come from the engine, so a game pool keyed by `Entity` lines up
with the engine pools for free. `cmd/game/casino/main.odin` and `player.odin`
wire all four.

## Adding a component

A component is a plain struct stored in a `Pool` on either the engine's
`World` or the game's own state. Same `pool_add` / `pool_get` / `pool_remove`
either way; only where the pool lives and where it is cleared differ.

```odin
Health :: struct {
	current: f32,
	max:     f32,
}
```

**Game component** — the usual case:

1. Define the struct next to the code that uses it, in `cmd/game/casino`.
2. Add a `engine.Pool(T)` field to `Game` in `player.odin`.
3. Clear it in `game_on_destroy`.
4. To name it in json, add a `casino:` case to `casino_component_loader` in
   `cmd/game/casino/json.odin`.

**Engine component** — only for something the renderer or another engine
system reads, like `Transform` or `Aabb`:

1. Define the struct in `engine/`.
2. Add a `Pool(T)` field to `World` in `engine/ecs.odin`.
3. Clear it in `entity_destroy`.
4. To name it in json, add an `engine:` case to `component_from_json` in
   `engine/json.odin`.

Missing either clear leaves a destroyed entity holding stale components.

Pools are direct mapped: `data` is indexed by entity id with a parallel `has`
array, so every pool costs `MAX_ENTITIES * size_of(T)` whether or not anything
uses it. Keep components small; `Game` is heap allocated for the same reason
`World` is.

Attach with `pool_add(&g.health, e, Health{100, 100})`, read with `pool_get`,
which returns `nil` when the entity has none. Pools are zeroed, so a component
whose zero value is not a valid state needs a seeding helper — see
`transform_identity`.

## Entities from json

`engine.entity_from_json` builds an entity from an array of components:

```json
[
	{"name": "engine:transform", "data": {"pos": [0, 1.7, 5]}},
	{"name": "casino:movement", "data": {"speed": 25}}
]
```

Names are prefixed by who owns the component, which is what stops the engine
and a game from claiming the same one. The engine handles `engine:` itself and
hands everything else to the `ComponentLoader` passed alongside the document:

```odin
engine.entity_from_json(app.world, PLAYER_JSON, casino_component_loader)
```

A loader returns false for a name it does not own either. Any failure destroys
the entity, so nothing half built survives, though the id is still spent
because ids are never reused.

Two rules when adding a case:

- **Seed defaults before unmarshalling.** `component_unmarshal` leaves fields
  the json omits at whatever the struct already holds, which is how
  `engine:transform` comes back at unit scale. A component seeded from its zero
  value gets the zero value for anything left out.
- **Only plain data can be named.** `Drawable` holds gpu offsets and
  `Interactable` holds procs, so neither can come from a document. A mesh has
  to arrive as a game component that resolves an asset by name.

Rotation is the one field that is not a straight mapping: json carries euler
degrees, turned about y then x then z, because a quaternion is neither
writable by hand nor something `core:encoding/json` can unmarshal.

Games own file io, not the engine — `entity_from_json` takes a string and never
goes looking for one. The casino embeds its scenes at compile time:

```odin
PLAYER_JSON :: #load("scenes/player.json", string)
```

That keeps a renamed scene a build error instead of a launch one, and sidesteps
the working directory entirely. `#load_directory` is the next step up, and
runtime reads only become worth it once content should change without a
rebuild.

## Models from gltf

`engine.mesh_from_glb` turns binary gltf bytes into a `MeshData` — packed
`Vertex`, the `Index` slice and the `Aabb` the geometry fills:

```odin
DEMO_SLOT_GLB :: #load("models/demo_slot.glb")

mesh, ok := engine.mesh_from_glb(DEMO_SLOT_GLB)
```

`MeshData` is what a hand written mesh and an imported one both look like, so
either can feed `DrawableUpload`, `icon_bake` and the `Aabb` pool. Games own
file io here too: the loader takes bytes and the casino embeds the model with
`#load`, the same rule `entity_from_json` follows.

Export from Blender as **glTF Binary (.glb)** with its defaults. `+Y Up` and
CCW winding already match the camera and the unlit pipeline's `frontFace`.

Two things about the geometry that arrives:

- **Every mesh in the scene is flattened into one.** Node transforms are baked
  into the positions and all primitives are concatenated, so the hierarchy is
  gone by the time the mesh is returned.
- **Blender models about the origin, our convention is origin at base.** Lift a
  spawned model by `-bounds.min.y` or it sits half under the floor — see
  `demo_model_create`.

### What it does not support yet

Only what the unlit pipeline can draw is read, which is positions, uvs and each
primitive's `baseColorFactor` folded into the vertex color. So:

- **No materials, no textures, no lighting.** A material's base color becomes a
  flat vertex color, which means a model only shows shape where its materials
  differ. Give a test object two or three material slots, or it imports as a
  silhouette. Normals are ignored entirely; a `.Lit` layout and pipeline is the
  next step.
- **Colors arrive linear.** Blender writes `baseColorFactor` in linear space
  and nothing converts it, so it looks right only while the surface format is
  sRGB. `create_window` takes `caps.formats[0]` and does not check.
- **No skins or animations.** Nor sparse accessors, non-triangle topologies, or
  positions and uvs in any component type but f32. Each of those is refused
  rather than approximated, so a malformed or unsupported document returns
  false instead of drawing something wrong.
- **`.glb` only.** The text `.gltf` form would need external file resolution
  and base64 data uris, and every exporter can write `.glb`.

## Adding a system

A system is an `engine.System`, that is a `proc(app: ^App)`. Every system gets
the whole app, so game systems read engine components and vice versa.

**Game system**: write it in `cmd/game/casino` and add it to `GAME_SYSTEMS` in
`player.odin`. Order within the list is the order it runs.

```odin
damage_system :: proc(app: ^engine.App) {
	w := app.world
	g := (^Game)(w.user_ptr)
	for i in 0 ..< w.count {
		e := engine.Entity(i)
		health := engine.pool_get(&g.health, e)
		if health == nil {
			continue
		}
		// ...
	}
}
```

**Engine system**: add it to `UPDATE_SYSTEMS` or `RENDER_SYSTEMS` in
`engine/systems.odin`. Put it here only if it is game agnostic.

Each frame `run_app` runs `PRE_SYSTEMS` (timing and input), then
`app.user_systems`, then `UPDATE_SYSTEMS`, then `RENDER_SYSTEMS`, every list in
order.

Iterating means walking `0 ..< w.count` and skipping entities that lack the
component. Systems needing two components fetch both and skip when either is
`nil`, as `player_move_system` does.

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
		gpu_buffer_write(app, &app.render.models, data)
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
