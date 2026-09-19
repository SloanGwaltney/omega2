package engine

import "vendor:wgpu"

UNLIT_SHADER :: #load("shaders/unlit.wgsl", string)
LIT_SHADER :: #load("shaders/lit.wgsl", string)
UI_SHADER :: #load("shaders/ui.wgsl", string)

// Vertex layout consumed by the world pipelines. The unlit one ignores the
// normal.
Vertex :: struct {
	pos:    Vec3,
	color:  Vec4,
	uv:     Vec2,
	normal: Vec3,
}

// A key light and the hemisphere fill standing in for bounced light, which is
// what the lit pipeline shades with. Colors are linear, direction points at
// the light and must be normalized.
//
// The padding is the std140 rule the shader reads this under: a vec3 is four
// bytes short of the sixteen it is aligned to.
Light :: struct {
	direction: Vec3,
	_pad0:     f32,
	color:     Vec3,
	_pad1:     f32,
	sky:       Vec3,
	_pad2:     f32,
	ground:    Vec3,
	_pad3:     f32,
}

// A key from the front upper left over a cool sky and warm ground fill, close
// enough to blender's default studio light to make an export recognisable.
// Key and sky sum to one, so a surface facing the light keeps its base color.
LIGHT_DEFAULT :: Light {
	direction = {0.408, 0.816, 0.408},
	color     = {0.8, 0.8, 0.8},
	sky       = {0.16, 0.18, 0.2},
	ground    = {0.1, 0.09, 0.08},
}

// Vertex layout consumed by the ui pipeline. Positions are in pixels, with the
// origin at the top left of the window.
UiVertex :: struct {
	pos:   Vec3,
	color: Vec4,
	uv:    Vec2,
}

// The wgpu pipeline backing a Pipeline value.
pipeline_handle :: proc(app: ^App, pipeline: Pipeline) -> wgpu.RenderPipeline {
	switch pipeline {
	case .Unlit:
		return app.render.unlit_pipeline
	case .Lit:
		return app.render.lit_pipeline
	}
	panic("unknown pipeline")
}

// Builds the frame bind group: the camera view projection matrix, the array of
// model matrices and the ui pixels to clip space matrix, all shared by every
// pipeline and rewritten each frame.
create_frame_bind_group :: proc(app: ^App) {
	entries := [?]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Vertex}, buffer = {type = .Uniform, minBindingSize = size_of(Mat4)}},
		{binding = 1, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage, minBindingSize = size_of(Mat4)}},
		{binding = 2, visibility = {.Vertex}, buffer = {type = .Uniform, minBindingSize = size_of(Mat4)}},
		{binding = 3, visibility = {.Fragment}, buffer = {type = .Uniform, minBindingSize = size_of(Light)}},
	}
	app.render.frame_layout = wgpu.DeviceCreateBindGroupLayout(
		app.window.device,
		&{label = "frame", entryCount = len(entries), entries = &entries[0]},
	)
	if app.render.frame_layout == nil {
		panic("failed to create frame bind group layout")
	}

	bindings := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = app.render.camera_uniform.handle, size = app.render.camera_uniform.size},
		{binding = 1, buffer = app.render.models.handle, size = app.render.models.size},
		{binding = 2, buffer = app.render.ui_uniform.handle, size = app.render.ui_uniform.size},
		{binding = 3, buffer = app.render.light_uniform.handle, size = app.render.light_uniform.size},
	}
	app.render.frame_bind_group = wgpu.DeviceCreateBindGroup(
		app.window.device,
		&{label = "frame", layout = app.render.frame_layout, entryCount = len(bindings), entries = &bindings[0]},
	)
	if app.render.frame_bind_group == nil {
		panic("failed to create frame bind group")
	}
}

