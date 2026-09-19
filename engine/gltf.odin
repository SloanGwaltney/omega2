// Reading geometry out of a binary gltf. The engine does no io, so the game
// hands over the bytes and gets back a MeshData.
//
// Only what the world pipelines can draw is read: positions, normals, uvs, and
// each primitive's base color factor flattened into the vertex color. Every
// mesh the scene reaches becomes one MeshData, with each node's transform
// baked into its positions and normals. Textures, skins and animations are
// ignored, so a model arrives in its flat material colors, shaded only by the
// lit pipeline's own light.
package engine

import "base:intrinsics"
import "core:encoding/json"
import "core:math"
import "core:slice"

// The container's file magic and its two chunk types, each four ascii bytes
// read as a little endian u32, so they read backwards here: "glTF", "JSON"
// and "BIN" padded with a nul.
@(private = "file")
GLB_MAGIC :: 0x46546C67
@(private = "file")
GLB_JSON :: 0x4E4F534A
@(private = "file")
GLB_BIN :: 0x004E4942

// gltf componentType values, the ones an accessor this reads may use. They
// are the OpenGL type enums gltf inherited, which is the only reason they
// start at 5120 and skip a value: 5120 and 5122 are the signed byte and short
// no accessor here accepts.
@(private = "file")
COMPONENT_U8 :: 5121
@(private = "file")
COMPONENT_U16 :: 5123
@(private = "file")
COMPONENT_U32 :: 5125
@(private = "file")
COMPONENT_F32 :: 5126

// primitive.mode for a triangle list, the only topology the pipelines draw.
// Another OpenGL enum: 0 through 6 are points, lines, line loop, line strip,
// triangles, triangle strip and triangle fan.
@(private = "file")
MODE_TRIANGLES :: 4

// The slice of the gltf document this reads. Fields gltf leaves out keep the
// zero value, and the ones whose default is not zero are Maybe so the default
// can be applied where it is used.
@(private = "file")
GltfDoc :: struct {
	scene:        Maybe(u32),
	scenes:       []GltfScene,
	nodes:        []GltfNode,
	meshes:       []GltfMesh,
	accessors:    []GltfAccessor,
	buffer_views: []GltfBufferView `json:"bufferViews"`,
	materials:    []GltfMaterial,
}

@(private = "file")
GltfScene :: struct {
	nodes: []u32,
}

// A node's transform is either matrix or the translation, rotation and scale
// that compose to it, never both.
@(private = "file")
GltfNode :: struct {
	mesh:        Maybe(u32),
	children:    []u32,
	local:       Maybe([16]f32) `json:"matrix"`,
	translation: Maybe(Vec3),
	rotation:    Maybe([4]f32),
	scale:       Maybe(Vec3),
}

@(private = "file")
GltfMesh :: struct {
	primitives: []GltfPrimitive,
}

@(private = "file")
GltfPrimitive :: struct {
	// Accessor index per attribute name, of which POSITION, NORMAL and
	// TEXCOORD_0 are read.
	attributes: map[string]u32,
	indices:    Maybe(u32),
	material:   Maybe(u32),
	mode:       Maybe(u32),
}

@(private = "file")
GltfAccessor :: struct {
	buffer_view:    Maybe(u32) `json:"bufferView"`,
	byte_offset:    u32 `json:"byteOffset"`,
	component_type: u32 `json:"componentType"`,
	count:          u32,
	kind:           string `json:"type"`,
}

@(private = "file")
GltfBufferView :: struct {
	buffer:      u32,
	byte_offset: u32 `json:"byteOffset"`,
	byte_length: u32 `json:"byteLength"`,
	byte_stride: Maybe(u32) `json:"byteStride"`,
}

@(private = "file")
GltfMaterial :: struct {
	pbr: Maybe(GltfPbr) `json:"pbrMetallicRoughness"`,
}

@(private = "file")
GltfPbr :: struct {
	base_color: Maybe(Vec4) `json:"baseColorFactor"`,
}

// The mesh being built out of the nodes as they are walked.
@(private = "file")
Builder :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]Index,
	bounds:   Aabb,
}

// Reads glb's default scene into a single unlit mesh. The returned slices are
// allocated with allocator and must outlive every drawable built from them,
// because mesh_upload keeps them.
//
// Returns false for anything outside the supported slice of gltf: a malformed
// container, a buffer held outside the glb, a primitive that is not an f32
// triangle list, or a sparse accessor.
mesh_from_glb :: proc(glb: []byte, allocator := context.allocator) -> (mesh: MeshData, ok: bool) {
	document, bin, split := glb_chunks(glb)
	if !split {
		return
	}

	doc: GltfDoc
	if json.unmarshal(document, &doc, allocator = context.temp_allocator) != nil {
		return
	}

	scene := doc.scene.? or_else 0
	if int(scene) >= len(doc.scenes) {
		return
	}

	b := Builder {
		vertices = make([dynamic]Vertex, allocator),
		indices  = make([dynamic]Index, allocator),
		bounds   = {min = math.F32_MAX, max = -math.F32_MAX},
	}
	for root in doc.scenes[scene].nodes {
		if !gltf_node(&doc, bin, root, MAT4_IDENTITY, &b) {
			delete(b.vertices)
			delete(b.indices)
			return
		}
	}
	if len(b.vertices) == 0 {
		delete(b.vertices)
		delete(b.indices)
		return
	}
	return {data = slice.to_bytes(b.vertices[:]), indices = b.indices[:], bounds = b.bounds}, true
}

