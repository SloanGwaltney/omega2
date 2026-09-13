package engine

import "core:math"
import "core:math/linalg"
import "core:testing"

@(private = "file")
UNIT_BOX :: Aabb{{-1, -1, -1}, {1, 1, 1}}

@(private = "file")
expect_near :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expect(t, abs(got - want) < EPSILON, "expected near equal floats", loc = loc)
}

@(private = "file")
expect_near_vec3 :: proc(t: ^testing.T, got, want: Vec3, loc := #caller_location) {
	testing.expect(t, linalg.length(got - want) < EPSILON, "expected near equal vectors", loc = loc)
}

// Spawns an entity with a box and a transform, which is what both queries need.
@(private = "file")
box_entity :: proc(w: ^World, box: Aabb, t: Transform) -> Entity {
	e := entity_create(w)
	pool_add(&w.aabb, e, box)
	pool_add(&w.transform, e, t)
	return e
}

@(private = "file")
at :: proc(pos: Vec3) -> Transform {
	t := transform_identity()
	t.pos = pos
	return t
}

@(test)
test_aabb_closest_point_clamps_outside :: proc(t: ^testing.T) {
	testing.expect_value(t, aabb_closest_point(UNIT_BOX, {5, -3, 0.5}), Vec3{1, -1, 0.5})
}

@(test)
test_aabb_closest_point_inside_is_itself :: proc(t: ^testing.T) {
	testing.expect_value(t, aabb_closest_point(UNIT_BOX, {0.5, -0.25, 0}), Vec3{0.5, -0.25, 0})
}

@(test)
test_ray_aabb_hits_from_outside :: proc(t: ^testing.T) {
	d, ok := ray_aabb(UNIT_BOX, {-5, 0, 0}, {1, 0, 0})
	testing.expect(t, ok)
	expect_near(t, d, 4)
}

// A ray starting inside has already entered, so it enters at 0 rather than at
// the far face.
@(test)
test_ray_aabb_inside_is_zero :: proc(t: ^testing.T) {
	d, ok := ray_aabb(UNIT_BOX, {0, 0, 0}, {1, 0, 0})
	testing.expect(t, ok)
	expect_near(t, d, 0)
}

@(test)
test_ray_aabb_misses :: proc(t: ^testing.T) {
	_, ok := ray_aabb(UNIT_BOX, {-5, 3, 0}, {1, 0, 0})
	testing.expect(t, !ok)
}

// The box is behind the origin, so every entry distance is negative and the
// clamp at 0 must not turn that into a hit.
@(test)
test_ray_aabb_behind_origin_misses :: proc(t: ^testing.T) {
	_, ok := ray_aabb(UNIT_BOX, {5, 0, 0}, {1, 0, 0})
	testing.expect(t, !ok)
}

// A direction with a zero component cannot be divided into a slab, so those
// axes are tested as a plain containment check.
@(test)
test_ray_aabb_parallel_inside_slab_hits :: proc(t: ^testing.T) {
	d, ok := ray_aabb(UNIT_BOX, {-5, 0.5, 0.5}, {1, 0, 0})
	testing.expect(t, ok)
	expect_near(t, d, 4)
}

@(test)
test_ray_aabb_parallel_outside_slab_misses :: proc(t: ^testing.T) {
	_, ok := ray_aabb(UNIT_BOX, {-5, 2, 0}, {1, 0, 0})
	testing.expect(t, !ok)
}

@(test)
test_collide_sphere_pushed_clear_of_face :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({0, 0, 0}))

	// Centre 0.5 outside the +x face, with a radius that overlaps it by 0.4.
	got := collide_sphere(w, {1.5, 0, 0}, 0.9)
	expect_near_vec3(t, got, {1.9, 0, 0})
}

// The push is along the surface normal, so motion across the face survives it.
@(test)
test_collide_sphere_keeps_tangential_position :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({0, 0, 0}))

	got := collide_sphere(w, {1.5, 0.3, -0.2}, 0.9)
	expect_near_vec3(t, got, {1.9, 0.3, -0.2})
}

