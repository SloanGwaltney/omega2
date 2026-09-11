// Cube stress demo: pulls the camera back, then spawns cubes at a fixed rate
// up to MAX_CUBES, each at a random transform inside the frustum, logging the
// frame rate as the count climbs.
package main

import "../../../engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"

CAMERA_Z :: 60
FOV_Y :: math.PI / 3
SPAWN_PER_SECOND :: 100
MAX_CUBES :: 9000
// World space depth range cubes are scattered over, in front of the camera.
NEAR_Z :: 20
FAR_Z :: -40

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

spawned: int
spawn_debt: f64

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)

	camera := engine.entity_create(app.world)
	camera_transform := engine.transform_identity()
	camera_transform.pos = {0, 0, CAMERA_Z}
	engine.pool_add(&app.world.transform, camera, camera_transform)
	engine.pool_add(&app.world.camera, camera, engine.Camera{fov_y = FOV_Y, near = 0.1, far = 200})

	app.user_update = demo_update
	engine.run_app(app)
}

// Spawns SPAWN_PER_SECOND cubes a second until MAX_CUBES exist, and logs the
// frame rate alongside the live cube count.
demo_update :: proc(app: ^engine.App) {
	dt := f64(app.world.delta_time) / 1e9
	spawn_debt += dt * SPAWN_PER_SECOND
	for spawn_debt >= 1 && spawned < MAX_CUBES {
		spawn_cube(app)
		spawn_debt -= 1
		spawned += 1
	}
	fmt.printfln("fps %.0f cubes %d", dt > 0 ? 1 / dt : 0, spawned)
}

// Creates a cube at a random position inside the camera frustum with a random
// rotation and scale.
spawn_cube :: proc(app: ^engine.App) {
	aspect := f32(app.surface_config.width) / f32(app.surface_config.height)
	z := rand.float32_range(FAR_Z, NEAR_Z)
	half_h := math.tan(f32(FOV_Y) / 2) * (CAMERA_Z - z)
	half_w := half_h * aspect

	t := engine.transform_identity()
	t.pos = {rand.float32_range(-half_w, half_w), rand.float32_range(-half_h, half_h), z}
	t.rot = linalg.quaternion_from_euler_angles_f32(
		rand.float32_range(0, 2 * math.PI),
		rand.float32_range(0, 2 * math.PI),
		rand.float32_range(0, 2 * math.PI),
		.XYZ,
	)
	t.scale = engine.Vec3(rand.float32_range(0.5, 1.5))

	e := engine.entity_create(app.world)
	engine.pool_add(&app.world.transform, e, t)
	engine.pool_add(
		&app.world.drawable_upload,
		e,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(CUBE_VERTICES[:]),
			indices = CUBE_INDICES[:],
		},
	)
}
