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

// Undoes the srgb encoding of a color, so the surface's encode on write lands
// back on the authored value.
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
	let low = c / 12.92;
	let high = pow((c + 0.055) / 1.055, vec3<f32>(2.4));
	return select(high, low, c <= vec3<f32>(0.04045));
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
	var out: VertexOut;
	out.clip_pos = ui_proj * vec4<f32>(in.pos, 1.0);
	// Ui colors are authored in srgb, so they are converted here and blended
	// linearly with everything else the frame wrote.
	out.color = vec4<f32>(srgb_to_linear(in.color.rgb), in.color.a);
	out.uv = in.uv;
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	return in.color * textureSample(ui_texture, ui_sampler, in.uv);
}
