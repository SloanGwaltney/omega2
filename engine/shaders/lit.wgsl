struct VertexIn {
	@location(0) pos: vec3<f32>,
	@location(1) color: vec4<f32>,
	@location(2) uv: vec2<f32>,
	@location(3) normal: vec3<f32>,
	@location(4) roughness: f32,
}

struct VertexOut {
	@builtin(position) clip_pos: vec4<f32>,
	@location(0) color: vec4<f32>,
	@location(1) uv: vec2<f32>,
	@location(2) normal: vec3<f32>,
	@location(3) roughness: f32,
	@location(4) world_pos: vec3<f32>,
}

// A key light, the hemisphere fill and the eye, matching engine.Light.
struct Light {
	direction: vec3<f32>,
	color: vec3<f32>,
	sky: vec3<f32>,
	ground: vec3<f32>,
	eye: vec3<f32>,
}

// How tight the highlight gets as roughness falls to zero. Blinn-Phong has no
// physical exponent, so this is picked to land near blender's preview.
const MAX_SHININESS: f32 = 256.0;

@group(0) @binding(0) var<uniform> view_proj: mat4x4<f32>;
// Model matrices packed in draw order, reached through the draw's firstInstance.
@group(0) @binding(1) var<storage, read> models: array<mat4x4<f32>>;
@group(0) @binding(3) var<uniform> light: Light;

@vertex
fn vs_main(in: VertexIn, @builtin(instance_index) instance: u32) -> VertexOut {
	let model = models[instance];
	let world = model * vec4<f32>(in.pos, 1.0);
	var out: VertexOut;
	out.clip_pos = view_proj * world;
	out.color = in.color;
	out.uv = in.uv;
	// Rotating the normal by the model matrix only holds for a uniform scale,
	// which is what entity transforms are expected to carry. Normalizing in the
	// fragment absorbs that scale; a non uniform one would skew the normal.
	out.normal = (model * vec4<f32>(in.normal, 0.0)).xyz;
	out.roughness = in.roughness;
	out.world_pos = world.xyz;
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	// Interpolating across the triangle shortens the normal, so it is rescaled
	// per fragment rather than per vertex.
	let n = normalize(in.normal);
	let roughness = clamp(in.roughness, 0.03, 1.0);

	let lambert = max(dot(n, light.direction), 0.0);
	let key = lambert * light.color;
	// The fill stands in for bounced light: sky straight up, ground straight
	// down, blended by how far the normal leans between them.
	let fill = mix(light.ground, light.sky, n.y * 0.5 + 0.5);

	// Blinn-Phong: the highlight peaks where the normal splits the angle
	// between the light and the eye.
	let view_dir = normalize(light.eye - in.world_pos);
	let half_dir = normalize(view_dir + light.direction);
	let shininess = MAX_SHININESS * (1.0 - roughness) * (1.0 - roughness);
	// A rough surface spreads the same energy over a wider lobe, so it is
	// dimmed as it is widened. Near enough the blinn-phong normalizing term.
	let spread = (shininess + 8.0) / 24.0;
	// Weighted by the key, so a face turned away from the light carries no
	// highlight however the eye is placed.
	let gloss = pow(max(dot(n, half_dir), 0.0), shininess) * spread * lambert;

	return vec4<f32>(in.color.rgb * (key + fill) + gloss * light.color, in.color.a);
}
