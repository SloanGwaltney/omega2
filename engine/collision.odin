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

// Pushes a sphere clear of every box it overlaps and returns the corrected
// centre. Each push is along the surface normal, so motion across a face is
// kept and only the motion into it is removed. A centre already inside a box
// has no such normal and is left where it is.
collide_sphere :: proc(w: ^World, center: Vec3, radius: f32) -> Vec3 {
	p := center
	for i in 0 ..< w.count {
		e := Entity(i)
		box := pool_get(&w.aabb, e)
		t := pool_get(&w.transform, e)
		if box == nil || t == nil {
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
