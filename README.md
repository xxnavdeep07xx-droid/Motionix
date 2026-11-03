# Motionix

**Mobile video editing — advanced as hell, smooth as heaven.**

Motionix is an Android-first video editor built to be easier than CapCut,
deeper than After Effects / DaVinci Resolve / Blender (video-grade 3D included),
and still smooth on 4 GB-RAM phones.

- **UI**: Flutter (dark, thumb-first, one-hand friendly)
- **Engine**: C++ core (`core/`) linked through `dart:ffi` as `libmotionix_core.so`
- **Media**: Media3 Transformer (hardware codecs; the CPU never touches pixels)
- **Platform**: Android-first (iOS later)

## Status — Phase 1: Engine proof

Milestone: import a 4K clip, auto-generate a lean proxy, scrub buttery-smooth,
export full quality from the ORIGINAL file.

| Phase | Scope | Status |
| ----- | ----- | ------ |
| 1 | Engine: import, proxy, scrub, export | **In flight** |
| 2 | Timeline editor UI | Planned |
| 3 | Node-graph runtime | Planned |
| 4 | Look: filters and effects | Planned |
| 5 | Words and style: text, shapes, templates | Planned |
| 6 | Sound | Planned |
| 7 | 3D layers | Planned |
| 8 | Pro tools | Planned |
| 9 | Armor: signing, store release | Planned |

## Repository layout

```
lib/                 Flutter app (screens, FFI bindings, media service)
core/                C++ engine (rational time, proxy planner, project model)
android/             Android shell (Gradle, Media3 bridge in MainActivity.kt)
.github/workflows/   CI: analyze, test, build APK
docs/                Architecture notes
```

## Building

APKs are built by **GitHub Actions** on every push to `main`. Download the
`motionix-apk-<run>` artifact from the Actions tab — it is signed with a
throwaway CI key (stored as a repo secret), so consecutive builds
upgrade-install over each other.

Manual build: `flutter pub get && flutter build apk --release`.

### Running the tests

The test suite exercises the real C++ core through FFI, so build the host
core first:

```bash
g++ -std=c++17 -O2 -shared -fPIC -Icore/src -Icore/thirdparty \
    core/src/*.cpp -o libmotionix_core.so
LD_LIBRARY_PATH=$PWD flutter test
```

## Signing note

`android/app/keys/ci-test-signing.jks` (decoded from the
`CI_KEYSTORE_BASE64` secret at build time) is a throwaway key that only
exists so CI builds install cleanly during development. The real release
key arrives in Phase 9 and will be injected via secrets. Never use the CI
key for a store upload.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the engine design.
