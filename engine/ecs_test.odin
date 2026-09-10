package engine

import "core:testing"

@(test)
test_entity_create :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	a := entity_create(w)
	b := entity_create(w)

	testing.expect_value(t, a, Entity(0))
	testing.expect_value(t, b, Entity(1))
	testing.expect_value(t, w.count, u32(2))
	testing.expect(t, entity_alive(w, a))
	testing.expect(t, entity_alive(w, b))
}

@(test)
test_pool_add_get :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e := entity_create(w)
	pool_add(&w.transform, e, Transform{pos = {1, 2, 3}})

	got := pool_get(&w.transform, e)
	testing.expect(t, got != nil)
	testing.expect_value(t, got.pos, Vec3{1, 2, 3})
}

@(test)
test_pool_get_missing :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e := entity_create(w)
	testing.expect(t, pool_get(&w.transform, e) == nil)
}

@(test)
test_pool_get_returns_writable_pointer :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e := entity_create(w)
	pool_add(&w.transform, e, Transform{pos = {1, 0, 0}})

	pool_get(&w.transform, e).pos = {9, 9, 9}
	testing.expect_value(t, pool_get(&w.transform, e).pos, Vec3{9, 9, 9})
}

@(test)
test_pool_remove :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e := entity_create(w)
	pool_add(&w.transform, e, Transform{pos = {1, 2, 3}})
	pool_remove(&w.transform, e)

	testing.expect(t, pool_get(&w.transform, e) == nil)
}

@(test)
test_pools_are_per_entity :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	a := entity_create(w)
	b := entity_create(w)
	pool_add(&w.transform, a, Transform{pos = {1, 1, 1}})

	testing.expect(t, pool_get(&w.transform, a) != nil)
	testing.expect(t, pool_get(&w.transform, b) == nil)
}

@(test)
test_entity_destroy :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e := entity_create(w)
	pool_add(&w.transform, e, Transform{pos = {1, 2, 3}})
	entity_destroy(w, e)

	testing.expect(t, !entity_alive(w, e))
	testing.expect(t, pool_get(&w.transform, e) == nil)
}

@(test)
test_entity_destroy_leaves_others :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	a := entity_create(w)
	b := entity_create(w)
	pool_add(&w.transform, a, Transform{pos = {1, 1, 1}})
	pool_add(&w.transform, b, Transform{pos = {2, 2, 2}})
	entity_destroy(w, a)

	testing.expect(t, entity_alive(w, b))
	testing.expect_value(t, pool_get(&w.transform, b).pos, Vec3{2, 2, 2})
}

@(test)
test_ids_not_reused :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	a := entity_create(w)
	entity_destroy(w, a)
	b := entity_create(w)

	testing.expect_value(t, b, Entity(1))
}
