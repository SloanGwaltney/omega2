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

// How much of the key a surface mirrors back when faced head on. A real
// dielectric returns about four percent, but one directional light is standing
// in for a whole environment here, so it is left far higher than that and set
// instead to land the peak inside the tone map's rolloff rather than clipping.
const SPECULAR_STRENGTH: f32 = 0.35;

// Narkowicz's curve fit to the aces filmic tone map. Rolls a highlight off
// towards white instead of clipping at it, which is what keeps a bright
// specular from reading as a flat white patch.
fn tonemap(c: vec3<f32>) -> vec3<f32> {
	let a = 2.51;
	let b = 0.03;
	let d = 2.43;
	let e = 0.59;
	let f = 0.14;
	return clamp((c * (a * c + b)) / (c * (d * c + e) + f), vec3<f32>(0.0), vec3<f32>(1.0));
}

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
	// Schlick: a surface mirrors far more at a grazing angle than head on,
	// which is what puts a sheen along the edge of a round shape.
	let grazing = pow(1.0 - max(dot(half_dir, view_dir), 0.0), 5.0);
	let fresnel = SPECULAR_STRENGTH + (1.0 - SPECULAR_STRENGTH) * grazing;

	let lit = in.color.rgb * (key + fill) + gloss * fresnel * light.color;
	return vec4<f32>(tonemap(lit), in.color.a);
}
