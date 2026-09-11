package engine

import "vendor:wgpu"

UNLIT_SHADER :: #load("shaders/unlit.wgsl", string)

// Vertex layout consumed by the unlit pipeline.
Vertex :: struct {
	pos:   Vec3,
	color: Vec4,
	uv:    Vec2,
}

// Builds the unlit pipeline: one interleaved vertex buffer, no bind groups,
// triangle list drawn with an index buffer. The index format is supplied at
// draw time, not here, because the topology is not a strip.
create_unlit_pipeline :: proc(app: ^App) {
	module := wgpu.DeviceCreateShaderModule(
		app.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{chain = {sType = .ShaderSourceWGSL}, code = UNLIT_SHADER}},
	)
	if module == nil {
		panic("failed to compile unlit shader")
	}
	defer wgpu.ShaderModuleRelease(module)

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
