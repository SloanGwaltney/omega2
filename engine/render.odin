package engine

import "vendor:wgpu"

// Written to the surface as it stands. Unlike a color a shader writes, a clear
// value is not srgb encoded on the way in, so this is already a display value.
CLEAR_COLOR :: wgpu.Color{0.1, 0.1, 0.12, 1.0}
DEPTH_FORMAT :: wgpu.TextureFormat.Depth32Float

// wgpu handles that live only for the current frame. Created by
// start_render_pass_system and released by end_render_pass_system.
Frame :: struct {
	surface_texture: wgpu.SurfaceTexture,
	view:            wgpu.TextureView,
	encoder:         wgpu.CommandEncoder,
	pass:            wgpu.RenderPassEncoder,
}

// The gpu resources the frame is drawn with, and the per frame staging that
// feeds them.
Render :: struct {
	frame:            Frame,
	depth_texture:    wgpu.Texture,
	depth_view:       wgpu.TextureView,
	unlit_pipeline:   wgpu.RenderPipeline,
	lit_pipeline:     wgpu.RenderPipeline,
	ui_pipeline:      wgpu.RenderPipeline,
	mesh_vertices:    GpuBuffer,
	ui_vertices:      GpuBuffer,
	ui_indices:       GpuBuffer,
	indices:          GpuBuffer,
	camera_uniform:   GpuBuffer,
	ui_uniform:       GpuBuffer,
	light_uniform:    GpuBuffer,
	models:           GpuBuffer,
	// What the lit pipeline shades with, uploaded every frame so the game can
	// change it whenever it likes.
	light:            Light,
	frame_layout:     wgpu.BindGroupLayout,
	frame_bind_group: wgpu.BindGroup,
	texture_layout:   wgpu.BindGroupLayout,
	// Bound by the ui unless the frame chose its own texture. Carries the
	// glyphs and the white texel flat quads sample.
	font:             Font,
	// Staging for models, packed in draw order and uploaded whole each frame.
	model_matrices:   [MAX_ENTITIES]Mat4,
	// Draw batches rebuilt each frame from the drawables.
	batches:          [MAX_BATCHES]Batch,
	batch_count:      int,
	// This frame's drawable entities and the batch each landed in, so the
	// second pass does not rescan the pools or the batch list.
	drawn:            [MAX_ENTITIES]DrawEntry,
	meshes:           MeshStorage,
}

// Builds the depth texture, buffers, bind groups, font and pipelines. The
// window must already hold a device.
@(private)
create_render :: proc(app: ^App) {
	create_depth_texture(app)
	create_buffers(app)
	create_frame_bind_group(app)
	create_texture_layout(app)
	create_font(app)
	create_unlit_pipeline(app)
	create_lit_pipeline(app)
	create_ui_pipeline(app)
	// Written now as well as every frame, because icons are baked before the
	// first frame gets the chance to.
	app.render.light = LIGHT_DEFAULT
	gpu_buffer_write(app, &app.render.light_uniform, []Light{LIGHT_DEFAULT})
}

@(private)
delete_render :: proc(app: ^App) {
	delete_mesh_storage(&app.render.meshes)
	delete_depth_texture(app)
	delete_buffers(app)
	wgpu.RenderPipelineRelease(app.render.unlit_pipeline)
	wgpu.RenderPipelineRelease(app.render.lit_pipeline)
	wgpu.RenderPipelineRelease(app.render.ui_pipeline)
	delete_font(&app.render.font)
	wgpu.BindGroupLayoutRelease(app.render.texture_layout)
	wgpu.BindGroupRelease(app.render.frame_bind_group)
	wgpu.BindGroupLayoutRelease(app.render.frame_layout)
}

