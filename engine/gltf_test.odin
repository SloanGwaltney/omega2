// A glb is a header, a json chunk and a binary chunk, all three of which are
// cheap to assemble in a test. So none of this needs a model on disk: each
// fixture is a document written out by hand over a handful of bytes, which is
// also the only way to cover the malformed documents an exporter never emits.
//
// Documents are concatenated rather than formatted, because Odin's fmt reads
// a brace as a format directive and a json document is nothing but braces.
package engine

import "core:slice"
import "core:strings"
import "core:testing"

@(private = "file")
MAGIC :: 0x46546C67
@(private = "file")
JSON_CHUNK :: 0x4E4F534A
@(private = "file")
BIN_CHUNK :: 0x004E4942

// The triangle every fixture draws from, and the indices onto it. Positions
// occupy the first 36 bytes of the binary chunk and the indices the 6 after.
@(private = "file")
TRIANGLE := [3]Vec3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
@(private = "file")
TRIANGLE_INDICES := [3]u16{0, 1, 2}

// A glb around document and bin, padding both chunks the way the container
// requires so a reader that ignores the padding still lands on the next
// chunk header.
@(private = "file")
glb :: proc(document: string, bin: []byte) -> []byte {
	pad :: proc(n: int) -> int {
		return (4 - n % 4) % 4
	}
	out := make([dynamic]byte, 0, 128, context.temp_allocator)
	total := 12 + 8 + len(document) + pad(len(document)) + 8 + len(bin) + pad(len(bin))

	append_u32(&out, MAGIC)
	append_u32(&out, 2)
	append_u32(&out, u32(total))

	append_u32(&out, u32(len(document) + pad(len(document))))
	append_u32(&out, JSON_CHUNK)
	append(&out, document)
	for _ in 0 ..< pad(len(document)) {
		append(&out, ' ')
	}

	append_u32(&out, u32(len(bin) + pad(len(bin))))
	append_u32(&out, BIN_CHUNK)
	append(&out, ..bin)
	for _ in 0 ..< pad(len(bin)) {
		append(&out, 0)
	}
	return out[:]
}

@(private = "file")
append_u32 :: proc(out: ^[dynamic]byte, v: u32) {
	append(out, byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24))
}

// The triangle's positions followed by indices, at the offsets
// triangle_doc's buffer views name.
@(private = "file")
triangle_bin :: proc(indices: []u16 = nil) -> []byte {
	indices := indices
	if indices == nil {
		indices = TRIANGLE_INDICES[:]
	}
	out := make([dynamic]byte, 0, 48, context.temp_allocator)
	append(&out, ..slice.to_bytes(TRIANGLE[:]))
	append(&out, ..slice.to_bytes(indices))
	return out[:]
}

// A document holding one triangle, where nodes is the node array whose first
// entry the scene names, primitive is what the primitive carries past its
// attributes and indices, materials is the material array, and buffer is the
// buffer the positions are read from.
@(private = "file")
triangle_doc :: proc(nodes: string, primitive := "", materials := "[]", buffer := "0") -> string {
	return strings.concatenate(
		{
			`{"asset": {"version": "2.0"},`,
			`"scenes": [{"nodes": [0]}],`,
			`"nodes": `,
			nodes,
			`,"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1`,
			primitive,
			`}]}],`,
			`"materials": `,
			materials,
			`,"accessors": [`,
			`{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},`,
			`{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],`,
			`"bufferViews": [`,
			`{"buffer": `,
			buffer,
			`, "byteOffset": 0, "byteLength": 36},`,
			`{"buffer": 0, "byteOffset": 36, "byteLength": 6}],`,
			`"buffers": [{"byteLength": 42}]}`,
		},
		context.temp_allocator,
	)
}

@(private = "file")
triangle_glb :: proc(nodes: string, primitive := "", materials := "[]", buffer := "0") -> []byte {
	return glb(triangle_doc(nodes, primitive, materials, buffer), triangle_bin())
}

@(private = "file")
vertices_of :: proc(mesh: MeshData) -> []Vertex {
	return slice.reinterpret([]Vertex, mesh.data)
}

// A loaded mesh owns two allocations, which a test has to drop for the
// runner's leak tracking to stay quiet.
@(private = "file")
delete_mesh :: proc(mesh: MeshData) {
	delete(mesh.data)
	delete(mesh.indices)
}

@(private = "file")
expect_near :: proc(t: ^testing.T, got, want: Vec3, loc := #caller_location) {
	for i in 0 ..< 3 {
		testing.expectf(t, abs(got[i] - want[i]) < EPSILON, "expected %v, got %v", want, got, loc = loc)
	}
}

