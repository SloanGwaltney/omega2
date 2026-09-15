package engine

import "vendor:wgpu"

// A sampled texture with the bind group that binds it, and the sampler it is
// read through. Every sampled texture shares app.render.texture_layout, so any of them
// can be bound at group 1 of any pipeline that samples.
Texture :: struct {
	handle:     wgpu.Texture,
	view:       wgpu.TextureView,
	sampler:    wgpu.Sampler,
	bind_group: wgpu.BindGroup,
}

// Builds the layout every sampled texture binds against: the view at 0 and the
// sampler at 1, both read by the fragment stage.
create_texture_layout :: proc(app: ^App) {
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
	}
	app.render.texture_layout = wgpu.DeviceCreateBindGroupLayout(
		app.window.device,
		&{label = "texture", entryCount = len(entries), entries = &entries[0]},
	)
	if app.render.texture_layout == nil {
		panic("failed to create texture bind group layout")
	}
}

// Uploads pixels as a 2D texture. Pixels must be width * height tightly packed
// texels of format, in rows from the top down.
create_texture :: proc(
	app: ^App,
	label: string,
	pixels: []u8,
	width, height: u32,
	format: wgpu.TextureFormat,
) -> Texture {
	stride := texel_size(format)
	assert(u32(len(pixels)) == width * height * stride, "pixel count does not match the texture size")

	size := wgpu.Extent3D{width, height, 1}
	handle := wgpu.DeviceCreateTexture(
		app.window.device,
		&{
			label = label,
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = size,
			format = format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if handle == nil {
		panic("failed to create texture")
	}

	wgpu.QueueWriteTexture(
		app.window.queue,
		&{texture = handle, aspect = .All},
		raw_data(pixels),
		len(pixels),
		&{bytesPerRow = width * stride, rowsPerImage = height},
		&size,
	)

	return texture_bind(app, label, handle)
}

// Creates an empty texture the renderer can draw into and the ui can sample.
// Made in the surface format so the world pipelines render into it unchanged.
create_render_target :: proc(app: ^App, label: string, width, height: u32) -> Texture {
	handle := wgpu.DeviceCreateTexture(
		app.window.device,
		&{
			label = label,
			usage = {.TextureBinding, .RenderAttachment},
			dimension = ._2D,
			size = {width, height, 1},
			format = app.window.config.format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if handle == nil {
		panic("failed to create render target")
	}
	return texture_bind(app, label, handle)
}

// Wraps an uploaded texture in the view, sampler and bind group that let any
// sampling pipeline bind it at group 1.
@(private)
texture_bind :: proc(app: ^App, label: string, handle: wgpu.Texture) -> Texture {
	view := wgpu.TextureCreateView(handle)
	if view == nil {
		panic("failed to create texture view")
	}

	sampler := wgpu.DeviceCreateSampler(
		app.window.device,
		&{
			label = label,
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Nearest,
			lodMaxClamp = 1,
			maxAnisotropy = 1,
		},
	)
	if sampler == nil {
		panic("failed to create sampler")
	}

	bindings := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = view},
		{binding = 1, sampler = sampler},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		app.window.device,
		&{
			label = label,
			layout = app.render.texture_layout,
			entryCount = len(bindings),
			entries = &bindings[0],
		},
	)
	if bind_group == nil {
		panic("failed to create texture bind group")
	}

	return {handle = handle, view = view, sampler = sampler, bind_group = bind_group}
}

delete_texture :: proc(texture: ^Texture) {
	wgpu.BindGroupRelease(texture.bind_group)
	wgpu.SamplerRelease(texture.sampler)
	wgpu.TextureViewRelease(texture.view)
	wgpu.TextureRelease(texture.handle)
	texture^ = {}
}

// Bytes per texel, for the formats textures are uploaded in.
@(private)
texel_size :: proc(format: wgpu.TextureFormat) -> u32 {
	#partial switch format {
	case .R8Unorm:
		return 1
	case .RGBA8Unorm, .RGBA8UnormSrgb:
		return 4
	}
	panic("unsupported texture format")
}
