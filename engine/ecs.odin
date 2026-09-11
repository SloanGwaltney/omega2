package engine

// Direct-mapped ECS storage: every pool is indexed by entity id, with a
// parallel bool marking presence. This is the implementation until it stops
// scaling. When it does these optimization can help:
//   1. a free list + generation counters so ids are reused and stale handles
//      are detectable
//   2. bitsets in place of the `has`/`alive` bool arrays so systems can
//      intersect components 64 entities at a time
//   3. sparse sets for components held by only a small fraction of entities

MAX_ENTITIES :: 10_000

Entity :: distinct u32

/// Storage for a single component type, indexed by entity id.
Pool :: struct($T: typeid) {
	data: [MAX_ENTITIES]T,
	has:  [MAX_ENTITIES]bool,
}

// Owns every entity and component pool. Too large for the stack; heap
// allocate it.
World :: struct {
	alive:      [MAX_ENTITIES]bool,
	count:      u32,
	// Nanoseconds elapsed since the previous frame.
	delta_time: u64,
	transform:  Pool(Transform),
}

/// Allocates a zeroed world.
world_create :: proc(allocator := context.allocator) -> ^World {
	return new(World, allocator)
}

world_destroy :: proc(w: ^World, allocator := context.allocator) {
	free(w, allocator)
}

/// Returns a new entity. Ids are never reused, so this panics once
/// MAX_ENTITIES have been created.
entity_create :: proc(w: ^World) -> Entity {
	assert(w.count < MAX_ENTITIES, "out of entities")
	e := Entity(w.count)
	w.count += 1
	w.alive[e] = true
	return e
}

/// Marks e dead and drops its components. Must clear every pool in World.
entity_destroy :: proc(w: ^World, e: Entity) {
	w.alive[e] = false
	pool_remove(&w.transform, e)
}

entity_alive :: proc(w: ^World, e: Entity) -> bool {
	return w.alive[e]
}

/// Sets e's component to v and returns a pointer to it.
pool_add :: proc(p: ^Pool($T), e: Entity, v: T) -> ^T {
	p.data[e] = v
	p.has[e] = true
	return &p.data[e]
}

/// Returns a pointer to e's component, or nil if e has none.
pool_get :: proc(p: ^Pool($T), e: Entity) -> ^T {
	if !p.has[e] do return nil
	return &p.data[e]
}

pool_remove :: proc(p: ^Pool($T), e: Entity) {
	p.has[e] = false
}