// A node's translation and scale have to arrive baked into the positions,
// because the importer flattens the scene and nothing downstream sees the
// node again.
@(test)
test_mesh_from_glb_bakes_node_transform :: proc(t: ^testing.T) {
	mesh, ok := mesh_from_glb(triangle_glb(`[{"mesh": 0, "translation": [1, 0, 0], "scale": [2, 2, 2]}]`))
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	verts := vertices_of(mesh)
	testing.expect_value(t, len(verts), 3)
	expect_near(t, verts[0].pos, {1, 0, 0})
	expect_near(t, verts[1].pos, {3, 0, 0})
	expect_near(t, verts[2].pos, {1, 2, 0})
	testing.expect_value(t, mesh.bounds, Aabb{min = {1, 0, 0}, max = {3, 2, 0}})
}

// u16 indices are what an exporter writes and u32 is what the gpu buffer
// holds, so the widening is on the common path.
@(test)
test_mesh_from_glb_widens_indices :: proc(t: ^testing.T) {
	mesh, ok := mesh_from_glb(triangle_glb(`[{"mesh": 0}]`))
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	testing.expect(t, slice.equal(mesh.indices, []Index{0, 1, 2}))
}

// gltf writes a node's matrix column major, which is the same order Odin
// stores one in but the transpose of how a matrix literal reads. A parent
// matrix scaling x by 3 and lifting y by 5 has to compose with the child's
// own translation.
@(test)
test_mesh_from_glb_node_matrix :: proc(t: ^testing.T) {
	mesh, ok := mesh_from_glb(
		triangle_glb(
			`[
				{"matrix": [3,0,0,0, 0,1,0,0, 0,0,1,0, 0,5,0,1], "children": [1]},
				{"mesh": 0, "translation": [0, 0, 2]}
			]`,
		),
	)
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	verts := vertices_of(mesh)
	expect_near(t, verts[0].pos, {0, 5, 2})
	expect_near(t, verts[1].pos, {3, 5, 2})
	expect_near(t, verts[2].pos, {0, 6, 2})
}

// The base color factor is the whole of the material this reads, and it is
// what makes an imported mesh visible at all under the unlit pipeline.
@(test)
test_mesh_from_glb_base_color :: proc(t: ^testing.T) {
	mesh, ok := mesh_from_glb(
		triangle_glb(
			`[{"mesh": 0}]`,
			`, "material": 0`,
			`[{"pbrMetallicRoughness": {"baseColorFactor": [0.25, 0.5, 0.75, 1]}}]`,
		),
	)
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	for v in vertices_of(mesh) {
		testing.expect_value(t, v.color, Vec4{0.25, 0.5, 0.75, 1})
	}
}

// A primitive with no material, or one whose material leaves the factor out,
// is white rather than the transparent black a zero value would give.
@(test)
test_mesh_from_glb_default_color :: proc(t: ^testing.T) {
	bare, bare_ok := mesh_from_glb(triangle_glb(`[{"mesh": 0}]`))
	defer delete_mesh(bare)
	empty, empty_ok := mesh_from_glb(
		triangle_glb(`[{"mesh": 0}]`, `, "material": 0`, `[{"pbrMetallicRoughness": {}}]`),
	)
	defer delete_mesh(empty)

	testing.expect(t, bare_ok)
	testing.expect(t, empty_ok)
	testing.expect_value(t, vertices_of(bare)[0].color, Vec4{1, 1, 1, 1})
	testing.expect_value(t, vertices_of(empty)[0].color, Vec4{1, 1, 1, 1})
}

// Attributes may be interleaved in one buffer view, which is the case a
// reader that assumes tight packing gets wrong while still producing
// plausible looking vertices.
@(test)
test_mesh_from_glb_interleaved :: proc(t: ^testing.T) {
	Interleaved :: struct {
		pos: Vec3,
		uv:  Vec2,
	}
	verts := [3]Interleaved {
		{pos = {0, 0, 0}, uv = {0, 0}},
		{pos = {1, 0, 0}, uv = {1, 0}},
		{pos = {0, 1, 0}, uv = {0, 1}},
	}
	bin := make([dynamic]byte, 0, 72, context.temp_allocator)
	append(&bin, ..slice.to_bytes(verts[:]))
	append(&bin, ..slice.to_bytes(TRIANGLE_INDICES[:]))

	mesh, ok := mesh_from_glb(
		glb(
			`{
				"asset": {"version": "2.0"},
				"scenes": [{"nodes": [0]}],
				"nodes": [{"mesh": 0}],
				"meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2}]}],
				"accessors": [
					{"bufferView": 0, "byteOffset": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
					{"bufferView": 0, "byteOffset": 12, "componentType": 5126, "count": 3, "type": "VEC2"},
					{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
				],
				"bufferViews": [
					{"buffer": 0, "byteOffset": 0, "byteLength": 60, "byteStride": 20},
					{"buffer": 0, "byteOffset": 60, "byteLength": 6}
				],
				"buffers": [{"byteLength": 66}]
			}`,
			bin[:],
		),
	)
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	got := vertices_of(mesh)
	testing.expect_value(t, len(got), 3)
	for v, i in got {
		expect_near(t, v.pos, verts[i].pos)
		testing.expect_value(t, v.uv, verts[i].uv)
	}
}

