package engine

import "core:math/linalg"

// Projection settings for a camera entity. The entity's Transform supplies
// the view; an entity needs both to be rendered from.
Camera :: struct {
	fov_y: f32,
	near:  f32,
	far:   f32,
}

// View projection matrix of the first entity holding a Camera and a Transform.
// Panics when there is none, because nothing could be drawn without one.
camera_view_proj :: proc(app: ^App) -> Mat4 {
	w := app.world
	aspect := f32(app.window.config.width) / f32(app.window.config.height)
	for i in 0 ..< w.count {
		e := Entity(i)
		camera := pool_get(&w.camera, e)
		transform := pool_get(&w.transform, e)
		if camera == nil || transform == nil {
			continue
		}
		view := linalg.matrix4_inverse(linalg.matrix4_from_trs_f32(transform.pos, transform.rot, Vec3{1, 1, 1}))
		return perspective(camera.fov_y, aspect, camera.near, camera.far) * view
	}
	panic("no camera in the world")
}
