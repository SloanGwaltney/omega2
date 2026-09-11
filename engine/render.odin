package engine

import "vendor:wgpu"

CLEAR_COLOR :: wgpu.Color{0.1, 0.1, 0.12, 1.0}

// wgpu handles that live only for the current frame. Created by
// start_render_pass_system and released by end_render_pass_system.
Frame :: struct {
	surface_texture: wgpu.SurfaceTexture,
	view:            wgpu.TextureView,
	encoder:         wgpu.CommandEncoder,
	pass:            wgpu.RenderPassEncoder,
}

// Acquires the swapchain texture and begins a render pass that clears to CLEAR_COLOR.
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
	frame.pass = wgpu.CommandEncoderBeginRenderPass(
		frame.encoder,
		&{colorAttachmentCount = 1, colorAttachments = &attachment},
	)
}

// Draws every entity with a Drawable from the shared gpu buffers.
draw_render_system :: proc(app: ^App) {
	w := app.world
	pass := app.frame.pass
	for i in 0 ..< w.count {
		drawable := pool_get(&w.drawable, Entity(i))
		if drawable == nil {
			continue
		}
		layout := pipeline_layout(drawable.pipeline)
		wgpu.RenderPassEncoderSetPipeline(pass, pipeline_handle(app, drawable.pipeline))
		wgpu.RenderPassEncoderSetVertexBuffer(
			pass,
			0,
			vertex_buffer(app, layout).handle,
			drawable.offsets.vertex,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			pass,
			app.indices.handle,
			INDEX_FORMAT,
			drawable.offsets.index,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(pass, drawable.index_count, 1, 0, 0, 0)
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
