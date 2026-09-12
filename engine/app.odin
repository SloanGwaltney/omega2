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
	unlit_vertices:   GpuBuffer,
	indices:          GpuBuffer,
	camera_uniform:   GpuBuffer,
	models:           GpuBuffer,
	frame_layout:     wgpu.BindGroupLayout,
	frame_bind_group: wgpu.BindGroup,
	// Staging for models, packed in draw order and uploaded whole each frame.
	model_matrices:   [MAX_ENTITIES]Mat4,
	// Draw batches rebuilt each frame from the drawables.
	batches:          [MAX_BATCHES]Batch,
	batch_count:      int,
	// This frame's drawable entities and the batch each landed in, so the
	// second pass does not rescan the pools or the batch list.
	drawn:            [MAX_ENTITIES]DrawEntry,
	meshes:           MeshStorage,
	// Called once per frame before the engine systems, if set.
	user_update:      System,
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
	create_unlit_pipeline(app)
	return app
}

/// Releases the world arena and everything on it, the window and the wgpu handles.
delete_app :: proc(app: ^App) {
	delete_mesh_storage(&app.meshes)
	delete_depth_texture(app)
	delete_buffers(app)
	wgpu.RenderPipelineRelease(app.unlit_pipeline)
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

		if app.user_update != nil {
			app.user_update(app)
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

	if !sdl3.SetWindowRelativeMouseMode(app.window, true) {
		panic("failed to capture the mouse")
	}

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
