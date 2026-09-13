package engine

import "core:mem"
import "core:mem/virtual"
import "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

WORLD_ARENA_SIZE :: 100 * mem.Megabyte

WINDOW_TITLE :: "omega2"
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

App :: struct {
	world_arena:      virtual.Arena,
	world:            ^World,
	window:           ^sdl3.Window,
	instance:         wgpu.Instance,
	surface:          wgpu.Surface,
	adapter:          wgpu.Adapter,
	device:           wgpu.Device,
	queue:            wgpu.Queue,
	surface_config:   wgpu.SurfaceConfiguration,
	frame:            Frame,
	depth_texture:    wgpu.Texture,
	depth_view:       wgpu.TextureView,
	unlit_pipeline:   wgpu.RenderPipeline,
	ui_pipeline:      wgpu.RenderPipeline,
	unlit_vertices:   GpuBuffer,
	ui_vertices:      GpuBuffer,
	ui_indices:       GpuBuffer,
	indices:          GpuBuffer,
	camera_uniform:   GpuBuffer,
	ui_uniform:       GpuBuffer,
	models:           GpuBuffer,
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
	// This frame's ui geometry, rebuilt by ui_system.
	ui:               Ui,
	// Called by ui_system to emit this frame's ui, if set.
	ui_callback:      UiCallback,
	// This frame's raw device state, refilled by sample_input_system.
	input:            Input,
	// The game's systems, run each frame after PRE_SYSTEMS and before the
	// engine's own. They get the whole app, engine components included.
	user_systems:     []System,
}

/// Allocates the app with a 100MB world arena and a world living on it, and opens the window.
new_app :: proc() -> ^App {
	app := new(App)
	if err := virtual.arena_init_static(&app.world_arena, WORLD_ARENA_SIZE); err != nil {
		panic("failed to reserve world arena")
	}
	app.world = world_create(virtual.arena_allocator(&app.world_arena))
	create_window(app)
	create_depth_texture(app)
	create_buffers(app)
	create_frame_bind_group(app)
	create_texture_layout(app)
	create_font(app)
	create_unlit_pipeline(app)
	create_ui_pipeline(app)
	return app
}

/// Releases the world arena and everything on it, the window and the wgpu handles.
delete_app :: proc(app: ^App) {
	delete_mesh_storage(&app.meshes)
	delete_depth_texture(app)
	delete_buffers(app)
	wgpu.RenderPipelineRelease(app.unlit_pipeline)
	wgpu.RenderPipelineRelease(app.ui_pipeline)
	delete_font(&app.font)
	wgpu.BindGroupLayoutRelease(app.texture_layout)
	wgpu.BindGroupRelease(app.frame_bind_group)
	wgpu.BindGroupLayoutRelease(app.frame_layout)
	wgpu.QueueRelease(app.queue)
	wgpu.DeviceRelease(app.device)
	wgpu.AdapterRelease(app.adapter)
	wgpu.SurfaceRelease(app.surface)
	wgpu.InstanceRelease(app.instance)
	sdl3.DestroyWindow(app.window)
	sdl3.Quit()
	virtual.arena_destroy(&app.world_arena)
	free(app)
}

/// Runs the event loop until the window is closed.
run_app :: proc(app: ^App) {
	event: sdl3.Event
	for {
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				return
			case .WINDOW_PIXEL_SIZE_CHANGED:
				resize_surface(app, u32(event.window.data1), u32(event.window.data2))
			}
		}

		for system in PRE_SYSTEMS {
			system(app)
		}
		for system in app.user_systems {
			system(app)
		}
		for system in UPDATE_SYSTEMS {
			system(app)
		}
		for system in RENDER_SYSTEMS {
			system(app)
		}
	}
}

/// Reconfigures the surface and rebuilds the depth texture at the new size.
/// A zero sized window is skipped, because wgpu rejects a zero sized surface.
@(private)
resize_surface :: proc(app: ^App, width, height: u32) {
	if width == 0 || height == 0 {
		return
	}
	app.surface_config.width = width
	app.surface_config.height = height
	wgpu.SurfaceConfigure(app.surface, &app.surface_config)
	delete_depth_texture(app)
	create_depth_texture(app)
}

/// Opens an SDL3 window and stores the wgpu surface, adapter, device and queue on the app.
@(private)
create_window :: proc(app: ^App) {
	if !sdl3.Init({.VIDEO}) {
		panic("failed to init SDL3")
	}

	app.window = sdl3.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	if app.window == nil {
		panic("failed to create window")
	}

	set_mouse_captured(app, true)

	app.instance = wgpu.CreateInstance()
	if app.instance == nil {
		panic("failed to create wgpu instance")
	}

	app.surface = sdl3glue.GetSurface(app.instance, app.window)

	wgpu.InstanceRequestAdapter(
		app.instance,
		&{compatibleSurface = app.surface},
		{callback = on_adapter, userdata1 = app},
	)
	wgpu.AdapterRequestDevice(app.adapter, nil, {callback = on_device, userdata1 = app})

	app.queue = wgpu.DeviceGetQueue(app.device)

	caps, status := wgpu.SurfaceGetCapabilities(app.surface, app.adapter)
	if status != .Success {
		panic("failed to query surface capabilities")
	}
	defer wgpu.SurfaceCapabilitiesFreeMembers(caps)

	width, height: i32
	sdl3.GetWindowSizeInPixels(app.window, &width, &height)

	app.surface_config = wgpu.SurfaceConfiguration {
		device      = app.device,
		format      = caps.formats[0],
		usage       = {.RenderAttachment},
		width       = u32(width),
		height      = u32(height),
		alphaMode   = .Auto,
		presentMode = .Immediate,
	}
	wgpu.SurfaceConfigure(app.surface, &app.surface_config)
}

@(private)
on_adapter :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	if status != .Success {
		panic_contextless("failed to acquire wgpu adapter")
	}
	(cast(^App)userdata1).adapter = adapter
}

@(private)
on_device :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	if status != .Success {
		panic_contextless("failed to acquire wgpu device")
	}
	(cast(^App)userdata1).device = device
}
