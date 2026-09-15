package main

import "../../../engine"
import "core:math"
import "core:math/linalg"
import "core:testing"

EPSILON :: 1e-5

@(private = "file")
expect_near_vec3 :: proc(t: ^testing.T, got, want: engine.Vec3, loc := #caller_location) {
	testing.expect(t, linalg.length(got - want) < EPSILON, "expected near equal vectors", loc = loc)
}

// A player at eye height aiming with the given yaw and pitch, built the way
// player_look_system builds it.
@(private = "file")
aiming :: proc(pos: engine.Vec3, yaw, pitch: f32) -> engine.Transform {
	t := engine.transform_identity()
	t.pos = pos
	t.rot =
		linalg.quaternion_angle_axis_f32(yaw, engine.Vec3{0, 1, 0}) *
		linalg.quaternion_angle_axis_f32(pitch, engine.Vec3{1, 0, 0})
	return t
}

@(test)
test_placement_target_straight_down :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({2, EYE_HEIGHT, -3}, 0, -math.PI / 2))
	testing.expect(t, on_floor)
	expect_near_vec3(t, pos, {2, 0, -3})
}

// Aimed 45 degrees down the floor is hit as far ahead as the eye is high.
@(test)
test_placement_target_lands_ahead_of_the_player :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, 0}, 0, -math.PI / 4))
	testing.expect(t, on_floor)
	expect_near_vec3(t, pos, {0, 0, -EYE_HEIGHT})
}

// Yaw turns the target about the player rather than moving it away.
@(test)
test_placement_target_follows_yaw :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, 0}, math.PI / 2, -math.PI / 4))
	testing.expect(t, on_floor)
	expect_near_vec3(t, pos, {-EYE_HEIGHT, 0, 0})
}

// A level aim never meets the floor, so it falls back to a point out at the
// reach and reports there is no floor under it.
@(test)
test_placement_target_level_aim_falls_back_to_reach :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, 0}, 0, 0))
	testing.expect(t, !on_floor)
	expect_near_vec3(t, pos, {0, 0, -PLACE_REACH})
}

@(test)
test_placement_target_upward_aim_falls_back_to_reach :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, 0}, 0, PITCH_LIMIT))
	testing.expect(t, !on_floor)
	expect_near_vec3(t, pos, {0, 0, -PLACE_REACH})
}

// Aimed far enough down the floor to be out of reach, the fallback keeps the
// item in front of the player instead of dropping it on the distant hit.
@(test)
test_placement_target_beyond_reach_falls_back :: proc(t: ^testing.T) {
	// Shallow enough that the floor is hit well past PLACE_REACH.
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, 0}, 0, -0.1))
	testing.expect(t, !on_floor)
	expect_near_vec3(t, pos, {0, 0, -PLACE_REACH})
}

// A hit off the edge of the floor is still where the item follows the aim to,
// but it cannot be placed there.
@(test)
test_placement_target_past_the_floor_edge_is_not_on_floor :: proc(t: ^testing.T) {
	pos, on_floor := placement_target(aiming({0, EYE_HEIGHT, -FLOOR_HALF}, 0, -math.PI / 4))
	testing.expect(t, !on_floor)
	expect_near_vec3(t, pos, {0, 0, -FLOOR_HALF - EYE_HEIGHT})
}
