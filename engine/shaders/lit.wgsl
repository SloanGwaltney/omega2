struct VertexIn {
	@location(0) pos: vec3<f32>,
	@location(1) color: vec4<f32>,
	@location(2) uv: vec2<f32>,
	@location(3) normal: vec3<f32>,
}

struct VertexOut {
	@builtin(position) clip_pos: vec4<f32>,
	@location(0) color: vec4<f32>,
	@location(1) uv: vec2<f32>,
	@location(2) normal: vec3<f32>,
}

// A key light and the hemisphere fill, matching engine.Light.
struct Light {
	direction: vec3<f32>,
	color: vec3<f32>,
	sky: vec3<f32>,
	ground: vec3<f32>,
}

@group(0) @binding(0) var<uniform> view_proj: mat4x4<f32>;
// Model matrices packed in draw order, reached through the draw's firstInstance.
@group(0) @binding(1) var<storage, read> models: array<mat4x4<f32>>;
@group(0) @binding(3) var<uniform> light: Light;

@vertex
fn vs_main(in: VertexIn, @builtin(instance_index) instance: u32) -> VertexOut {
	let model = models[instance];
	var out: VertexOut;
	out.clip_pos = view_proj * model * vec4<f32>(in.pos, 1.0);
	out.color = in.color;
	out.uv = in.uv;
	// Rotating the normal by the model matrix only holds for a uniform scale,
	// which is what entity transforms are expected to carry. Normalizing here
	// absorbs that scale; a non uniform one would skew the normal instead.
	out.normal = (model * vec4<f32>(in.normal, 0.0)).xyz;
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	// Interpolating across the triangle shortens the normal, so it is rescaled
	// per fragment rather than per vertex.
	let n = normalize(in.normal);
	let key = max(dot(n, light.direction), 0.0) * light.color;
	// The fill stands in for bounced light: sky straight up, ground straight
	// down, blended by how far the normal leans between them.
	let fill = mix(light.ground, light.sky, n.y * 0.5 + 0.5);
	return vec4<f32>(in.color.rgb * (key + fill), in.color.a);
}
