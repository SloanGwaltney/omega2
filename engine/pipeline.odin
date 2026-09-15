package engine

import "vendor:wgpu"

UNLIT_SHADER :: #load("shaders/unlit.wgsl", string)
UI_SHADER :: #load("shaders/ui.wgsl", string)

// Vertex layout consumed by the unlit pipeline.
Vertex :: struct {
	pos:   Vec3,
	color: Vec4,
	uv:    Vec2,
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
	}
	app.render.frame_bind_group = wgpu.DeviceCreateBindGroup(
		app.window.device,
		&{label = "frame", layout = app.render.frame_layout, entryCount = len(bindings), entries = &bindings[0]},
	)
	if app.render.frame_bind_group == nil {
		panic("failed to create frame bind group")
	}
}

// Builds the unlit pipeline: one interleaved vertex buffer, the frame bind
// group at group 0, triangle list drawn with an index buffer. The index format
// is supplied at draw time, not here, because the topology is not a strip.
create_unlit_pipeline :: proc(app: ^App) {
	module := wgpu.DeviceCreateShaderModule(
		app.window.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{chain = {sType = .ShaderSourceWGSL}, code = UNLIT_SHADER}},
	)
	if module == nil {
		panic("failed to compile unlit shader")
	}
	defer wgpu.ShaderModuleRelease(module)

	layouts := [?]wgpu.BindGroupLayout{app.render.frame_layout}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		app.window.device,
		&{label = "unlit", bindGroupLayoutCount = len(layouts), bindGroupLayouts = &layouts[0]},
	)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = u64(offset_of(Vertex, pos)), shaderLocation = 0},
		{format = .Float32x4, offset = u64(offset_of(Vertex, color)), shaderLocation = 1},
		{format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 2},
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

	app.render.unlit_pipeline = wgpu.DeviceCreateRenderPipeline(
		app.window.device,
		&{
			label = "unlit",
			layout = pipeline_layout,
			vertex = {
				module = module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .Back},
			depthStencil = &depth_stencil,
			multisample = {count = 1, mask = ~u32(0)},
			fragment = &fragment,
		},
	)
	if app.render.unlit_pipeline == nil {
		panic("failed to create unlit pipeline")
	}
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
