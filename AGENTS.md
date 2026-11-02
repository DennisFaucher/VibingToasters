# AGENTS.md — Flying Toasters

Native macOS Metal re-creation of the classic After Dark *Flying Toasters* screensaver.

## Build & run

```sh
swift build
.build/debug/FlyingToasters
```

Release build:

```sh
swift build -c release
.build/release/FlyingToasters
```

Screen saver build and install:

```sh
./Tools/make-saver.sh            # builds ./FlyingToasters.saver
./Tools/make-saver.sh --install   # also copies it to ~/Library/Screen Savers
```

Requires Apple Silicon + macOS 13+. No Xcode project, no asset bundle — the Metal shader
source is inlined as a Swift string and compiled at runtime with
`device.makeLibrary(source:options:)`, and the toaster sprite frames are compiled into
`Sources/FlyingToastersKit/ToasterFrames.swift` as packed palette data. Keep it that way:
SPM resource bundles in an executable target are a needless source of `Bundle.module`
failures. The one exception is the `.saver`, which is a bundle by definition — its
precompiled `metallib` lives in `Contents/Resources` and is found with `Bundle(for:)`.

## Layout

| File | Purpose |
| --- | --- |
| `Package.swift` | SPM manifest: kit library, app executable, saver dylib |
| `Sources/FlyingToastersKit/ShaderSource.swift` | Metal shader as a Swift string |
| `Sources/FlyingToastersKit/Scene.swift` | Wire format, `Kind`, `Flight`, toasts/toasters/stars |
| `Sources/FlyingToastersKit/Renderer.swift` | `FlyingToastersRenderer`, pipeline, instancing |
| `Sources/FlyingToastersKit/ToasterView.swift` | Shared `MTKView` setup (display link pushed hard) |
| `Sources/FlyingToastersKit/ToasterFrames.swift` | Generated. Six 64×64 toaster frames, 4 bits per pixel |
| `Sources/FlyingToasters/main.swift` | App front end: window, key handling |
| `Sources/FlyingToastersSaver/FlyingToastersSaverView.swift` | `ScreenSaverView` plugin |
| `Tools/make-saver.sh` | Builds, compiles the metallib, assembles and signs the `.saver` |
| `Tools/BakeToasterFrames.py` | Regenerates `ToasterFrames.swift` from the XPM sprites |
| `Tools/TestSaver.swift` | Loads a `.saver` via `NSBundle` and hosts it in a window |
| `Tools/winlist.swift` | Prints a window's CGWindowID, for screenshot capture |
| `AGENTS.md` | This file |

## Sprite provenance

