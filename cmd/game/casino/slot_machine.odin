// Placeholder slot machine: an untextured cabinet box with a screen quad on
// its front face. Its origin sits at the base so it can be placed straight
// onto the floor plane.
package main

import "../../../engine"
import "core:slice"

SLOT_HALF_WIDTH :: 0.5
SLOT_HALF_DEPTH :: 0.35
SLOT_HEIGHT :: 1.8
SLOT_SCREEN_BOTTOM :: 1.0
SLOT_SCREEN_TOP :: 1.6
SLOT_SCREEN_INSET :: 0.1
SLOT_SCREEN_OFFSET :: 0.01

SLOT_BODY_COLOR :: engine.Vec4{0.45, 0.1, 0.14, 1}
SLOT_SIDE_COLOR :: engine.Vec4{0.35, 0.08, 0.11, 1}
SLOT_TOP_COLOR :: engine.Vec4{0.55, 0.13, 0.17, 1}
SLOT_SCREEN_COLOR :: engine.Vec4{0.1, 0.12, 0.25, 1}

@(private = "file")
W :: SLOT_HALF_WIDTH
@(private = "file")
D :: SLOT_HALF_DEPTH
@(private = "file")
H :: SLOT_HEIGHT
@(private = "file")
SW :: SLOT_HALF_WIDTH - SLOT_SCREEN_INSET
@(private = "file")
SD :: SLOT_HALF_DEPTH + SLOT_SCREEN_OFFSET

SLOT_VERTICES := [?]engine.Vertex {
	// front
	{pos = {-W, 0, D}, color = SLOT_BODY_COLOR},
	{pos = {W, 0, D}, color = SLOT_BODY_COLOR},
	{pos = {W, H, D}, color = SLOT_BODY_COLOR},
	{pos = {-W, H, D}, color = SLOT_BODY_COLOR},
	// back
	{pos = {W, 0, -D}, color = SLOT_SIDE_COLOR},
	{pos = {-W, 0, -D}, color = SLOT_SIDE_COLOR},
	{pos = {-W, H, -D}, color = SLOT_SIDE_COLOR},
	{pos = {W, H, -D}, color = SLOT_SIDE_COLOR},
	// left
	{pos = {-W, 0, -D}, color = SLOT_SIDE_COLOR},
	{pos = {-W, 0, D}, color = SLOT_SIDE_COLOR},
	{pos = {-W, H, D}, color = SLOT_SIDE_COLOR},
	{pos = {-W, H, -D}, color = SLOT_SIDE_COLOR},
	// right
	{pos = {W, 0, D}, color = SLOT_SIDE_COLOR},
	{pos = {W, 0, -D}, color = SLOT_SIDE_COLOR},
	{pos = {W, H, -D}, color = SLOT_SIDE_COLOR},
	{pos = {W, H, D}, color = SLOT_SIDE_COLOR},
	// top
	{pos = {-W, H, D}, color = SLOT_TOP_COLOR},
	{pos = {W, H, D}, color = SLOT_TOP_COLOR},
	{pos = {W, H, -D}, color = SLOT_TOP_COLOR},
	{pos = {-W, H, -D}, color = SLOT_TOP_COLOR},
	// screen
	{pos = {-SW, SLOT_SCREEN_BOTTOM, SD}, color = SLOT_SCREEN_COLOR},
	{pos = {SW, SLOT_SCREEN_BOTTOM, SD}, color = SLOT_SCREEN_COLOR},
	{pos = {SW, SLOT_SCREEN_TOP, SD}, color = SLOT_SCREEN_COLOR},
	{pos = {-SW, SLOT_SCREEN_TOP, SD}, color = SLOT_SCREEN_COLOR},
}

SLOT_INDICES := [?]engine.Index {
	0, 1, 2, 0, 2, 3,
	4, 5, 6, 4, 6, 7,
	8, 9, 10, 8, 10, 11,
	12, 13, 14, 12, 14, 15,
	16, 17, 18, 16, 18, 19,
	20, 21, 22, 20, 22, 23,
}

// Spawns a slot machine standing on the floor at pos.
slot_machine_create :: proc(app: ^engine.App, pos: engine.Vec3) -> engine.Entity {
	e := engine.entity_create(app.world)
	t := engine.transform_identity()
	t.pos = pos
	engine.pool_add(&app.world.transform, e, t)
	engine.pool_add(
		&app.world.drawable_upload,
		e,
		engine.DrawableUpload {
			pipeline = .Unlit,
			data = slice.to_bytes(SLOT_VERTICES[:]),
			indices = SLOT_INDICES[:],
		},
	)
	engine.pool_add(&app.world.aabb, e, engine.Aabb{{-W, 0, -D}, {W, H, D}})
	return e
}
