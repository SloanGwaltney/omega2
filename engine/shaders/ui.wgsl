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

// Pixels to clip space, rebuilt whenever the surface is resized.
@group(0) @binding(2) var<uniform> ui_proj: mat4x4<f32>;

@group(1) @binding(0) var ui_texture: texture_2d<f32>;
@group(1) @binding(1) var ui_sampler: sampler;

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
	var out: VertexOut;
	out.clip_pos = ui_proj * vec4<f32>(in.pos, 1.0);
	out.color = in.color;
	out.uv = in.uv;
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	return in.color * textureSample(ui_texture, ui_sampler, in.uv);
}
