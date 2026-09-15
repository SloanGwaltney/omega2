package engine

import "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

WINDOW_TITLE :: "omega2"
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

// The os window and the wgpu handles tied to it.
Window :: struct {
	handle:   ^sdl3.Window,
	instance: wgpu.Instance,
	surface:  wgpu.Surface,
	adapter:  wgpu.Adapter,
	device:   wgpu.Device,
	queue:    wgpu.Queue,
	config:   wgpu.SurfaceConfiguration,
}

// Opens an SDL3 window and stores the wgpu surface, adapter, device and queue on the app.
@(private)
create_window :: proc(app: ^App) {
	if !sdl3.Init({.VIDEO}) {
		panic("failed to init SDL3")
	}

	app.window.handle = sdl3.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	if app.window.handle == nil {
		panic("failed to create window")
	}

	set_mouse_captured(app, true)

	app.window.instance = wgpu.CreateInstance()
	if app.window.instance == nil {
		panic("failed to create wgpu instance")
	}

	app.window.surface = sdl3glue.GetSurface(app.window.instance, app.window.handle)

	wgpu.InstanceRequestAdapter(
		app.window.instance,
		&{compatibleSurface = app.window.surface},
		{callback = on_adapter, userdata1 = app},
	)
	wgpu.AdapterRequestDevice(app.window.adapter, nil, {callback = on_device, userdata1 = app})

	app.window.queue = wgpu.DeviceGetQueue(app.window.device)

	caps, status := wgpu.SurfaceGetCapabilities(app.window.surface, app.window.adapter)
	if status != .Success {
		panic("failed to query surface capabilities")
	}
	defer wgpu.SurfaceCapabilitiesFreeMembers(caps)

	width, height: i32
	sdl3.GetWindowSizeInPixels(app.window.handle, &width, &height)

	app.window.config = wgpu.SurfaceConfiguration {
		device      = app.window.device,
		format      = caps.formats[0],
		usage       = {.RenderAttachment},
		width       = u32(width),
		height      = u32(height),
		alphaMode   = .Auto,
		presentMode = .Immediate,
	}
	wgpu.SurfaceConfigure(app.window.surface, &app.window.config)
}

// Releases the wgpu handles and closes the window.
@(private)
delete_window :: proc(window: ^Window) {
	wgpu.QueueRelease(window.queue)
	wgpu.DeviceRelease(window.device)
	wgpu.AdapterRelease(window.adapter)
	wgpu.SurfaceRelease(window.surface)
	wgpu.InstanceRelease(window.instance)
	sdl3.DestroyWindow(window.handle)
	sdl3.Quit()
}

// Reconfigures the surface and rebuilds the depth texture at the new size.
// A zero sized window is skipped, because wgpu rejects a zero sized surface.
@(private)
resize_surface :: proc(app: ^App, width, height: u32) {
	if width == 0 || height == 0 {
		return
	}
	app.window.config.width = width
	app.window.config.height = height
	wgpu.SurfaceConfigure(app.window.surface, &app.window.config)
	delete_depth_texture(app)
	create_depth_texture(app)
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
	(cast(^App)userdata1).window.adapter = adapter
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
	(cast(^App)userdata1).window.device = device
}
