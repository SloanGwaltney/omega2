package engine

// Request to put a mesh on the gpu. Replaced by a Drawable once
// upload_drawables_system runs, so it lives for at most one frame.
DrawableUpload :: struct {
	pipeline: Pipeline,
	data:     []byte,
	indices:  []Index,
}

// An uploaded mesh, ready to be drawn from the shared gpu buffers.
Drawable :: struct {
	pipeline:    Pipeline,
	offsets:     BufferOffsets,
	index_count: u32,
}

// Uploads every pending DrawableUpload and swaps it for a Drawable.
upload_drawables_system :: proc(app: ^App) {
	w := app.world
	for i in 0 ..< w.count {
		e := Entity(i)
		upload := pool_get(&w.drawable_upload, e)
		if upload == nil {
			continue
		}
		pool_add(
			&w.drawable,
			e,
			Drawable {
				pipeline = upload.pipeline,
				offsets = mesh_upload(app, pipeline_layout(upload.pipeline), upload.data, upload.indices),
				index_count = u32(len(upload.indices)),
			},
		)
		pool_remove(&w.drawable_upload, e)
	}
}