@(test)
test_collide_sphere_leaves_clear_centre :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({0, 0, 0}))

	expect_near_vec3(t, collide_sphere(w, {5, 0, 0}, 0.5), {5, 0, 0})
}

// A centre inside the box has no surface normal to push along, so it is left
// where it is rather than snapped to an arbitrary face.
@(test)
test_collide_sphere_inside_is_untouched :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({0, 0, 0}))

	expect_near_vec3(t, collide_sphere(w, {0, 0, 0}, 0.5), {0, 0, 0})
}

@(test)
test_collide_sphere_skips_entities_without_both :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	no_transform := entity_create(w)
	pool_add(&w.aabb, no_transform, UNIT_BOX)
	no_box := entity_create(w)
	pool_add(&w.transform, no_box, at({0, 0, 0}))

	expect_near_vec3(t, collide_sphere(w, {0.5, 0, 0}, 1), {0.5, 0, 0})
}

// The box is stored in local space, so the entity's position moves it.
@(test)
test_collide_sphere_uses_entity_transform :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({10, 0, 0}))

	expect_near_vec3(t, collide_sphere(w, {8.5, 0, 0}, 0.9), {8.1, 0, 0})
}

@(test)
test_raycast_returns_nearest :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	far := box_entity(w, UNIT_BOX, at({10, 0, 0}))
	near := box_entity(w, UNIT_BOX, at({5, 0, 0}))

	hit, dist, ok := raycast(w, {0, 0, 0}, {1, 0, 0}, 100, MAX_ENTITIES)
	testing.expect(t, ok)
	testing.expect_value(t, hit, near)
	testing.expect(t, hit != far)
	expect_near(t, dist, 4)
}

@(test)
test_raycast_skips_ignored :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	near := box_entity(w, UNIT_BOX, at({5, 0, 0}))
	far := box_entity(w, UNIT_BOX, at({10, 0, 0}))

	hit, dist, ok := raycast(w, {0, 0, 0}, {1, 0, 0}, 100, near)
	testing.expect(t, ok)
	testing.expect_value(t, hit, far)
	expect_near(t, dist, 9)
}

@(test)
test_raycast_respects_max_dist :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({10, 0, 0}))

	_, _, ok := raycast(w, {0, 0, 0}, {1, 0, 0}, 5, MAX_ENTITIES)
	testing.expect(t, !ok)
}

@(test)
test_raycast_misses :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	box_entity(w, UNIT_BOX, at({5, 0, 0}))

	_, _, ok := raycast(w, {0, 0, 0}, {0, 1, 0}, 100, MAX_ENTITIES)
	testing.expect(t, !ok)
}

// The ray is moved into the box's local space, so a rotated entity is tested
// against its rotated faces rather than an axis aligned hull around them.
@(test)
test_raycast_hits_rotated_box :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	tr := at({5, 0, 0})
	tr.rot = linalg.quaternion_angle_axis_f32(math.PI / 4, Vec3{0, 1, 0})
	// A slab half as deep as it is wide, turned 45 degrees about y.
	e := box_entity(w, Aabb{{-1, -1, -0.5}, {1, 1, 0.5}}, tr)

	hit, dist, ok := raycast(w, {0, 0, 0}, {1, 0, 0}, 100, MAX_ENTITIES)
	testing.expect(t, ok)
	testing.expect_value(t, hit, e)
	// Along the centreline the ray meets the turned face at the slab's half
	// depth divided by sin(45), not at the wider axis aligned hull around it.
	expect_near(t, dist, 5 - 0.5 * math.SQRT_TWO)
}

// Scale is baked into the local space too, so the returned distance stays in
// world units.
@(test)
test_raycast_distance_is_world_units_under_scale :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	tr := at({10, 0, 0})
	tr.scale = {3, 1, 1}
	box_entity(w, UNIT_BOX, tr)

	_, dist, ok := raycast(w, {0, 0, 0}, {1, 0, 0}, 100, MAX_ENTITIES)
	testing.expect(t, ok)
	expect_near(t, dist, 7)
}
