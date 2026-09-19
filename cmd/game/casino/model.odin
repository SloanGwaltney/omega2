// Models named by a scene. The engine does no io, so every glb a scene may
// name is embedded here at compile time and looked up by its path; a path
// this build does not carry is a content bug worth failing loudly for.
package main

import "../../../engine"

DEMO_SLOT_GLB :: #load("models/demo_slot.glb")

// Every glb a "casino:model" component may name, paired with the path it is
// embedded from.
MODELS := [?]struct {
	path: string,
	glb:  []byte,
}{{"models/demo_slot.glb", DEMO_SLOT_GLB}}

// Meshes already imported, keyed by path. A model is loaded once and kept
// for the life of the process, because every drawable built from it keeps its
// slices.
@(private = "file")
MESHES: map[string]engine.MeshData

// Imports path, or returns the copy already imported. Every model is grounded
// as it is imported, so a scene positions it by its base rather than by
// wherever the exporter's origin happened to sit. False for a path this build
// does not embed or a glb the importer refuses.
model_mesh :: proc(path: string) -> (engine.MeshData, bool) {
	if mesh, cached := MESHES[path]; cached {
		return mesh, true
	}
	for m in MODELS {
		if m.path != path {
			continue
		}
		mesh, ok := engine.mesh_from_glb(m.glb)
		if ok {
			engine.mesh_ground(&mesh)
			MESHES[path] = mesh
		}
		return mesh, ok
	}
	return {}, false
}

// A glb to draw, named by a scene. Loaded when the component is read, so the
// component itself is never stored.
ModelSpec :: struct {
	path: string,
}

// Imports spec.path and gives e the mesh and its bounds. The mesh is grounded
// on import, so the entity's transform places its base.
model_load :: proc(w: ^engine.World, e: engine.Entity, spec: ModelSpec) -> bool {
	mesh, ok := model_mesh(spec.path)
	if !ok {
		return false
	}
	engine.pool_add(
		&w.drawable_upload,
		e,
		engine.DrawableUpload{pipeline = .Lit, data = mesh.data, indices = mesh.indices},
	)
	engine.pool_add(&w.aabb, e, mesh.bounds)
	return true
}
