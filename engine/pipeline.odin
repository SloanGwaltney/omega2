package engine

import "vendor:wgpu"

UNLIT_SHADER :: #load("shaders/unlit.wgsl", string)

// Vertex layout consumed by the unlit pipeline.
Vertex :: struct {
	pos:   Vec3,
	color: Vec4,
	uv:    Vec2,
}

// The wgpu pipeline backing a Pipeline value.
pipeline_handle :: proc(app: ^App, pipeline: Pipeline) -> wgpu.RenderPipeline {
	switch pipeline {
	case .Unlit:
		return app.unlit_pipeline
	}
	panic("unknown pipeline")
}

// Builds the frame bind group: the camera view projection matrix and the array
// of model matrices, both shared by every pipeline and rewritten each frame.
create_frame_bind_group :: proc(app: ^App) {
	entries := [?]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Vertex}, buffer = {type = .Uniform, minBindingSize = size_of(Mat4)}},
		{binding = 1, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage, minBindingSize = size_of(Mat4)}},
	}
	app.frame_layout = wgpu.DeviceCreateBindGroupLayout(
		app.device,
		&{label = "frame", entryCount = len(entries), entries = &entries[0]},
	)
	if app.frame_layout == nil {
		panic("failed to create frame bind group layout")
	}

	bindings := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = app.camera_uniform.handle, size = app.camera_uniform.size},
		{binding = 1, buffer = app.models.handle, size = app.models.size},
	}
	app.frame_bind_group = wgpu.DeviceCreateBindGroup(
		app.device,
		&{label = "frame", layout = app.frame_layout, entryCount = len(bindings), entries = &bindings[0]},
	)
	if app.frame_bind_group == nil {
		panic("failed to create frame bind group")
	}
}

// Builds the unlit pipeline: one interleaved vertex buffer, the frame bind
// group at group 0, triangle list drawn with an index buffer. The index format
// is supplied at draw time, not here, because the topology is not a strip.
create_unlit_pipeline :: proc(app: ^App) {
	module := wgpu.DeviceCreateShaderModule(
		app.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{chain = {sType = .ShaderSourceWGSL}, code = UNLIT_SHADER}},
	)
	if module == nil {
		panic("failed to compile unlit shader")
	}
	defer wgpu.ShaderModuleRelease(module)

	layouts := [?]wgpu.BindGroupLayout{app.frame_layout}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		app.device,
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
	target := wgpu.ColorTargetState {
		format    = app.surface_config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module      = module,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &target,
	}

	app.unlit_pipeline = wgpu.DeviceCreateRenderPipeline(
		app.device,
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
			multisample = {count = 1, mask = ~u32(0)},
			fragment = &fragment,
		},
	)
	if app.unlit_pipeline == nil {
		panic("failed to create unlit pipeline")
	}
}
