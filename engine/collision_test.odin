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

// A box a unit tall and 4 long on x, so a yaw turn changes its footprint
// enough for the axis aligned hull and the real one to disagree.
@(private = "file")
BAR_BOX :: Aabb{{-2, 0, -0.1}, {2, 1, 0.1}}

@(private = "file")
yawed :: proc(pos: Vec3, yaw: f32) -> Transform {
	t := at(pos)
	t.rot = linalg.quaternion_angle_axis_f32(yaw, Vec3{0, 1, 0})
	return t
}

@(test)
test_obb2_from_centres_the_box_and_keeps_its_y_range :: proc(t: ^testing.T) {
	got := obb2_from(Aabb{{-1, 0, -0.5}, {1, 2, 0.5}}, at({3, 0, 4}))
	expect_near(t, got.center.x, 3)
	expect_near(t, got.center.y, 4)
	expect_near(t, got.half.x, 1)
	expect_near(t, got.half.y, 0.5)
	expect_near(t, got.min_y, 0)
	expect_near(t, got.max_y, 2)
}

@(test)
test_obb2_from_applies_scale :: proc(t: ^testing.T) {
	tr := at({0, 0, 0})
	tr.scale = {2, 3, 4}
	got := obb2_from(UNIT_BOX, tr)
	expect_near(t, got.half.x, 2)
	expect_near(t, got.half.y, 4)
	expect_near(t, got.max_y, 3)
}

@(test)
test_obb2_overlaps_boxes_sharing_space :: proc(t: ^testing.T) {
	a := obb2_from(UNIT_BOX, at({0, 0, 0}))
	b := obb2_from(UNIT_BOX, at({1.5, 0, 0}))
	testing.expect(t, obb2_overlaps(a, b))
}

@(test)
test_obb2_overlaps_separated_boxes :: proc(t: ^testing.T) {
	a := obb2_from(UNIT_BOX, at({0, 0, 0}))
	b := obb2_from(UNIT_BOX, at({2.5, 0, 0}))
	testing.expect(t, !obb2_overlaps(a, b))
}

// Boxes placed edge to edge only touch, which placement must allow.
@(test)
test_obb2_overlaps_touching_boxes_are_clear :: proc(t: ^testing.T) {
	a := obb2_from(UNIT_BOX, at({0, 0, 0}))
	b := obb2_from(UNIT_BOX, at({2, 0, 0}))
	testing.expect(t, !obb2_overlaps(a, b))
}

// Footprints that overlap are still clear when one box sits above the other.
@(test)
test_obb2_overlaps_boxes_stacked_out_of_reach :: proc(t: ^testing.T) {
	a := obb2_from(UNIT_BOX, at({0, 0, 0}))
	b := obb2_from(UNIT_BOX, at({0, 3, 0}))
	testing.expect(t, !obb2_overlaps(a, b))
}

// Turned a quarter turn the bar is only 0.2 wide on x, so the pair is clear
// even though their axis aligned hulls still overlap.
@(test)
test_obb2_overlaps_honours_yaw :: proc(t: ^testing.T) {
	a := obb2_from(BAR_BOX, at({0, 0, 0}))
	b := obb2_from(BAR_BOX, yawed({2.5, 0, 0}, math.PI / 2))
	testing.expect(t, !obb2_overlaps(a, b))
}

@(test)
test_obb2_overlaps_yawed_boxes_still_meet :: proc(t: ^testing.T) {
	a := obb2_from(BAR_BOX, at({0, 0, 0}))
	b := obb2_from(BAR_BOX, yawed({2, 0, 0}, math.PI / 2))
	testing.expect(t, obb2_overlaps(a, b))
}

@(test)
test_aabb_overlaps_any_finds_the_box_in_the_way :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	e := box_entity(w, UNIT_BOX, at({0, 0, 0}))
	box_entity(w, UNIT_BOX, at({1.5, 0, 0}))
	testing.expect(t, aabb_overlaps_any(w, e))
}

// The entity is skipped against itself, so a lone box is always clear.
@(test)
test_aabb_overlaps_any_ignores_itself :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	e := box_entity(w, UNIT_BOX, at({0, 0, 0}))
	testing.expect(t, !aabb_overlaps_any(w, e))
}

@(test)
test_aabb_overlaps_any_clear_of_everything :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	e := box_entity(w, UNIT_BOX, at({0, 0, 0}))
	box_entity(w, UNIT_BOX, at({5, 0, 0}))
	testing.expect(t, !aabb_overlaps_any(w, e))
}

// An entity without a box has no footprint to overlap with.
@(test)
test_aabb_overlaps_any_without_a_box :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	e := entity_create(w)
	pool_add(&w.transform, e, at({0, 0, 0}))
	box_entity(w, UNIT_BOX, at({0, 0, 0}))
	testing.expect(t, !aabb_overlaps_any(w, e))
}

@(test)
test_collide_sphere_ignores_the_named_entity :: proc(t: ^testing.T) {
	w := world_create()
	defer world_destroy(w)
	e := box_entity(w, UNIT_BOX, at({0, 0, 0}))
	expect_near_vec3(t, collide_sphere(w, {1.5, 0, 0}, 0.9, e), {1.5, 0, 0})
}
