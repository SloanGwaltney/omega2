struct VertexIn {
	@location(0) pos: vec3<f32>,
	@location(1) color: vec4<f32>,
	@location(2) uv: vec2<f32>,
}

struct VertexOut {
	@builtin(position) clip_pos: vec4<f32>,
	@location(0) color: vec4<f32>,
	@location(1) uv: vec2<f32>,
}

@group(0) @binding(0) var<uniform> view_proj: mat4x4<f32>;
// Model matrices packed in draw order, reached through the draw's firstInstance.
@group(0) @binding(1) var<storage, read> models: array<mat4x4<f32>>;

@vertex
fn vs_main(in: VertexIn, @builtin(instance_index) instance: u32) -> VertexOut {
	var out: VertexOut;
	out.clip_pos = view_proj * models[instance] * vec4<f32>(in.pos, 1.0);
	out.color = in.color;
	out.uv = in.uv;
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	return in.color;
}
