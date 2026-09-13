package engine

import "core:math"
import "core:math/linalg"
import "core:testing"

EPSILON :: 1e-5

@(private = "file")
expect_vec3 :: proc(t: ^testing.T, got, want: Vec3, loc := #caller_location) {
	testing.expect(t, linalg.length(got - want) < EPSILON, "expected near equal vectors", loc = loc)
}

@(private = "file")
mat_point :: proc(m: Mat4, p: Vec3) -> Vec3 {
	v := m * Vec4{p.x, p.y, p.z, 1}
	return v.xyz
}

@(test)
test_transform_matrix_identity :: proc(t: ^testing.T) {
	m := transform_matrix(transform_identity())
	expect_vec3(t, mat_point(m, {1, 2, 3}), {1, 2, 3})
}

@(test)
test_transform_matrix_translation :: proc(t: ^testing.T) {
	tr := transform_identity()
	tr.pos = {5, -2, 1}
	m := transform_matrix(tr)
	expect_vec3(t, mat_point(m, {1, 1, 1}), {6, -1, 2})
}

@(test)
test_transform_matrix_scale :: proc(t: ^testing.T) {
	tr := transform_identity()
	tr.scale = {2, 3, 4}
	m := transform_matrix(tr)
	expect_vec3(t, mat_point(m, {1, 1, 1}), {2, 3, 4})
}

@(test)
test_transform_matrix_rotation :: proc(t: ^testing.T) {
	tr := transform_identity()
	tr.rot = linalg.quaternion_from_euler_angles_f32(0, math.PI / 2, 0, .XYZ)
	m := transform_matrix(tr)
	// A quarter turn about y sends +x to -z.
	expect_vec3(t, mat_point(m, {1, 0, 0}), {0, 0, -1})
}

@(test)
test_transform_matrix_matches_linalg :: proc(t: ^testing.T) {
	tr := Transform {
		pos   = {1, -2, 3},
		rot   = linalg.quaternion_from_euler_angles_f32(0.3, -0.7, 1.1, .XYZ),
		scale = {2, 0.5, 1.5},
	}
	got := transform_matrix(tr)
	want := linalg.matrix4_from_trs_f32(tr.pos, tr.rot, tr.scale)
	for c in 0 ..< 4 {
		for r in 0 ..< 4 {
			testing.expect(t, abs(got[r, c] - want[r, c]) < EPSILON, "matrices differ")
		}
	}
}

@(test)
test_perspective_depth_range :: proc(t: ^testing.T) {
	near, far: f32 = 0.1, 100
	m := perspective(math.PI / 3, 1.5, near, far)

	on_near := m * Vec4{0, 0, -near, 1}
	on_far := m * Vec4{0, 0, -far, 1}

	testing.expect(t, abs(on_near.z / on_near.w - 0) < EPSILON, "near plane should map to 0")
	testing.expect(t, abs(on_far.z / on_far.w - 1) < EPSILON, "far plane should map to 1")
}

@(test)
test_perspective_aspect_and_fov :: proc(t: ^testing.T) {
	fov_y: f32 = math.PI / 2
	aspect: f32 = 2
	m := perspective(fov_y, aspect, 0.1, 100)

	// At z = -1 the top of the frustum is at y = tan(fov_y/2), mapping to 1.
	top := m * Vec4{0, math.tan(fov_y / 2), -1, 1}
	testing.expect(t, abs(top.y / top.w - 1) < EPSILON, "top of frustum should map to 1")

	// The same extent scaled by the aspect ratio maps to 1 in x.
	right := m * Vec4{math.tan(fov_y / 2) * aspect, 0, -1, 1}
	testing.expect(t, abs(right.x / right.w - 1) < EPSILON, "right of frustum should map to 1")

	// w carries the view space depth, so perspective divide works.
	testing.expect(t, abs(top.w - 1) < EPSILON, "w should be -z")
}

@(test)
test_transform_point_inverse_round_trip :: proc(t: ^testing.T) {
	tr := Transform {
		pos   = {1, -2, 3},
		rot   = linalg.quaternion_from_euler_angles_f32(0.3, -0.7, 1.1, .XYZ),
		scale = {2, 0.5, 1.5},
	}
	p := Vec3{4, -1, 0.25}
	expect_vec3(t, transform_point_inverse(tr, transform_point(tr, p)), p)
}

// A direction carries no position, so the translation must not be applied to
// it the way transform_point_inverse applies it to a point.
@(test)
test_transform_vector_inverse_ignores_translation :: proc(t: ^testing.T) {
	tr := Transform {
		rot   = linalg.quaternion_from_euler_angles_f32(0.3, -0.7, 1.1, .XYZ),
		scale = {2, 0.5, 1.5},
	}
	moved := tr
	moved.pos = {9, -4, 2}
	expect_vec3(t, transform_vector_inverse(tr, {1, 0, 0}), transform_vector_inverse(moved, {1, 0, 0}))
}

// The pair leaves a ray parameter unchanged, which is what lets ray_aabb
// report world distances from a test done in local space.
@(test)
test_transform_vector_inverse_preserves_ray_parameter :: proc(t: ^testing.T) {
	tr := Transform {
		pos   = {1, -2, 3},
		rot   = linalg.quaternion_from_euler_angles_f32(0.3, -0.7, 1.1, .XYZ),
		scale = {2, 0.5, 1.5},
	}
	origin, dir, distance := Vec3{5, 1, -2}, linalg.normalize(Vec3{1, 2, 3}), f32(4)

	local := transform_point_inverse(tr, origin) + transform_vector_inverse(tr, dir) * distance
	expect_vec3(t, transform_point(tr, local), origin + dir * distance)
}

@(test)
test_ortho_screen_maps_window_corners :: proc(t: ^testing.T) {
	m := ortho_screen(800, 600)

	top_left := m * Vec4{0, 0, 0, 1}
	bottom_right := m * Vec4{800, 600, 0, 1}

	expect_vec3(t, top_left.xyz, {-1, 1, 0})
	expect_vec3(t, bottom_right.xyz, {1, -1, 0})
}