// Splits a glb into its json and binary chunks. The binary chunk is optional
// in the container but not here, because a mesh has to come from somewhere.
@(private = "file")
glb_chunks :: proc(glb: []byte) -> (document, bin: []byte, ok: bool) {
	// magic, version, total length.
	if len(glb) < 12 || read_u32(glb, 0) != GLB_MAGIC || read_u32(glb, 4) != 2 {
		return
	}
	total := u64(read_u32(glb, 8))
	if total > u64(len(glb)) {
		return
	}

	// Each chunk is a length and a type followed by its padded bytes.
	at := u64(12)
	for at + 8 <= total {
		length := u64(read_u32(glb, at))
		kind := read_u32(glb, at + 4)
		start := at + 8
		if start + length > total {
			return
		}
		switch kind {
		case GLB_JSON:
			document = glb[start:][:length]
		case GLB_BIN:
			bin = glb[start:][:length]
		}
		// Chunks are padded to a four byte boundary.
		at = start + (length + 3) & ~u64(3)
	}
	return document, bin, document != nil && bin != nil
}

// Walks node and its children, baking each one's transform into the positions
// of the mesh it holds. parent is the transform of everything above it.
@(private = "file")
gltf_node :: proc(doc: ^GltfDoc, bin: []byte, index: u32, parent: Mat4, b: ^Builder) -> bool {
	if int(index) >= len(doc.nodes) {
		return false
	}
	node := doc.nodes[index]
	world := parent * node_matrix(node)

	if mesh, has_mesh := node.mesh.?; has_mesh {
		if int(mesh) >= len(doc.meshes) {
			return false
		}
		for primitive in doc.meshes[mesh].primitives {
			if !gltf_primitive(doc, bin, primitive, world, b) {
				return false
			}
		}
	}
	for child in node.children {
		if !gltf_node(doc, bin, child, world, b) {
			return false
		}
	}
	return true
}

// A node's local transform, from its matrix if it has one and from its
// translation, rotation and scale otherwise.
@(private = "file")
node_matrix :: proc(node: GltfNode) -> Mat4 {
	if local, has_matrix := node.local.?; has_matrix {
		m: Mat4
		// gltf stores the matrix in column major order.
		for column in 0 ..< 4 {
			for row in 0 ..< 4 {
				m[row, column] = local[column * 4 + row]
			}
		}
		return m
	}
	// gltf writes a quaternion as xyzw, which is not the order a quaternion
	// literal takes.
	r := node.rotation.? or_else {0, 0, 0, 1}
	return transform_matrix(
		Transform {
			pos = node.translation.? or_else {0, 0, 0},
			rot = quaternion(x = r[0], y = r[1], z = r[2], w = r[3]),
			scale = node.scale.? or_else {1, 1, 1},
		},
	)
}

// Appends one primitive's triangles, transformed by world and colored by its
// material's base color factor.
@(private = "file")
gltf_primitive :: proc(doc: ^GltfDoc, bin: []byte, primitive: GltfPrimitive, world: Mat4, b: ^Builder) -> bool {
	if (primitive.mode.? or_else MODE_TRIANGLES) != MODE_TRIANGLES {
		return false
	}
	position, has_position := primitive.attributes["POSITION"]
	if !has_position {
		return false
	}
	positions, position_stride, count, position_ok := accessor(doc, bin, position, "VEC3", COMPONENT_F32)
	if !position_ok {
		return false
	}

	// An untextured mesh carries its color per material, so uvs are read only
	// to fill the vertex layout.
	uvs: []byte
	uv_stride: u32
	if uv, has_uv := primitive.attributes["TEXCOORD_0"]; has_uv {
		uv_count: u32
		uv_ok: bool
		uvs, uv_stride, uv_count, uv_ok = accessor(doc, bin, uv, "VEC2", COMPONENT_F32)
		if !uv_ok || uv_count != count {
			return false
		}
	}

	// A primitive that ships no normals is left facing straight up, which is
	// as much as can be said about it without rebuilding them from the faces.
	normals: []byte
	normal_stride: u32
	if normal, has_normal := primitive.attributes["NORMAL"]; has_normal {
		normal_count: u32
		normal_ok: bool
		normals, normal_stride, normal_count, normal_ok = accessor(doc, bin, normal, "VEC3", COMPONENT_F32)
		if !normal_ok || normal_count != count {
			return false
		}
	}
	to_normal := normal_matrix(world)

	color := Vec4{1, 1, 1, 1}
	if material, has_material := primitive.material.?; has_material {
		if int(material) >= len(doc.materials) {
			return false
		}
		if pbr, has_pbr := doc.materials[material].pbr.?; has_pbr {
			color = pbr.base_color.? or_else color
		}
	}

	base := u64(len(b.vertices))
	if base + u64(count) > u64(max(Index)) {
		return false
	}
	for i in 0 ..< count {
		local := read_at(Vec3, positions, position_stride, i)
		projected := world * Vec4{local.x, local.y, local.z, 1}
		pos := Vec3{projected.x, projected.y, projected.z}
		b.bounds.min = vec3_min(b.bounds.min, pos)
		b.bounds.max = vec3_max(b.bounds.max, pos)
		normal := Vec3{0, 1, 0}
		if normals != nil {
			normal = transform_normal(to_normal, read_at(Vec3, normals, normal_stride, i))
		}
		append(
			&b.vertices,
			Vertex {
				pos = pos,
				color = color,
				uv = uvs == nil ? {} : read_at(Vec2, uvs, uv_stride, i),
				normal = normal,
			},
		)
	}

	// An unindexed primitive is count vertices taken in order.
	indices, has_indices := primitive.indices.?
	if !has_indices {
		if count % 3 != 0 {
			return false
		}
		for i in 0 ..< count {
			append(&b.indices, Index(base) + Index(i))
		}
		return true
	}
	return gltf_indices(doc, bin, indices, Index(base), count, b)
}