// Creates the depth texture at the current surface size. Must be recreated
// whenever the surface is resized.
create_depth_texture :: proc(app: ^App) {
	app.render.depth_texture = wgpu.DeviceCreateTexture(
		app.window.device,
		&{
			label = "depth",
			usage = {.RenderAttachment},
			dimension = ._2D,
			size = {app.window.config.width, app.window.config.height, 1},
			format = DEPTH_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if app.render.depth_texture == nil {
		panic("failed to create depth texture")
	}
	app.render.depth_view = wgpu.TextureCreateView(app.render.depth_texture)
}

delete_depth_texture :: proc(app: ^App) {
	wgpu.TextureViewRelease(app.render.depth_view)
	wgpu.TextureRelease(app.render.depth_texture)
}

// Acquires the swapchain texture and begins a render pass that clears the
// color target to CLEAR_COLOR and the depth target to the far plane.
start_render_pass_system :: proc(app: ^App) {
	frame := &app.render.frame
	frame.surface_texture = wgpu.SurfaceGetCurrentTexture(app.window.surface)
	switch frame.surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	case .Timeout, .Outdated, .Lost, .Error, .Occluded:
		panic("failed to acquire surface texture")
	}

	frame.view = wgpu.TextureCreateView(frame.surface_texture.texture)
	frame.encoder = wgpu.DeviceCreateCommandEncoder(app.window.device)

	attachment := wgpu.RenderPassColorAttachment {
		view       = frame.view,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = CLEAR_COLOR,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view            = app.render.depth_view,
		depthLoadOp     = .Clear,
		depthStoreOp    = .Store,
		depthClearValue = 1.0,
	}
	frame.pass = wgpu.CommandEncoderBeginRenderPass(
		frame.encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
}

// Entities sharing a pipeline and a mesh, drawn with one instanced draw. Their
// model matrices are contiguous in the model buffer starting at first_instance.
Batch :: struct {
	pipeline:       Pipeline,
	offsets:        BufferOffsets,
	index_count:    u32,
	first_instance: u32,
	count:          u32,
}

MAX_BATCHES :: 64

// An entity to draw and the index of the batch it belongs to.
DrawEntry :: struct {
	entity: Entity,
	batch:  u32,
}

// Writes the camera and ui matrices to the gpu and builds this frame's batches, packing
// the model matrices of each batch's entities contiguously into the model
// buffer. An entity without a Transform gets the identity.
upload_frame_uniforms_system :: proc(app: ^App) #no_bounds_check {
	zone_begin(.FrameUniforms)
	w := app.world
	proj, eye := camera_view_proj(app)
	view_proj := [1]Mat4{proj}
	gpu_buffer_write(app, &app.render.camera_uniform, view_proj[:])
	app.render.light.eye = eye
	ui_proj := [1]Mat4{ortho_screen(f32(app.window.config.width), f32(app.window.config.height))}
	gpu_buffer_write(app, &app.render.ui_uniform, ui_proj[:])
	light := [1]Light{app.render.light}
	gpu_buffer_write(app, &app.render.light_uniform, light[:])

	app.render.batch_count = 0
	drawn: u32
	for i in 0 ..< w.count {
		e := Entity(i)
		drawable := pool_get(&w.drawable, e)
		if drawable == nil {
			continue
		}
		b := batch_for(app, drawable)
		app.render.batches[b].count += 1
		app.render.drawn[drawn] = {entity = e, batch = b}
		drawn += 1
	}

	next: u32
	for &batch in app.render.batches[:app.render.batch_count] {
		batch.first_instance = next
		next += batch.count
		// Reused below as the write cursor, ending back at the count.
		batch.count = 0
	}

	for entry in app.render.drawn[:drawn] {
		batch := &app.render.batches[entry.batch]
		transform := pool_get(&w.transform, entry.entity)
		app.render.model_matrices[batch.first_instance + batch.count] =
			transform == nil ? MAT4_IDENTITY : transform_matrix(transform^)
		batch.count += 1
	}
	{
		zone_begin(.ModelUpload)
		gpu_buffer_write(app, &app.render.models, app.render.model_matrices[:next])
	}
}

// Index of the batch matching drawable, appended if this frame has not seen
// it yet.
@(private)
batch_for :: proc(app: ^App, drawable: ^Drawable) -> u32 {
	for batch, i in app.render.batches[:app.render.batch_count] {
		if batch.pipeline == drawable.pipeline && batch.offsets == drawable.offsets {
			return u32(i)
		}
	}
	assert(app.render.batch_count < MAX_BATCHES, "out of draw batches")
	app.render.batches[app.render.batch_count] = Batch {
		pipeline    = drawable.pipeline,
		offsets     = drawable.offsets,
		index_count = drawable.index_count,
	}
	app.render.batch_count += 1
	return u32(app.render.batch_count - 1)
}

// Draws every batch, one instanced draw each, with the pipeline and its vertex
// buffer bound once per pipeline group.
draw_render_system :: proc(app: ^App) {
	pass := app.render.frame.pass
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.render.indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.render.frame_bind_group)

	for pipeline in Pipeline {
		bound := false
		stride := layout_stride(pipeline_layout(pipeline))
		for batch in app.render.batches[:app.render.batch_count] {
			if batch.pipeline != pipeline {
				continue
			}
			if !bound {
				wgpu.RenderPassEncoderSetPipeline(pass, pipeline_handle(app, pipeline))
				wgpu.RenderPassEncoderSetVertexBuffer(
					pass,
					0,
					vertex_buffer(app, pipeline_layout(pipeline)).handle,
					0,
					wgpu.WHOLE_SIZE,
				)
				bound = true
			}
			wgpu.RenderPassEncoderDrawIndexed(
				pass,
				batch.index_count,
				batch.count,
				u32(batch.offsets.index / size_of(Index)),
				i32(batch.offsets.vertex / stride),
				batch.first_instance,
			)
		}
	}
}

// Ends the pass, submits the frame, presents it and releases the frame handles.
end_render_pass_system :: proc(app: ^App) {
	frame := &app.render.frame
	wgpu.RenderPassEncoderEnd(frame.pass)

	command_buffer := wgpu.CommandEncoderFinish(frame.encoder)
	wgpu.QueueSubmit(app.window.queue, {command_buffer})
	wgpu.SurfacePresent(app.window.surface)

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.RenderPassEncoderRelease(frame.pass)
	wgpu.CommandEncoderRelease(frame.encoder)
	wgpu.TextureViewRelease(frame.view)
	wgpu.TextureRelease(frame.surface_texture.texture)
	frame^ = {}
}
