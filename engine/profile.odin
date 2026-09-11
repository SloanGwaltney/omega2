package engine

@(require) import "core:fmt"
@(require) import "vendor:sdl3"

// Zone timing, off unless asked for at build time. Turn everything on with
// -define:PROFILE=true, or a single zone with -define:PROFILE_<ZONE>=true.
PROFILE :: #config(PROFILE, false)

PROFILE_FRAME_UNIFORMS :: #config(PROFILE_FRAME_UNIFORMS, PROFILE)
PROFILE_MODEL_UPLOAD :: #config(PROFILE_MODEL_UPLOAD, PROFILE)

// Frames between reports.
PROFILE_REPORT_FRAMES :: #config(PROFILE_REPORT_FRAMES, 120)

// A timed region. Adding one means adding a Zone, its enable const and its
// zone_enabled entry.
Zone :: enum {
	FrameUniforms,
	ModelUpload,
}

@(private, rodata)
zone_enabled := [Zone]bool {
	.FrameUniforms = PROFILE_FRAME_UNIFORMS,
	.ModelUpload   = PROFILE_MODEL_UPLOAD,
}

// False when every zone is off, so the machinery compiles away entirely.
@(private)
PROFILE_ANY :: PROFILE_FRAME_UNIFORMS || PROFILE_MODEL_UPLOAD

@(private)
ZoneStats :: struct {
	total: u64,
	max:   u64,
	calls: u64,
}

@(private)
zone_stats: [Zone]ZoneStats
@(private)
zone_frames: u64

// Times the calling scope into z, ending when that scope exits.
@(deferred_in_out = zone_end)
zone_begin :: proc(z: Zone) -> u64 {
	when PROFILE_ANY {
		if zone_enabled[z] {
			return sdl3.GetTicksNS()
		}
	}
	return 0
}

@(private)
zone_end :: proc(z: Zone, start: u64) {
	when PROFILE_ANY {
		if !zone_enabled[z] {
			return
		}
		elapsed := sdl3.GetTicksNS() - start
		s := &zone_stats[z]
		s.total += elapsed
		s.calls += 1
		s.max = max(s.max, elapsed)
	}
}

// Prints each enabled zone's average and worst case every
// PROFILE_REPORT_FRAMES frames, then clears the accumulators.
profile_report_system :: proc(app: ^App) {
	when PROFILE_ANY {
		zone_frames += 1
		if zone_frames < PROFILE_REPORT_FRAMES {
			return
		}
		for s, z in zone_stats {
			if s.calls == 0 {
				continue
			}
			fmt.printfln(
				"%v avg %.3fms max %.3fms calls %d",
				z,
				f64(s.total) / f64(s.calls) / 1e6,
				f64(s.max) / 1e6,
				s.calls,
			)
		}
		zone_stats = {}
		zone_frames = 0
	}
}
