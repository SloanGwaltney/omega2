// Scenes named by content rather than by code. The engine does no io, so every
// json document something may name is embedded here at compile time and looked
// up by its path; a path this build does not carry is a content bug worth
// failing loudly for.
package main

import "../../../engine"
import "core:encoding/json"
import "core:fmt"

SLOT_MACHINE_JSON :: #load("scenes/slot_machine.json", string)
UV_SPHERE_JSON :: #load("scenes/uv_sphere.json", string)

UV_SPHERE_SCENE :: "scenes/uv_sphere.json"

// Every scene a shop item may name, paired with the path it is embedded from.
SCENES := [?]struct {
	path: string,
	src:  string,
}{{SLOT_MACHINE_SCENE, SLOT_MACHINE_JSON}, {UV_SPHERE_SCENE, UV_SPHERE_JSON}}

// The document at path, false for a path this build does not embed.
scene_src :: proc(path: string) -> (string, bool) {
	for s in SCENES {
		if s.path == path {
			return s.src, true
		}
	}
	return "", false
}

// Builds the scene at path with its origin at pos, whatever position the
// document itself gives. Panics on a path this build does not carry or a
// document that fails to load.
scene_spawn :: proc(app: ^engine.App, path: string, pos: engine.Vec3) -> engine.Entity {
	src, found := scene_src(path)
	if !found {
		fmt.panicf("unknown scene %q", path)
	}
	e, ok := engine.entity_from_json(app.world, src, casino_component_loader)
	if !ok {
		fmt.panicf("bad scene %q", path)
	}
	engine.pool_get(&app.world.transform, e).pos = pos
	return e
}

// Path of the model the scene's "casino:model" names, empty for a scene that
// names none. What an icon of the scene is baked from.
scene_model_path :: proc(path: string) -> string {
	src, found := scene_src(path)
	if !found {
		fmt.panicf("unknown scene %q", path)
	}
	doc, err := json.parse_string(src, allocator = context.temp_allocator)
	if err != nil {
		fmt.panicf("bad scene %q", path)
	}
	for component in doc.(json.Array) or_else nil {
		obj := component.(json.Object) or_else nil
		name := obj["name"].(string) or_else ""
		if name != "casino:model" {
			continue
		}
		data := obj["data"].(json.Object) or_else nil
		return data["path"].(string) or_else ""
	}
	return ""
}
