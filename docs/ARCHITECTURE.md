# Motionix Engine — Architecture

The mission: **advanced as hell, smooth as heaven.** The engine borrows its
discipline from game engines, not from desktop NLEs, because the target is a
4 GB-RAM phone in a warm pocket, not a workstation in an air-conditioned room.

## Principles

1. **Everything is a node graph.** Clips, filters, masks, text and 3D layers
   are nodes with typed ports. The saved project file *is* the graph. Presets
   are graphs too — beginners tap to apply them, power users open the nodes.
2. **A render compiler, not a render loop.** Effects get fused into as few
   shaders as possible, hidden branches are compiled out, and results are
   cached and reused.
3. **A quality governor.** Every frame gets a time budget. Under pressure the
   preview drops resolution, never frames; when idle it settles back. This is
   how 4 GB devices stay smooth while flagships burn.
4. **GPU-resident pixels.** Decoded frames go to GPU textures and stay there.
   CPU RAM holds metadata, audio and a small frame cache (~250 MB).
5. **Proxy editing.** Imports transcode to 540–720p proxies (originals stay
   untouched); the final export always reads the originals.
6. **One renderer.** Preview and export run the same pipeline, so what you
   scrub is what you render.
7. **Editing niceties are not afterthoughts.** Rational timebase (29.97-safe
   from day one), command-queue undo/redo, resumable export queue.

## What exists today (Phase 1)

| Piece | File | Notes |
| ----- | ---- | ----- |
| C ABI surface | `core/src/core_api.cpp` | malloc'd UTF-8 out-params, `mx_free_string`, no exceptions cross the boundary |
| Rational time | `core/src/rational.{h,cpp}` | exact frame math, 30000/1001 safe |
| Timecode | `core/src/timecode.{h,cpp}` | HH:MM:SS:FF formatting |
| Proxy planner | `core/src/proxy_planner.{h,cpp}` | JSON in, ladder + bitrates out; `lowRam` flag clamps to 540p |
| Project model | `core/src/project.{h,cpp}` | the seed of the node graph: media, trims, timeline rate |
| FFI bridge | `lib/core/bindings.dart` | dlopen + lookupFunction, memory freed via `mx_free_string` |
| Media bridge | `MainActivity.kt` | Media3 Transformer: probe, thumbnails, proxy transcode, export |
| CI | `.github/workflows/android.yml` | analyze + test (against the real core) + signed APK artifact |

## 3D scope (Phase 7)

Video-grade 3D only: 3D layers, cameras, lights, shadows, glTF import,
extruded text. Explicitly out of scope: modeling, sculpting, rigging.

## Memory targets

| Device class | Preview | Proxy | Frame cache |
| ------------ | ------- | ----- | ----------- |
| 4 GB (simulated) | 540p | 540p | ~120 MB |
| 6–8 GB | 720p | 720p | ~250 MB |
| Flagship | 1080p | 720p | ~400 MB |

The founder dev phone is a Vivo T4x 5G (Dimensity 7300, 8+8 GB) — the
"Simulate 4 GB device" switch on the home screen forces the lean ladder so
the low-end promise is tested on real hardware every day.
