package engine

import "vendor:wgpu"

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

// Creates the depth texture at the current surface size. Must be recreated
// whenever the surface is resized.
create_depth_texture :: proc(app: ^App) {
	app.depth_texture = wgpu.DeviceCreateTexture(
		app.device,
		&{
			label = "depth",
			usage = {.RenderAttachment},
			dimension = ._2D,
			size = {app.surface_config.width, app.surface_config.height, 1},
			format = DEPTH_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if app.depth_texture == nil {
		panic("failed to create depth texture")
	}
	app.depth_view = wgpu.TextureCreateView(app.depth_texture)
}

delete_depth_texture :: proc(app: ^App) {
	wgpu.TextureViewRelease(app.depth_view)
	wgpu.TextureRelease(app.depth_texture)
}

// Acquires the swapchain texture and begins a render pass that clears the
// color target to CLEAR_COLOR and the depth target to the far plane.
start_render_pass_system :: proc(app: ^App) {
	frame := &app.frame
	frame.surface_texture = wgpu.SurfaceGetCurrentTexture(app.surface)
	switch frame.surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	case .Timeout, .Outdated, .Lost, .Error, .Occluded:
		panic("failed to acquire surface texture")
	}

	frame.view = wgpu.TextureCreateView(frame.surface_texture.texture)
	frame.encoder = wgpu.DeviceCreateCommandEncoder(app.device)

	attachment := wgpu.RenderPassColorAttachment {
		view       = frame.view,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = CLEAR_COLOR,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view            = app.depth_view,
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
	view_proj := [1]Mat4{camera_view_proj(app)}
	gpu_buffer_write(app, &app.camera_uniform, view_proj[:])
	ui_proj := [1]Mat4{ortho_screen(f32(app.surface_config.width), f32(app.surface_config.height))}
	gpu_buffer_write(app, &app.ui_uniform, ui_proj[:])

	app.batch_count = 0
	drawn: u32
	for i in 0 ..< w.count {
		e := Entity(i)
		drawable := pool_get(&w.drawable, e)
		if drawable == nil {
			continue
		}
		b := batch_for(app, drawable)
		app.batches[b].count += 1
		app.drawn[drawn] = {entity = e, batch = b}
		drawn += 1
	}

	next: u32
	for &batch in app.batches[:app.batch_count] {
		batch.first_instance = next
		next += batch.count
		// Reused below as the write cursor, ending back at the count.
		batch.count = 0
	}

	for entry in app.drawn[:drawn] {
		batch := &app.batches[entry.batch]
		transform := pool_get(&w.transform, entry.entity)
		app.model_matrices[batch.first_instance + batch.count] =
			transform == nil ? MAT4_IDENTITY : transform_matrix(transform^)
		batch.count += 1
	}
	{
		zone_begin(.ModelUpload)
		gpu_buffer_write(app, &app.models, app.model_matrices[:next])
	}
}

// Index of the batch matching drawable, appended if this frame has not seen
// it yet.
@(private)
batch_for :: proc(app: ^App, drawable: ^Drawable) -> u32 {
	for batch, i in app.batches[:app.batch_count] {
		if batch.pipeline == drawable.pipeline && batch.offsets == drawable.offsets {
			return u32(i)
		}
	}
	assert(app.batch_count < MAX_BATCHES, "out of draw batches")
	app.batches[app.batch_count] = Batch {
		pipeline    = drawable.pipeline,
		offsets     = drawable.offsets,
		index_count = drawable.index_count,
	}
	app.batch_count += 1
	return u32(app.batch_count - 1)
}

// Draws every batch, one instanced draw each, with the pipeline and its vertex
// buffer bound once per pipeline group.
draw_render_system :: proc(app: ^App) {
	pass := app.frame.pass
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.frame_bind_group)

	for pipeline in Pipeline {
		bound := false
		stride := layout_stride(pipeline_layout(pipeline))
		for batch in app.batches[:app.batch_count] {
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
	frame := &app.frame
	wgpu.RenderPassEncoderEnd(frame.pass)

	command_buffer := wgpu.CommandEncoderFinish(frame.encoder)
	wgpu.QueueSubmit(app.queue, {command_buffer})
	wgpu.SurfacePresent(app.surface)

	wgpu.CommandBufferRelease(command_buffer)
	wgpu.RenderPassEncoderRelease(frame.pass)
	wgpu.CommandEncoderRelease(frame.encoder)
	wgpu.TextureViewRelease(frame.view)
	wgpu.TextureRelease(frame.surface_texture.texture)
	frame^ = {}
}
