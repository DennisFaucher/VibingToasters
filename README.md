# VibingToasters

The After Dark *Flying Toasters* screensaver, rebuilt from scratch as a native macOS app
and screen saver. Metal on Apple Silicon, no Xcode project, no dependencies.

![Flying toasters drifting down and to the left over a starfield](docs/screenshot.png)

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Swift 5.9 toolchain (Xcode 15+) for building

## Run it as an app

```sh
swift build
.build/debug/FlyingToasters
```

| Key | Action |
| --- | --- |
| `F` | toggle fullscreen |
| `Esc` / `Q` | quit |

## Install it as a screen saver

```sh
./Tools/make-saver.sh --install
```

That builds a release binary, compiles the shader to a precompiled Metal library,
assembles `FlyingToasters.saver`, signs it ad-hoc, and copies it to
`~/Library/Screen Savers`.

Then open **System Settings → Wallpaper → Screen Saver** and pick *Flying Toasters* from
the bottom of the list, under "Other".

To just produce the bundle without installing it:

```sh
./Tools/make-saver.sh
```

## How it works

Two front ends share one engine. The app puts an `MTKView` in a window; the screen saver
is a `ScreenSaverView` subclass that hosts the same view as a subview. Neither front end
draws anything itself — MTKView's display link drives the renderer at 60 fps in both.

**One draw call.** Every star, toast and toaster is an instance of the same quad:
`drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: N)`.
Quad corners are generated in the vertex shader from `[[vertex_id]]`, so there is no vertex
buffer and no vertex descriptor to get wrong. Layer order is instance order — stars, then
toasts, then toasters — so there is no depth buffer either.

**The toasters are real sprites.** Six 64×64 frames in a `texture2d_array`, selected per
instance by a frame index, with the wing flap driven by a per-toaster sine. The frames ship
as 4-bits-per-pixel palette data compiled into the binary; they are not drawn procedurally.

**The toasts and stars are not.** Both are generated entirely in the fragment shader — the
toast's crust ring, mottling and volume gradient are all math.

**Everything flies one direction.** The whole flock moves on a single shared vector, down and
to the left, banked at a single shared angle. Objects recycle in from the top or right edge
rather than bouncing.

**Blending is premultiplied**, so filtered sprite edges don't pick up dark fringes.

### Why there is a `.metallib` in the bundle

The standalone app compiles its shader at runtime from an inlined Swift string. The screen
saver cannot: `legacyScreenSaver` is sandboxed, and its Mach lookup exceptions cover
`CARenderServer` and `CoreDisplay` but **not** `MTLCompilerService`. Runtime shader
compilation is simply unavailable there.

So `make-saver.sh` compiles the shader ahead of time into `Contents/Resources`, and the
renderer **prefers** that library whenever one is present. Compiling from source is only a
path for the app, which ships no metallib. Getting this order wrong is not a slow path — it
is a black screen.

## Regenerating the sprites

The toaster frames are baked from the XPM sprites in
[torunar/flying-toasters-xscreensaver](https://github.com/torunar/flying-toasters-xscreensaver):

```sh
python3 Tools/BakeToasterFrames.py toaster.xpm > Sources/FlyingToastersKit/ToasterFrames.swift
```

## Tools

| File | Purpose |
| --- | --- |
| `Tools/make-saver.sh` | Build and assemble the `.saver` bundle |
| `Tools/BakeToasterFrames.py` | Bake XPM sprites into `ToasterFrames.swift` |
| `Tools/TestSaver.swift` | Load a `.saver` via `NSBundle` and host it in a window, for testing without waiting for idle |
| `Tools/winlist.swift` | Print a window's `CGWindowID`, for scripted screenshots |

`AGENTS.md` documents the architecture and the debugging playbook in more depth.

## Credits

Inspired by *After Dark*'s Flying Toasters, by Berkeley Systems (1992). The toaster sprite
artwork originates from that screensaver and was extracted by the
[torunar/flying-toasters-xscreensaver](https://github.com/torunar/flying-toasters-xscreensaver)
project, which is MIT licensed. The artwork itself belongs to Berkeley Systems; this project
is a personal reimplementation and is not affiliated with or endorsed by them.
