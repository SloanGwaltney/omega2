package main

import "../../engine"
import "core:math"
import "core:math/linalg"
import "core:slice"

CUBE_VERTICES := [?]engine.Vertex {
	{pos = {-0.5, -0.5, 0.5}, color = {0, 0, 1, 1}},
	{pos = {0.5, -0.5, 0.5}, color = {1, 0, 1, 1}},
	{pos = {0.5, 0.5, 0.5}, color = {1, 1, 1, 1}},
	{pos = {-0.5, 0.5, 0.5}, color = {0, 1, 1, 1}},
	{pos = {-0.5, -0.5, -0.5}, color = {0, 0, 0, 1}},
	{pos = {0.5, -0.5, -0.5}, color = {1, 0, 0, 1}},
	{pos = {0.5, 0.5, -0.5}, color = {1, 1, 0, 1}},
	{pos = {-0.5, 0.5, -0.5}, color = {0, 1, 0, 1}},
}
CUBE_INDICES := [?]engine.Index {
	0, 1, 2, 0, 2, 3, // front
	1, 5, 6, 1, 6, 2, // right
	5, 4, 7, 5, 7, 6, // back
	4, 0, 3, 4, 3, 7, // left
	3, 2, 6, 3, 6, 7, // top
	4, 5, 1, 4, 1, 0, // bottom
}

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)

	camera := engine.entity_create(app.world)
	camera_transform := engine.transform_identity()
	camera_transform.pos = {0, 0, 3}
	engine.pool_add(&app.world.transform, camera, camera_transform)
	engine.pool_add(&app.world.camera, camera, engine.Camera{fov_y = math.PI / 3, near = 0.1, far = 100})

	cube := engine.entity_create(app.world)
	cube_transform := engine.transform_identity()
	cube_transform.rot = linalg.quaternion_from_euler_angles_f32(
		math.PI / 6,
		math.PI / 4,
		0,
		.XYZ,
	)
	engine.pool_add(&app.world.transform, cube, cube_transform)
	engine.pool_add(
		&app.world.drawable_upload,
		cube,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(CUBE_VERTICES[:]),
			indices = CUBE_INDICES[:],
		},
	)

	engine.run_app(app)
}