// Each primitive of a mesh is its own run of vertices, so the second one's
// indices have to be offset past the first's rather than aliasing it.
@(test)
test_mesh_from_glb_offsets_each_primitive :: proc(t: ^testing.T) {
	mesh, ok := mesh_from_glb(
		glb(
			`{
				"asset": {"version": "2.0"},
				"scenes": [{"nodes": [0]}],
				"nodes": [{"mesh": 0}],
				"meshes": [{"primitives": [
					{"attributes": {"POSITION": 0}, "indices": 1},
					{"attributes": {"POSITION": 0}, "indices": 1}
				]}],
				"accessors": [
					{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
					{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
				],
				"bufferViews": [
					{"buffer": 0, "byteOffset": 0, "byteLength": 36},
					{"buffer": 0, "byteOffset": 36, "byteLength": 6}
				],
				"buffers": [{"byteLength": 42}]
			}`,
			triangle_bin(),
		),
	)
	defer delete_mesh(mesh)

	testing.expect(t, ok)
	testing.expect_value(t, len(vertices_of(mesh)), 6)
	testing.expect(t, slice.equal(mesh.indices, []Index{0, 1, 2, 3, 4, 5}))
}

@(test)
test_mesh_from_glb_rejects_bad_magic :: proc(t: ^testing.T) {
	bytes := triangle_glb(`[{"mesh": 0}]`)
	bytes[0] = 'x'

	_, ok := mesh_from_glb(bytes)

	testing.expect(t, !ok)
}

@(test)
test_mesh_from_glb_rejects_truncated :: proc(t: ^testing.T) {
	bytes := triangle_glb(`[{"mesh": 0}]`)

	_, ok := mesh_from_glb(bytes[:len(bytes) / 2])

	testing.expect(t, !ok)
}

// The pipelines draw triangle lists only, so a strip or a fan has to be
// refused rather than drawn as if its indices meant something else.
@(test)
test_mesh_from_glb_rejects_non_triangles :: proc(t: ^testing.T) {
	_, ok := mesh_from_glb(triangle_glb(`[{"mesh": 0}]`, `, "mode": 5`))

	testing.expect(t, !ok)
}

// Buffer zero is the glb's own binary chunk. Any other buffer is a file, and
// the engine does no io.
@(test)
test_mesh_from_glb_rejects_external_buffer :: proc(t: ^testing.T) {
	_, ok := mesh_from_glb(triangle_glb(`[{"mesh": 0}]`, buffer = "1"))

	testing.expect(t, !ok)
}

// An accessor reaching past its buffer view would otherwise be read straight
// out of whatever follows the binary chunk.
@(test)
test_mesh_from_glb_rejects_overrunning_accessor :: proc(t: ^testing.T) {
	_, ok := mesh_from_glb(
		glb(
			`{
				"asset": {"version": "2.0"},
				"scenes": [{"nodes": [0]}],
				"nodes": [{"mesh": 0}],
				"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
				"accessors": [
					{"bufferView": 0, "componentType": 5126, "count": 8, "type": "VEC3"},
					{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
				],
				"bufferViews": [
					{"buffer": 0, "byteOffset": 0, "byteLength": 36},
					{"buffer": 0, "byteOffset": 36, "byteLength": 6}
				],
				"buffers": [{"byteLength": 42}]
			}`,
			triangle_bin(),
		),
	)

	testing.expect(t, !ok)
}

// An index past the primitive's vertices would read a vertex belonging to
// another primitive, or none at all.
@(test)
test_mesh_from_glb_rejects_out_of_range_index :: proc(t: ^testing.T) {
	_, ok := mesh_from_glb(glb(triangle_doc(`[{"mesh": 0}]`), triangle_bin([]u16{0, 1, 9})))

	testing.expect(t, !ok)
}

// A primitive with no POSITION has no geometry, whatever else it carries.
@(test)
test_mesh_from_glb_rejects_missing_position :: proc(t: ^testing.T) {
	_, ok := mesh_from_glb(
		glb(
			`{
				"asset": {"version": "2.0"},
				"scenes": [{"nodes": [0]}],
				"nodes": [{"mesh": 0}],
				"meshes": [{"primitives": [{"attributes": {"NORMAL": 0}, "indices": 1}]}],
				"accessors": [
					{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
					{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
				],
				"bufferViews": [
					{"buffer": 0, "byteOffset": 0, "byteLength": 36},
					{"buffer": 0, "byteOffset": 36, "byteLength": 6}
				],
				"buffers": [{"byteLength": 42}]
			}`,
			triangle_bin(),
		),
	)

	testing.expect(t, !ok)
}
