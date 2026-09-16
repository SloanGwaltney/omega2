package engine

import "core:encoding/json"
import "core:math/linalg"
import "core:testing"

@(private = "file")
expect_vec3 :: proc(t: ^testing.T, got, want: Vec3, loc := #caller_location) {
	testing.expect(t, linalg.length(got - want) < EPSILON, "expected near equal vectors", loc = loc)
}

@(test)
test_entity_from_json_transform :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(w, `[{"name": "engine:transform", "data": {"pos": [1, 2, 3], "scale": [2, 2, 2]}}]`)

	testing.expect(t, ok)
	got := pool_get(&w.transform, e)
	testing.expect(t, got != nil)
	expect_vec3(t, got.pos, {1, 2, 3})
	expect_vec3(t, got.scale, {2, 2, 2})
}

// A pool is zeroed, so a transform whose json leaves out scale has to come
// back at unit scale rather than collapsed to nothing.
@(test)
test_entity_from_json_transform_defaults :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(w, `[{"name": "engine:transform", "data": {"pos": [0, 1, 0]}}]`)

	testing.expect(t, ok)
	got := pool_get(&w.transform, e)
	expect_vec3(t, got.scale, {1, 1, 1})
	expect_vec3(t, linalg.quaternion_mul_vector3(got.rot, Vec3{0, 0, -1}), {0, 0, -1})
}

// Rotation is authored in euler degrees. A quarter turn about y has to swing
// forward onto -x, the same way the player's yaw does.
@(test)
test_entity_from_json_transform_rotation :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(w, `[{"name": "engine:transform", "data": {"rot": [0, 90, 0]}}]`)

	testing.expect(t, ok)
	got := pool_get(&w.transform, e)
	expect_vec3(t, linalg.quaternion_mul_vector3(got.rot, Vec3{0, 0, -1}), {-1, 0, 0})
}

@(test)
test_entity_from_json_camera_and_aabb :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(
		w,
		`[
			{"name": "engine:camera", "data": {"fov_y": 1.5, "near": 0.1, "far": 200}},
			{"name": "engine:aabb", "data": {"min": [-1, 0, -1], "max": [1, 2, 1]}}
		]`,
	)

	testing.expect(t, ok)
	cam := pool_get(&w.camera, e)
	testing.expect(t, cam != nil)
	testing.expect_value(t, cam.far, f32(200))
	box := pool_get(&w.aabb, e)
	testing.expect(t, box != nil)
	expect_vec3(t, box.max, {1, 2, 1})
}

@(test)
test_entity_from_json_empty_array :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(w, `[]`)

	testing.expect(t, ok)
	testing.expect(t, entity_alive(w, e))
}

@(test)
test_entity_from_json_rejects_malformed :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	_, ok := entity_from_json(w, `[{"name": `)

	testing.expect(t, !ok)
}

@(test)
test_entity_from_json_rejects_non_array :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	_, ok := entity_from_json(w, `{"name": "engine:transform"}`)

	testing.expect(t, !ok)
}

@(test)
test_entity_from_json_rejects_unnamed_component :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	_, ok := entity_from_json(w, `[{"data": {"pos": [1, 2, 3]}}]`)

	testing.expect(t, !ok)
}

@(test)
test_entity_from_json_rejects_unknown_without_loader :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	_, ok := entity_from_json(w, `[{"name": "casino:player"}]`)

	testing.expect(t, !ok)
}

// A component the engine cannot build must leave nothing behind, so the ones
// that already landed are rolled back with the entity.
@(test)
test_entity_from_json_failure_destroys_entity :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	e, ok := entity_from_json(
		w,
		`[
			{"name": "engine:transform", "data": {"pos": [1, 2, 3]}},
			{"name": "casino:player"}
		]`,
	)

	testing.expect(t, !ok)
	testing.expect(t, !entity_alive(w, Entity(0)))
	testing.expect(t, pool_get(&w.transform, Entity(0)) == nil)
	testing.expect_value(t, e, Entity(0))
}

// Ids are never reused, so a failed entity still spends one.
@(test)
test_entity_from_json_failure_spends_id :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	entity_from_json(w, `[{"name": "casino:player"}]`)

	testing.expect_value(t, entity_create(w), Entity(1))
}

@(private = "file")
LoaderRecord :: struct {
	name:  string,
	speed: f32,
	calls: int,
	fail:  bool,
}

@(private = "file")
record_loader :: proc(w: ^World, e: Entity, name: string, data: json.Value) -> bool {
	r := (^LoaderRecord)(w.user_ptr)
	r.name = name
	r.calls += 1
	if r.fail {
		return false
	}
	Movement :: struct {
		speed: f32,
	}
	m: Movement
	if !component_unmarshal(data, &m) {
		return false
	}
	r.speed = m.speed
	return true
}

// Engine components never reach the loader; everything else does, with its
// data intact.
@(test)
test_entity_from_json_loader_gets_game_components :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	record: LoaderRecord
	w.user_ptr = &record

	e, ok := entity_from_json(
		w,
		`[
			{"name": "engine:transform", "data": {"pos": [1, 2, 3]}},
			{"name": "casino:movement", "data": {"speed": 25}}
		]`,
		record_loader,
	)

	testing.expect(t, ok)
	testing.expect_value(t, record.calls, 1)
	testing.expect_value(t, record.name, "casino:movement")
	testing.expect_value(t, record.speed, f32(25))
	expect_vec3(t, pool_get(&w.transform, e).pos, {1, 2, 3})
}

@(test)
test_entity_from_json_loader_refusal_fails_entity :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)

	record := LoaderRecord {
		fail = true,
	}
	w.user_ptr = &record

	_, ok := entity_from_json(w, `[{"name": "casino:movement"}]`, record_loader)

	testing.expect(t, !ok)
	testing.expect(t, !entity_alive(w, Entity(0)))
}