The toaster animation frames are baked from the XPM sprites in
[torunar/flying-toasters-xscreensaver](https://github.com/torunar/flying-toasters-xscreensaver)
(MIT). They are the authentic After Dark artwork. To regenerate after editing the
generator:

```sh
python3 Tools/BakeToasterFrames.py toaster.xpm > Sources/FlyingToastersKit/ToasterFrames.swift
```

The toasts and stars are **not** sprites — they stay procedural in the fragment shader.

## Architecture

There are **two front ends** over one kit, and they must stay behaviourally identical:

- `FlyingToasters` — an `NSWindow` whose `contentView` is a `ToasterView`.
- `FlyingToastersSaverView` — a `ScreenSaverView` subclass that adds the same
  `ToasterView` as a subview and lets it animate. `animateOneFrame()` stays unused;
  MTKView's display link already runs flat out. Only `startAnimation()` / `stopAnimation()`
  do anything, toggling `isPaused`.

Because sizes are in NDC, the composition is size-independent, so the `.saver` needs no
layout work — only a `density` multiplier so the System Settings preview thumbnail is not a
solid field of stars.

The render loop is **MTKView's own display link**. `isPaused = false` and
`enableSetNeedsDisplay = false` means MetalKit calls `draw(in:)` every frame.
Do not drive rendering from a `Timer` or from `setNeedsDisplay` — on modern SDKs
`NSView.setNeedsDisplay` takes an `NSRect`, not a `Bool`, and fighting that is a dead end.
- Everything is drawn in **one instanced draw call**
  (`drawPrimitives(type:.triangleStrip, vertexStart:0, vertexCount:4, instanceCount:N)`).
  Quad corners are generated procedurally in the vertex shader from `[[vertex_id]]`,
  so there is no vertex buffer and no vertex descriptor to get wrong. Layer order is
  instance order (stars → toasts → toasters), so there is no depth buffer.
- The toaster is a **six-frame sprite in a `texture2d_array`**, selected per instance by
  `params.z`. One instance per toaster; the wing flap is the frame index, not geometry.
- **Blending is premultiplied** (`source = .one`, `destination = .oneMinusSourceAlpha`).
  The baked sprite is uploaded premultiplied and the procedural shades premultiply on the
  way out. Switching back to `.sourceAlpha` will reintroduce dark fringes on filtered
  sprite edges.

## Metal ↔ Swift memory layout rules (read this before touching uniforms)

This project lost a full day to silent GPU-side corruption from struct padding.
The rules that keep it safe:

1. **A Metal struct's stride is `size` rounded up to its alignment**, and alignment is
   driven by the largest member. `{ float4; float2 }` is **32 bytes**, not 24.
   `{ float4; float4; float4 }` is 48 bytes with no padding surprises.
2. Only use structs made entirely of `float4` (and `float2` pairs arranged so the
   struct is a clean power-of-two size). Everything else invites implicit padding.
3. The Swift-side buffer is a flat `[Float]` written in the exact member order.
   `MemoryLayout<ToastInstance>.stride` on the Swift struct is *not* the wire format —
   the wire format is defined by the shader struct and asserted by a startup print.
4. Buffer offsets passed to `setVertexBuffer(_:offset:index:)` must be a multiple of
   16 bytes when the shader indexes a 16-byte-aligned array. The instance stride here is
   64 bytes (4 × `float4`), which satisfies this automatically.
5. `[[attribute(n)]]` inside a shader struct does **nothing** unless the pipeline has an
   `MTLVertexDescriptor`. Prefer `[[vertex_id]]` / `[[instance_id]]` over attributes.

## Design invariants

- The whole flock moves on **one shared vector, down and to the left**
  (`Flight.direction`), banked at **one shared angle** (`Flight.tilt`). Objects recycle in
  from the top or right edge. They do not bounce off walls.
- Toasts are golden/brown quads with a darker crust ring, toasted mottling and a soft
  volume gradient, all computed in the fragment shader. No texture. They were signed off
  as-is — do not re-tune them.
- NDC is `-1…1` on both axes, so **aspect correction is mandatory**: divide the local
  x extent by `viewportWidth / viewportHeight` or everything renders stretched.
- `size` is expressed in NDC height units (0…2 spans the screen).
- The toaster sprite's body sits left of centre because both wings stick out to the right,
  so its instance uses an off-centre pivot (`spritePivot`) to keep the body where the
  physics says it is. A centred pivot makes the toasters look like they are sliding.

## Debugging playbook

Rendering "works but nothing appears" almost always means:

1. Pipeline / clear color correct → set `clearColor` to a garish color. If you see it,
   the render pass and presentation are fine and the bug is in geometry.
2. Geometry is fine → draw a full-screen triangle with hardcoded values.
3. Still nothing → the vertex output `w` is 0 or negative (clipped), or positions are
   outside `-1…1`.
4. Geometry visible but black or white → check the blend state and whether the shade
   function premultiplies. A premultiplied pipeline fed straight-alpha colors looks washed
   out; the reverse looks dark and fringed.

Screenshot verification without human eyes. Plain `screencapture` grabs whatever app is
frontmost, so capture the window by ID instead:

```sh
.build/debug/FlyingToasters &
sleep 3
# prints "<window id>\tFlyingToasters\t{...}" via CGWindowListCopyWindowInfo
WID=$(swift Tools/winlist.swift | head -1 | cut -f1)
screencapture -x -o -l "$WID" /tmp/ft.png
kill %1
```

## Screen saver debugging

Do not debug the `.saver` by waiting for the real screen saver to trigger — iterate on the
harness instead. It loads the bundle through `NSBundle` and resolves the principal class
from `Info.plist`, which is exactly what `legacyScreenSaver.appex` does:

```sh
swiftc -O Tools/TestSaver.swift -o /tmp/testsaver -framework ScreenSaver -framework Cocoa
/tmp/testsaver FlyingToasters.saver &
sleep 5
WID=$(swift Tools/winlist.swift testsaver | head -1 | cut -f1)
screencapture -x -o -l "$WID" /tmp/saver.png
kill %1
```

Check the log, not just the picture. The renderer logs `Ready:` and then
`Animation confirmed: 60 frames rendered`; a bundle that loads but never draws shows the
first line and no second one.

Failure modes worth knowing:

1. **Black screen in the real saver but not the harness** → shader compilation. The
   sandboxed host may not reach `MTLCompilerService`. The renderer already falls back to
   `Contents/Resources/FlyingToastersShaders.metallib`; check that file shipped.
2. **Saver missing from System Settings** → bad `Info.plist`. `CFBundlePackageType` must be
   `BNDL` and `NSPrincipalClass` must match the `@objc(...)` name exactly. Confirm with
   `defaults read <bundle>/Contents/Info NSPrincipalClass`.
3. **Bundle refuses to load on Apple Silicon** → unsigned. Every Mach-O must carry at least
   an ad-hoc signature; `make-saver.sh` signs the dylib and then the bundle.
4. **`legacyScreenSaver` pegged at 100% CPU after the saver is dismissed** → a known macOS
   Tahoe-and-later regression in Apple's host, not this code. `killall legacyScreenSaver`.

## Conventions

- Swift 5.9 language mode, macOS 13 deployment target.
- No third-party dependencies.
- Shared code goes in `FlyingToastersKit`. Both front ends are thin: everything either of
  them needs must be reachable from the kit, so they cannot drift apart.
