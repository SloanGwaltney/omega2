package engine

import "vendor:wgpu"

// A sampled texture with the bind group that binds it, and the sampler it is
// read through. Every sampled texture shares app.texture_layout, so any of them
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
	app.texture_layout = wgpu.DeviceCreateBindGroupLayout(
		app.device,
		&{label = "texture", entryCount = len(entries), entries = &entries[0]},
	)
	if app.texture_layout == nil {
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
		app.device,
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
		app.queue,
		&{texture = handle, aspect = .All},
		raw_data(pixels),
		len(pixels),
		&{bytesPerRow = width * stride, rowsPerImage = height},
		&size,
	)

	view := wgpu.TextureCreateView(handle)
	if view == nil {
		panic("failed to create texture view")
	}

	sampler := wgpu.DeviceCreateSampler(
		app.device,
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
		app.device,
		&{
			label = label,
			layout = app.texture_layout,
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
