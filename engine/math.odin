package engine

import "core:math"
import "core:math/linalg"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Quat :: quaternion128
Mat4 :: matrix[4, 4]f32

MAT4_IDENTITY :: Mat4(1)
QUAT_IDENTITY :: Quat(1)

// Position, rotation and scale of an entity in world space.
Transform :: struct {
	pos:   Vec3,
	rot:   Quat,
	scale: Vec3,
}

// A transform at the origin with no rotation and unit scale. Pools are zeroed,
// so a Transform must be seeded from this rather than left at its zero value.
transform_identity :: proc() -> Transform {
	return {pos = {0, 0, 0}, rot = QUAT_IDENTITY, scale = {1, 1, 1}}
}

// The model matrix for a transform. Builds T * R * S directly; the linalg
// version composes three matrices and multiplies them, which is two full 4x4
// multiplies of mostly zeroes.
transform_matrix :: proc(t: Transform) -> (m: Mat4) {
	q := t.rot
	xx, yy, zz := q.x * q.x, q.y * q.y, q.z * q.z
	xy, xz, yz := q.x * q.y, q.x * q.z, q.y * q.z
	wx, wy, wz := q.w * q.x, q.w * q.y, q.w * q.z

	m[0, 0] = (1 - 2 * (yy + zz)) * t.scale.x
	m[1, 0] = (2 * (xy + wz)) * t.scale.x
	m[2, 0] = (2 * (xz - wy)) * t.scale.x

	m[0, 1] = (2 * (xy - wz)) * t.scale.y
	m[1, 1] = (1 - 2 * (xx + zz)) * t.scale.y
	m[2, 1] = (2 * (yz + wx)) * t.scale.y

	m[0, 2] = (2 * (xz + wy)) * t.scale.z
	m[1, 2] = (2 * (yz - wx)) * t.scale.z
	m[2, 2] = (1 - 2 * (xx + yy)) * t.scale.z

	m[0, 3] = t.pos.x
	m[1, 3] = t.pos.y
	m[2, 3] = t.pos.z
	m[3, 3] = 1
	return
}

// Right handed view matrix for a camera at eye looking at target.
look_at :: proc(eye, target, up: Vec3) -> Mat4 {
	return linalg.matrix4_look_at_f32(eye, target, up)
}

// Right handed perspective projection mapping depth to 0..1, which is the
// clip space wgpu expects. core:math/linalg only offers the -1..1 form.
perspective :: proc(fov_y, aspect, near, far: f32) -> Mat4 {
	f := 1 / math.tan(0.5 * fov_y)
	m: Mat4
	m[0, 0] = f / aspect
	m[1, 1] = f
	m[2, 2] = far / (near - far)
	m[2, 3] = far * near / (near - far)
	m[3, 2] = -1
	return m
}
