// Collision against oriented boxes. A box is stored axis aligned in its
// entity's local space and every query is moved into that space, so a rotated
// entity is tested exactly rather than against a looser axis aligned hull.
package engine

import "core:math/linalg"

// Box in an entity's local space, before its transform.
Aabb :: struct {
	min: Vec3,
	max: Vec3,
}

// Nearest point on the box to p, both in the box's local space.
aabb_closest_point :: proc(box: Aabb, p: Vec3) -> Vec3 {
	return Vec3 {
		clamp(p.x, box.min.x, box.max.x),
		clamp(p.y, box.min.y, box.max.y),
		clamp(p.z, box.min.z, box.max.z),
	}
}

// Pushes a sphere clear of every box it overlaps, skipping ignore, and returns
// the corrected centre. Each push is along the surface normal, so motion across
// a face is kept and only the motion into it is removed. A centre already
// inside a box has no such normal and is left where it is.
collide_sphere :: proc(w: ^World, center: Vec3, radius: f32, ignore: Maybe(Entity) = nil) -> Vec3 {
	p := center
	for i in 0 ..< w.count {
		e := Entity(i)
		box := pool_get(&w.aabb, e)
		t := pool_get(&w.transform, e)
		if box == nil || t == nil || ignore == e {
			continue
		}
		local := transform_point_inverse(t^, p)
		closest := transform_point(t^, aabb_closest_point(box^, local))
		away := p - closest
		dist := linalg.length(away)
		if dist >= radius || dist == 0 {
			continue
		}
		p = closest + away / dist * radius
	}
	return p
}

// Distance along a ray to where it enters the box, both in the box's local
// space. Slab test. A ray starting inside the box returns 0; one that misses
// or only reaches the box behind its origin returns false.
ray_aabb :: proc(box: Aabb, origin, dir: Vec3) -> (f32, bool) {
	tmin, tmax := f32(0), max(f32)
	for i in 0 ..< 3 {
		if dir[i] == 0 {
			if origin[i] < box.min[i] || origin[i] > box.max[i] {
				return 0, false
			}
			continue
		}
		inv := 1 / dir[i]
		t0 := (box.min[i] - origin[i]) * inv
		t1 := (box.max[i] - origin[i]) * inv
		if t0 > t1 {
			t0, t1 = t1, t0
		}
		tmin = max(tmin, t0)
		tmax = min(tmax, t1)
		if tmin > tmax {
			return 0, false
		}
	}
	return tmin, true
}

// Nearest entity with a box hit by the ray, searched out to max_dist and
// skipping ignore. dir must be normalized, so the returned distance is in
// world units. Every box is tested; this is a linear scan until it hurts.
raycast :: proc(
	w: ^World,
	origin, dir: Vec3,
	max_dist: f32,
	ignore: Entity,
) -> (
	hit: Entity,
	dist: f32,
	ok: bool,
) {
	dist = max_dist
	for i in 0 ..< w.count {
		e := Entity(i)
		box := pool_get(&w.aabb, e)
		t := pool_get(&w.transform, e)
		if e == ignore || box == nil || t == nil {
			continue
		}
		d, box_hit := ray_aabb(
			box^,
			transform_point_inverse(t^, origin),
			transform_vector_inverse(t^, dir),
		)
		if !box_hit || d >= dist {
			continue
		}
		hit, dist, ok = e, d, true
	}
	return
}

// A box in world space, kept as a rectangle on the xz plane plus a y range.
// Only the yaw of the entity's rotation survives, so this is exact for props
// standing upright and wrong for anything pitched or rolled.
Obb2 :: struct {
	// Centre on the xz plane.
	center: Vec2,
	// The rectangle's own right and forward axes, unit length.
	axes:   [2]Vec2,
	// Half extents along those axes.
	half:   Vec2,
	min_y:  f32,
	max_y:  f32,
}

// Slack allowed before two boxes count as overlapping, so props placed edge
// to edge are not rejected for touching.
OVERLAP_SLACK :: 0.001

// Flattens a box and its transform into an Obb2.
obb2_from :: proc(box: Aabb, t: Transform) -> Obb2 {
	half := (box.max - box.min) / 2 * t.scale
	center := transform_point(t, box.min + (box.max - box.min) / 2)
	x := linalg.quaternion_mul_vector3(t.rot, Vec3{1, 0, 0})
	z := linalg.quaternion_mul_vector3(t.rot, Vec3{0, 0, 1})
	return Obb2 {
		center = {center.x, center.z},
		axes = {flatten_xz(x), flatten_xz(z)},
		half = {half.x, half.z},
		min_y = center.y - half.y,
		max_y = center.y + half.y,
	}
}

// Drops v's y and renormalizes it, falling back to +x when nothing is left.
@(private = "file")
flatten_xz :: proc(v: Vec3) -> Vec2 {
	flat := Vec2{v.x, v.z}
	if length := linalg.length(flat); length > 0 {
		return flat / length
	}
	return {1, 0}
}

// Half the width of a's footprint measured along axis.
@(private = "file")
obb2_radius :: proc(a: Obb2, axis: Vec2) -> f32 {
	return a.half.x * abs(linalg.dot(a.axes[0], axis)) + a.half.y * abs(linalg.dot(a.axes[1], axis))
}

// True while two boxes share any volume. Separating axis test over the four
// footprint axes, with the y ranges checked outright.
obb2_overlaps :: proc(a, b: Obb2) -> bool {
	if a.min_y >= b.max_y - OVERLAP_SLACK || b.min_y >= a.max_y - OVERLAP_SLACK {
		return false
	}
	between := b.center - a.center
	for axis in ([4]Vec2{a.axes[0], a.axes[1], b.axes[0], b.axes[1]}) {
		gap := abs(linalg.dot(between, axis)) - obb2_radius(a, axis) - obb2_radius(b, axis)
		if gap > -OVERLAP_SLACK {
			return false
		}
	}
	return true
}

// True while e's box overlaps the box of any other entity. Every box is
// tested; this is a linear scan until it hurts.
aabb_overlaps_any :: proc(w: ^World, e: Entity) -> bool {
	box := pool_get(&w.aabb, e)
	t := pool_get(&w.transform, e)
	if box == nil || t == nil {
		return false
	}
	a := obb2_from(box^, t^)
	for i in 0 ..< w.count {
		other := Entity(i)
		other_box := pool_get(&w.aabb, other)
		other_t := pool_get(&w.transform, other)
		if other == e || other_box == nil || other_t == nil {
			continue
		}
		if obb2_overlaps(a, obb2_from(other_box^, other_t^)) {
			return true
		}
	}
	return false
}
