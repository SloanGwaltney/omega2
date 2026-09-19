package engine

import "core:math"
import "core:math/linalg"
import "vendor:wgpu"

// Bakes meshes into textures the ui can draw, so the shop can show a picture
// of a thing without it existing in the world. A bake runs its own pass
// outside the frame, reusing the world pipelines and the shared mesh buffers.

// Vertical field of view the icon camera frames the mesh with.
ICON_FOV_Y :: f32(math.PI) / 6
// Direction the icon camera sits in from the mesh. Straight down z gives a
// face on view, and leaning it off the axes gives a three quarter one.
ICON_DIR :: Vec3{0, 0, 1}
// Slack left around the mesh so it does not touch the edges of the icon.
ICON_MARGIN :: 1.15

// Renders data once into a width by height texture, framed to fill it, and
// returns the texture for ui_image to draw. Bake at the aspect it will be
// drawn at, or the picture stretches. The mesh is uploaded through the shared
// buffers, so spawning the same mesh later reuses this upload.
icon_bake :: proc(
	app: ^App,
	label: string,
	pipeline: Pipeline,
	data: []byte,
	indices: []Index,
	bounds: Aabb,
	width, height: u32,
) -> Texture {
	icon := create_render_target(app, label, width, height)
	offsets := mesh_upload(app, pipeline_layout(pipeline), data, indices)

	depth := wgpu.DeviceCreateTexture(
		app.window.device,
		&{
			label = label,
			usage = {.RenderAttachment},
			dimension = ._2D,
			size = {width, height, 1},
			format = DEPTH_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if depth == nil {
		panic("failed to create icon depth texture")
	}
	defer wgpu.TextureRelease(depth)
	depth_view := wgpu.TextureCreateView(depth)
	defer wgpu.TextureViewRelease(depth_view)

	aspect := f32(width) / f32(height)
	view_proj, eye := icon_view_proj(bounds, aspect)
	gpu_buffer_write(app, &app.render.camera_uniform, []Mat4{view_proj})
	gpu_buffer_write(app, &app.render.models, []Mat4{linalg.MATRIX4F32_IDENTITY})
	// The icon is viewed from its own camera, so the light follows it there and
	// is left pointing at it for whatever frame comes next to overwrite.
	app.render.light.eye = eye
	gpu_buffer_write(app, &app.render.light_uniform, []Light{app.render.light})

	encoder := wgpu.DeviceCreateCommandEncoder(app.window.device, &{label = label})
	defer wgpu.CommandEncoderRelease(encoder)

	color := wgpu.RenderPassColorAttachment {
		view       = icon.view,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = {0, 0, 0, 0},
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view            = depth_view,
		depthLoadOp     = .Clear,
		depthStoreOp    = .Store,
		depthClearValue = 1,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			label = label,
			colorAttachmentCount = 1,
			colorAttachments = &color,
			depthStencilAttachment = &depth_attachment,
		},
	)

	layout := pipeline_layout(pipeline)
	wgpu.RenderPassEncoderSetPipeline(pass, pipeline_handle(app, pipeline))
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, vertex_buffer(app, layout).handle, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetIndexBuffer(pass, app.render.indices.handle, INDEX_FORMAT, 0, wgpu.WHOLE_SIZE)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, app.render.frame_bind_group)
	wgpu.RenderPassEncoderDrawIndexed(
		pass,
		u32(len(indices)),
		1,
		u32(offsets.index / size_of(Index)),
		i32(offsets.vertex / layout_stride(layout)),
		0,
	)
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder)
	defer wgpu.CommandBufferRelease(command_buffer)
	wgpu.QueueSubmit(app.window.queue, {command_buffer})
	return icon
}

// View projection and eye placing the camera far enough along ICON_DIR that
// bounds fits the icon vertically.
@(private)
icon_view_proj :: proc(bounds: Aabb, aspect: f32) -> (Mat4, Vec3) {
	center := (bounds.min + bounds.max) / 2
	radius := linalg.length(bounds.max - bounds.min) / 2 * ICON_MARGIN
	distance := radius / math.tan(ICON_FOV_Y / 2)
	eye := center + linalg.normalize(ICON_DIR) * distance
	proj := perspective(ICON_FOV_Y, aspect, distance - radius, distance + radius)
	return proj * look_at(eye, center, {0, 1, 0}), eye
}
