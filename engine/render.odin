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

// Writes the camera matrix and every entity's model matrix to the gpu. Model
// matrices are indexed by entity id, so a draw selects one through
// firstInstance. An entity without a Transform gets the identity.
upload_frame_uniforms_system :: proc(app: ^App) {
	w := app.world
	view_proj := [1]Mat4{camera_view_proj(app)}
	gpu_buffer_write(app, &app.camera_uniform, view_proj[:])

	for i in 0 ..< w.count {
		e := Entity(i)
		transform := pool_get(&w.transform, e)
		app.model_matrices[e] = transform == nil ? MAT4_IDENTITY : transform_matrix(transform^)
	}
	gpu_buffer_write(app, &app.models, app.model_matrices[:w.count])
}

// Draws every entity with a Drawable. Grouped by pipeline so the pipeline and
// its vertex buffer are bound once per group; the shared index buffer is bound
// once for the frame and meshes are reached through firstIndex and baseVertex.
draw_render_system :: proc(app: ^App) {
	w := app.world
	pass := app.frame.pass
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.frame_bind_group)

	for pipeline in Pipeline {
		bound := false
		stride := layout_stride(pipeline_layout(pipeline))
		for i in 0 ..< w.count {
			drawable := pool_get(&w.drawable, Entity(i))
			if drawable == nil || drawable.pipeline != pipeline {
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
				drawable.index_count,
				1,
				u32(drawable.offsets.index / size_of(Index)),
				i32(drawable.offsets.vertex / stride),
				u32(i),
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
