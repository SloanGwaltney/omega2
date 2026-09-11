package main

import "../../engine"
import "core:math"
import "core:slice"

TRIANGLE_VERTICES := [?]engine.Vertex {
	{pos = {0, 0.5, 0}, color = {1, 0, 0, 1}},
	{pos = {-0.5, -0.5, 0}, color = {0, 1, 0, 1}},
	{pos = {0.5, -0.5, 0}, color = {0, 0, 1, 1}},
}
TRIANGLE_INDICES := [?]engine.Index{0, 1, 2}

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)

	camera := engine.entity_create(app.world)
	camera_transform := engine.transform_identity()
	camera_transform.pos = {0, 0, 3}
	engine.pool_add(&app.world.transform, camera, camera_transform)
	engine.pool_add(&app.world.camera, camera, engine.Camera{fov_y = math.PI / 3, near = 0.1, far = 100})

	triangle := engine.entity_create(app.world)
	engine.pool_add(&app.world.transform, triangle, engine.transform_identity())
	engine.pool_add(
		&app.world.drawable_upload,
		triangle,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(TRIANGLE_VERTICES[:]),
			indices = TRIANGLE_INDICES[:],
		},
	)

	engine.run_app(app)
}
