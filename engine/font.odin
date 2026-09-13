package engine

import "core:c"
import "vendor:stb/truetype"

MONO_TTF :: #load("fonts/mono.ttf", []u8)

FONT_ATLAS_SIZE :: 512
FONT_FIRST_CHAR :: 32
FONT_CHAR_COUNT :: 95

// The sizes baked into the atlas, in pixels from ascender to descender.
FontSize :: enum {
	Small,
	Large,
}
FONT_PIXEL_HEIGHTS :: [FontSize]f32 {
	.Small = 16,
	.Large = 32,
}

// Per size baked glyphs and metrics.
FontFace :: struct {
	chars:       [FONT_CHAR_COUNT]truetype.packedchar,
	ascent:      f32,
	line_height: f32,
}

// Every size baked into one atlas, so all text and every solid rect sample the
// same texture and the ui stays a single draw call. The atlas is RGBA with the
// glyph coverage in alpha, so it shares the ui shader with ordinary textures.
Font :: struct {
	atlas:    Texture,
	faces:    [FontSize]FontFace,
	// A texel of solid white, for quads that want a flat color.
	white_uv: Vec2,
}

// Bakes every size of the built in mono font into one atlas. The bottom row of
// the atlas is held back from the packer to hold the white texel.
create_font :: proc(app: ^App) {
	packed_height :: FONT_ATLAS_SIZE - 1
	coverage := make([]u8, FONT_ATLAS_SIZE * FONT_ATLAS_SIZE)
	defer delete(coverage)

	ctx: truetype.pack_context
	if truetype.PackBegin(
		   &ctx,
		   raw_data(coverage),
		   FONT_ATLAS_SIZE,
		   packed_height,
		   FONT_ATLAS_SIZE,
		   1,
		   nil,
	   ) == 0 {
		panic("failed to begin font packing")
	}

	heights := FONT_PIXEL_HEIGHTS
	ranges: [len(FontSize)]truetype.pack_range
	for size in FontSize {
		ranges[size] = {
			font_size                        = heights[size],
			first_unicode_codepoint_in_range = FONT_FIRST_CHAR,
			num_chars                        = FONT_CHAR_COUNT,
			chardata_for_range               = &app.font.faces[size].chars[0],
		}
	}
	if truetype.PackFontRanges(&ctx, raw_data(MONO_TTF), 0, &ranges[0], len(ranges)) == 0 {
		panic("font atlas is too small")
	}
	truetype.PackEnd(&ctx)

	white := packed_height * FONT_ATLAS_SIZE
	coverage[white] = 255
	app.font.white_uv = {0.5 / FONT_ATLAS_SIZE, (f32(packed_height) + 0.5) / FONT_ATLAS_SIZE}

	// The ui shader tints by the vertex color, so the atlas carries coverage in
	// alpha and leaves the color channels white.
	pixels := make([]u8, FONT_ATLAS_SIZE * FONT_ATLAS_SIZE * 4)
	defer delete(pixels)
	for value, i in coverage {
		pixels[i * 4 + 0] = 255
		pixels[i * 4 + 1] = 255
		pixels[i * 4 + 2] = 255
		pixels[i * 4 + 3] = value
	}
	app.font.atlas = create_texture(
		app,
		"font atlas",
		pixels,
		FONT_ATLAS_SIZE,
		FONT_ATLAS_SIZE,
		.RGBA8Unorm,
	)

	for size in FontSize {
		descent, line_gap: f32
		face := &app.font.faces[size]
		truetype.GetScaledFontVMetrics(
			raw_data(MONO_TTF),
			0,
			heights[size],
			&face.ascent,
			&descent,
			&line_gap,
		)
		face.line_height = face.ascent - descent + line_gap
	}
}

delete_font :: proc(font: ^Font) {
	delete_texture(&font.atlas)
}

// Distance from the top of a line of text to its baseline.
font_ascent :: proc(font: ^Font, size: FontSize) -> f32 {
	return font.faces[size].ascent
}

// Distance from one baseline to the next.
font_line_height :: proc(font: ^Font, size: FontSize) -> f32 {
	return font.faces[size].line_height
}

// Width of text in pixels, without drawing it.
font_measure :: proc(font: ^Font, size: FontSize, text: string) -> f32 {
	face := &font.faces[size]
	width: f32
	for ch in text {
		if index, ok := glyph_index(ch); ok {
			width += face.chars[index].xadvance
		}
	}
	return width
}

// Index into a face's glyphs, or false for a codepoint outside the baked range.
@(private)
glyph_index :: proc(ch: rune) -> (index: int, ok: bool) {
	if ch < FONT_FIRST_CHAR || ch >= FONT_FIRST_CHAR + FONT_CHAR_COUNT {
		return 0, false
	}
	return int(ch) - FONT_FIRST_CHAR, true
}

// Quad and advance for one glyph, with pen at the baseline's left end.
@(private)
glyph_quad :: proc(face: ^FontFace, index: int, pen: ^Vec2) -> truetype.aligned_quad {
	quad: truetype.aligned_quad
	x, y := pen.x, pen.y
	truetype.GetPackedQuad(
		&face.chars[0],
		FONT_ATLAS_SIZE,
		FONT_ATLAS_SIZE,
		c.int(index),
		&x,
		&y,
		&quad,
		true,
	)
	pen^ = {x, y}
	return quad
}