// Builds a world pipeline from source: one interleaved vertex buffer, the
// frame bind group at group 0, triangle list drawn with an index buffer and
// depth tested against the rest of the world. The index format is supplied at
// draw time, not here, because the topology is not a strip.
@(private = "file")
create_world_pipeline :: proc(app: ^App, label: string, source: string) -> wgpu.RenderPipeline {
	module := wgpu.DeviceCreateShaderModule(
		app.window.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{chain = {sType = .ShaderSourceWGSL}, code = source}},
	)
	if module == nil {
		panic("failed to compile world shader")
	}
	defer wgpu.ShaderModuleRelease(module)

	layouts := [?]wgpu.BindGroupLayout{app.render.frame_layout}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		app.window.device,
		&{label = label, bindGroupLayoutCount = len(layouts), bindGroupLayouts = &layouts[0]},
	)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// A pipeline may leave the normal unread, which wgpu allows; the attribute
	// is declared either way so both share one vertex buffer.
	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = u64(offset_of(Vertex, pos)), shaderLocation = 0},
		{format = .Float32x4, offset = u64(offset_of(Vertex, color)), shaderLocation = 1},
		{format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 2},
		{format = .Float32x3, offset = u64(offset_of(Vertex, normal)), shaderLocation = 3},
	}
	layout := wgpu.VertexBufferLayout {
		stepMode       = .Vertex,
		arrayStride    = size_of(Vertex),
		attributeCount = len(attributes),
		attributes     = &attributes[0],
	}
	depth_stencil := wgpu.DepthStencilState {
		format            = DEPTH_FORMAT,
		depthWriteEnabled = .True,
		depthCompare      = .Less,
	}
	target := wgpu.ColorTargetState {
		format    = app.window.config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module      = module,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &target,
	}

	pipeline := wgpu.DeviceCreateRenderPipeline(
		app.window.device,
		&{
			label = label,
			layout = pipeline_layout,
			vertex = {module = module, entryPoint = "vs_main", bufferCount = 1, buffers = &layout},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .Back},
			depthStencil = &depth_stencil,
			multisample = {count = 1, mask = ~u32(0)},
			fragment = &fragment,
		},
	)
	if pipeline == nil {
		panic("failed to create world pipeline")
	}
	return pipeline
}

// Draws a mesh in its flat vertex colors, ignoring the normal.
create_unlit_pipeline :: proc(app: ^App) {
	app.render.unlit_pipeline = create_world_pipeline(app, "unlit", UNLIT_SHADER)
}

// Draws a mesh shaded by the frame's Light.
create_lit_pipeline :: proc(app: ^App) {
	app.render.lit_pipeline = create_world_pipeline(app, "lit", LIT_SHADER)
}

// Builds the ui pipeline: the same vertex layout and frame bind group as unlit,
// plus a sampled texture at group 1, drawn in screen space with alpha blending,
// no culling and no depth, so it lands on top of the world in the order its
// batches were built.
create_ui_pipeline :: proc(app: ^App) {
	module := wgpu.DeviceCreateShaderModule(
		app.window.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{chain = {sType = .ShaderSourceWGSL}, code = UI_SHADER}},
	)
	if module == nil {
		panic("failed to compile ui shader")
	}
	defer wgpu.ShaderModuleRelease(module)

	layouts := [?]wgpu.BindGroupLayout{app.render.frame_layout, app.render.texture_layout}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		app.window.device,
		&{label = "ui", bindGroupLayoutCount = len(layouts), bindGroupLayouts = &layouts[0]},
	)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = u64(offset_of(UiVertex, pos)), shaderLocation = 0},
		{format = .Float32x4, offset = u64(offset_of(UiVertex, color)), shaderLocation = 1},
		{format = .Float32x2, offset = u64(offset_of(UiVertex, uv)), shaderLocation = 2},
	}
	layout := wgpu.VertexBufferLayout {
		stepMode       = .Vertex,
		arrayStride    = size_of(UiVertex),
		attributeCount = len(attributes),
		attributes     = &attributes[0],
	}
	depth_stencil := wgpu.DepthStencilState {
		format            = DEPTH_FORMAT,
		depthWriteEnabled = .False,
		depthCompare      = .Always,
	}
	blend := wgpu.BlendState {
		color = {operation = .Add, srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha},
		alpha = {operation = .Add, srcFactor = .One, dstFactor = .OneMinusSrcAlpha},
	}
	target := wgpu.ColorTargetState {
		format    = app.window.config.format,
		blend     = &blend,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module      = module,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &target,
	}

	app.render.ui_pipeline = wgpu.DeviceCreateRenderPipeline(
		app.window.device,
		&{
			label = "ui",
			layout = pipeline_layout,
			vertex = {module = module, entryPoint = "vs_main", bufferCount = 1, buffers = &layout},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			depthStencil = &depth_stencil,
			multisample = {count = 1, mask = ~u32(0)},
			fragment = &fragment,
		},
	)
	if app.render.ui_pipeline == nil {
		panic("failed to create ui pipeline")
	}
}
