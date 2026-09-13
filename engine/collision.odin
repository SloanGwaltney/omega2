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