// Appends an index accessor, widened to Index and offset to the vertices the
// primitive just appended.
@(private = "file")
gltf_indices :: proc(doc: ^GltfDoc, bin: []byte, index: u32, base: Index, vertices: u32, b: ^Builder) -> bool {
	if int(index) >= len(doc.accessors) {
		return false
	}
	component := doc.accessors[index].component_type
	switch component {
	case COMPONENT_U8, COMPONENT_U16, COMPONENT_U32:
	case:
		return false
	}
	data, stride, count, ok := accessor(doc, bin, index, "SCALAR", component)
	if !ok || count % 3 != 0 {
		return false
	}
	for i in 0 ..< count {
		value: u32
		switch component {
		case COMPONENT_U8:
			value = u32(read_at(u8, data, stride, i))
		case COMPONENT_U16:
			value = u32(read_at(u16, data, stride, i))
		case COMPONENT_U32:
			value = read_at(u32, data, stride, i)
		}
		if value >= vertices {
			return false
		}
		append(&b.indices, base + Index(value))
	}
	return true
}

// The bytes an accessor's elements live in and the stride between them. Fails
// unless the accessor is count elements of kind and component packed inside
// the glb's own binary chunk.
@(private = "file")
accessor :: proc(
	doc: ^GltfDoc,
	bin: []byte,
	index: u32,
	kind: string,
	component: u32,
) -> (
	data: []byte,
	stride, count: u32,
	ok: bool,
) {
	if int(index) >= len(doc.accessors) {
		return
	}
	a := doc.accessors[index]
	if a.kind != kind || a.component_type != component || a.count == 0 {
		return
	}
	// An accessor without a buffer view reads as zeroes, which only a sparse
	// accessor has any use for.
	view_index, has_view := a.buffer_view.?
	if !has_view || int(view_index) >= len(doc.buffer_views) {
		return
	}
	view := doc.buffer_views[view_index]
	// Buffer zero is the binary chunk; any other is a file the engine cannot
	// reach.
	if view.buffer != 0 {
		return
	}

	element := component_size(component) * component_count(kind)
	if element == 0 {
		return
	}
	stride = view.byte_stride.? or_else element
	if stride < element {
		return
	}

	start := u64(view.byte_offset) + u64(a.byte_offset)
	end := start + u64(stride) * u64(a.count - 1) + u64(element)
	if end > u64(view.byte_offset) + u64(view.byte_length) || end > u64(len(bin)) {
		return
	}
	return bin[start:end], stride, a.count, true
}

@(private = "file")
component_size :: proc(component: u32) -> u32 {
	switch component {
	case COMPONENT_U8:
		return 1
	case COMPONENT_U16:
		return 2
	case COMPONENT_U32, COMPONENT_F32:
		return 4
	}
	return 0
}

@(private = "file")
component_count :: proc(kind: string) -> u32 {
	switch kind {
	case "SCALAR":
		return 1
	case "VEC2":
		return 2
	case "VEC3":
		return 3
	case "VEC4":
		return 4
	}
	return 0
}

// Element i of a strided accessor. gltf only aligns elements to their
// component size, so the read cannot assume T's alignment.
@(private = "file")
read_at :: proc($T: typeid, data: []byte, stride, i: u32) -> T {
	return intrinsics.unaligned_load((^T)(raw_data(data[u64(stride) * u64(i):])))
}

// A little endian u32 at a byte offset, for the container's headers.
@(private = "file")
read_u32 :: proc(bytes: []byte, at: u64) -> u32 {
	return u32(bytes[at]) | u32(bytes[at + 1]) << 8 | u32(bytes[at + 2]) << 16 | u32(bytes[at + 3]) << 24
}

@(private = "file")
vec3_min :: proc(a, b: Vec3) -> Vec3 {
	return {min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)}
}

@(private = "file")
vec3_max :: proc(a, b: Vec3) -> Vec3 {
	return {max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)}
}
