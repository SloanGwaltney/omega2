// Building entities from json. A document is an array of components, each
// with a name and its data:
//
//	[
//		{"name": "engine:transform", "data": {"pos": [0, 1.7, 5]}},
//		{"name": "casino:movement", "data": {"speed": 25}}
//	]
//
// Engine components are prefixed "engine:". Every other prefix belongs to a
// game, which loads its own through the ComponentLoader handed to
// entity_from_json. The prefix is what keeps the two name spaces from
// colliding.
//
// Only components whose data is plain values can be named here. Drawable and
// DrawableUpload hold gpu offsets and vertex bytes, so a mesh has to come
// from a game component that resolves an asset by name.
package engine

import "core:encoding/json"
import "core:math"
import "core:math/linalg"

// Loads a component the engine does not own. Returns false when name is not
// the game's either, which fails the whole entity.
ComponentLoader :: #type proc(w: ^World, e: Entity, name: string, data: json.Value) -> bool

// Creates an entity from a json component array, returning false if the
// document is malformed or names a component neither the engine nor load
// recognizes. A failed entity is destroyed before returning, though its id is
// still spent because ids are never reused.
entity_from_json :: proc(w: ^World, src: string, load: ComponentLoader = nil) -> (Entity, bool) {
	doc, err := json.parse_string(src, allocator = context.temp_allocator)
	if err != nil {
		return 0, false
	}
	components, is_array := doc.(json.Array)
	if !is_array {
		return 0, false
	}
	e := entity_create(w)
	for c in components {
		obj, is_obj := c.(json.Object)
		if !is_obj {
			entity_destroy(w, e)
			return 0, false
		}
		name, named := obj["name"].(json.String)
		if !named || !component_from_json(w, e, name, obj["data"], load) {
			entity_destroy(w, e)
			return 0, false
		}
	}
	return e, true
}

// Fills ptr from a component's data. Fields the json leaves out keep whatever
// ptr already holds, so seed it with any default that is not the zero value
// before calling. A component with no data at all keeps every default, which
// is what unmarshalling a null would wipe.
component_unmarshal :: proc(data: json.Value, ptr: ^$T) -> bool {
	if data == nil {
		return true
	}
	bytes, err := json.marshal(data, allocator = context.temp_allocator)
	if err != nil {
		return false
	}
	return json.unmarshal(bytes, ptr) == nil
}

// Transform as json names it. A quaternion is not something to write by hand,
// so rotation is euler degrees, turned about y then x then z to match the
// yaw and pitch the player is aimed with.
@(private = "file")
TransformJson :: struct {
	pos:   Vec3,
	rot:   Vec3,
	scale: Vec3,
}

// Adds the named component to e, deferring to load for anything outside the
// engine's prefix.
@(private = "file")
component_from_json :: proc(
	w: ^World,
	e: Entity,
	name: string,
	data: json.Value,
	load: ComponentLoader,
) -> bool {
	switch name {
	case "engine:transform":
		spec := TransformJson {
			scale = {1, 1, 1},
		}
		if !component_unmarshal(data, &spec) {
			return false
		}
		yaw := linalg.quaternion_angle_axis_f32(math.to_radians(spec.rot.y), Vec3{0, 1, 0})
		pitch := linalg.quaternion_angle_axis_f32(math.to_radians(spec.rot.x), Vec3{1, 0, 0})
		roll := linalg.quaternion_angle_axis_f32(math.to_radians(spec.rot.z), Vec3{0, 0, 1})
		pool_add(&w.transform, e, Transform{pos = spec.pos, rot = yaw * pitch * roll, scale = spec.scale})
	case "engine:camera":
		c: Camera
		if !component_unmarshal(data, &c) {
			return false
		}
		pool_add(&w.camera, e, c)
	case "engine:aabb":
		box: Aabb
		if !component_unmarshal(data, &box) {
			return false
		}
		pool_add(&w.aabb, e, box)
	case:
		if load == nil {
			return false
		}
		return load(w, e, name, data)
	}
	return true
}
