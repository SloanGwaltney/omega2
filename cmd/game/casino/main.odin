// Casino scratch scene: a first person camera that aims with the mouse and
// walks the xz plane with WASD over a flat floor.
package main

import "../../../engine"
import "core:math"
import "core:slice"

EYE_HEIGHT :: 1.7
MOVE_SPEED :: 25.0
MOUSE_SENSITIVITY :: 0.002
FLOOR_HALF :: 50.0
FLOOR_COLOR :: engine.Vec4{0.15, 0.35, 0.2, 1}

FLOOR_VERTICES := [?]engine.Vertex {
	{pos = {-FLOOR_HALF, 0, FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {FLOOR_HALF, 0, FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {FLOOR_HALF, 0, -FLOOR_HALF}, color = FLOOR_COLOR},
	{pos = {-FLOOR_HALF, 0, -FLOOR_HALF}, color = FLOOR_COLOR},
}
FLOOR_INDICES := [?]engine.Index{0, 1, 2, 0, 2, 3}

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)

	player := engine.entity_create(app.world)
	t := engine.transform_identity()
	t.pos = {0, EYE_HEIGHT, 5}
	engine.pool_add(&app.world.transform, player, t)
	engine.pool_add(
		&app.world.camera,
		player,
		engine.Camera{fov_y = math.PI / 3, near = 0.1, far = 200},
	)
	engine.pool_add(&app.world.input, player, engine.InputValues{})
	engine.pool_add(&app.world.player, player, engine.Player{})
	engine.pool_add(&app.world.movement, player, engine.Movement{speed = MOVE_SPEED})
	engine.pool_add(
		&app.world.mouse_look,
		player,
		engine.MouseLook{sensitivity = MOUSE_SENSITIVITY},
	)

	floor := engine.entity_create(app.world)
	engine.pool_add(&app.world.transform, floor, engine.transform_identity())
	engine.pool_add(
		&app.world.drawable_upload,
		floor,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(FLOOR_VERTICES[:]),
			indices = FLOOR_INDICES[:],
		},
	)

	engine.run_app(app)
}
