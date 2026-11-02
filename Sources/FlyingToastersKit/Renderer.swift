import Foundation
import Metal
import MetalKit
import QuartzCore

// MARK: - Renderer

public final class FlyingToastersRenderer: NSObject, MTKViewDelegate {

    /// Object counts at full density. The screen saver's preview tile passes a
    /// multiplier so it does not pack the whole flock into a thumbnail.
    private static let baseToastCount = 26
    private static let baseToasterCount = 16
    private static let baseStarCount = 240

    private let toastCount: Int
    private let toasterCount: Int
    private let starCount: Int
    private let instanceCapacity: Int

    /// The sprite's toaster body sits left of centre, because both wings stick out
    /// to the right. Pulling the pivot off-centre keeps the body where the physics
    /// says it is. In local quad units.
    private static let spritePivot = SIMD2<Float>(-0.32, 0.0)

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let instanceBuffer: MTLBuffer
    private let frameUniforms: MTLBuffer
    private let toasterTexture: MTLTexture

    private var toasts: [Toast] = []
    private var toasters: [FlyingToaster] = []
    private var stars: [Star] = []

    private var scratch: [Float]

    private var lastTime: CFTimeInterval = CACurrentMediaTime()
    private var elapsed: Float = 0
    private var frameCount = 0
    private var drawAttempts = 0
    private var viewportSize = SIMD2<Float>(1280, 800)
    private var aspect: Float = 1.6

    private var starRange = (start: 0, count: 0)
    private var toastRange = (start: 0, count: 0)
    private var toasterRange = (start: 0, count: 0)

    /// `density` scales the flock size. Pass something below 1 for the screen
    /// saver's preview thumbnail; the full-screen saver uses 1.
    public init?(device: MTLDevice, density: Float = 1.0) {
        let scale = max(0.15, min(density, 3.0))
        let toasts = max(3, Int((Float(Self.baseToastCount) * scale).rounded()))
        let toasters = max(2, Int((Float(Self.baseToasterCount) * scale).rounded()))
        let stars = max(20, Int((Float(Self.baseStarCount) * scale).rounded()))

        self.toastCount = toasts
        self.toasterCount = toasters
        self.starCount = stars
        self.instanceCapacity = toasts + toasters + stars + 8
        self.scratch = [Float](repeating: 0,
                               count: (toasts + toasters + stars + 8) * Wire.floatsPerInstance)

        guard let queue = device.makeCommandQueue() else {
            Diagnostics.log("Unable to create a Metal command queue")
            return nil
        }
        self.device = device
        self.commandQueue = queue

        let library: MTLLibrary
        do {
            library = try Self.makeShaderLibrary(device: device)
        } catch {
            Diagnostics.log("Shader compilation failed: \(error)")
            return nil
        }

        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            Diagnostics.log("Shader entry points are missing")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "AfterDarkPipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        // Premultiplied source everywhere: the baked sprite arrives premultiplied,
        // and the procedural shades premultiply on the way out. This avoids the
        // dark fringe you get when filtered texels blend un-premultiplied.
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Diagnostics.log("Pipeline creation failed: \(error)")
            return nil
        }

        let instanceBytes = instanceCapacity * Wire.bytesPerInstance
        guard let instances = device.makeBuffer(length: instanceBytes, options: .storageModeShared),
              let uniforms = device.makeBuffer(length: 16, options: .storageModeShared) else {
            Diagnostics.log("Unable to allocate Metal buffers")
            return nil
        }
        instances.label = "Instances"
        uniforms.label = "FrameUniforms"
        self.instanceBuffer = instances
        self.frameUniforms = uniforms

        guard let frames = Self.makeToasterTexture(device: device, queue: queue) else {
            Diagnostics.log("Unable to build the toaster frame texture")
            return nil
        }
        self.toasterTexture = frames

        super.init()

        assert(Wire.bytesPerInstance == 64,
               "Instance wire format drifted: \(Wire.bytesPerInstance) bytes, shader expects 64")

        buildPopulation()
        Diagnostics.log("Ready: \(starCount) stars, \(toastCount) toasts, \(toasterCount) toasters on \(device.name)")
    }

    /// Resolves the precompiled `Contents/Resources/FlyingToastersShaders.metallib`,
    /// if one shipped alongside this code.
    private static func bundledMetallibURL() -> URL? {
        // Usual case: NSBundle resolves the bundle that contains this class.
        if let url = Bundle(for: FlyingToastersRenderer.self)
            .url(forResource: "FlyingToastersShaders", withExtension: "metallib") {
            return url
        }

        // Inside `legacyScreenSaver` the dylib is hosted by another bundle, so
        // `Bundle(for:)` can resolve to the host's bundle instead of the `.saver`.
        // Derive the path from this image directly: <bundle>/Contents/MacOS/<exe>.
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let name = info.dli_fname else { return nil }
        let exe = URL(fileURLWithPath: String(cString: name))
        let contents = exe.deletingLastPathComponent().deletingLastPathComponent()
        let candidate = contents.appendingPathComponent("Resources/FlyingToastersShaders.metallib")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Builds the shader library, preferring the precompiled metallib.
    ///
    /// Order matters. The screen saver is loaded inside a sandboxed host with no
    /// Mach-lookup exception for `MTLCompilerService`, so `makeLibrary(source:)`
    /// cannot compile there — and probing it first risks a long XPC timeout before
    /// the fallback is ever reached. So: a bundled metallib wins whenever present,
    /// and runtime compilation is only for the standalone app, which has none.
    private static func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let url = bundledMetallibURL() {
            do {
                let library = try device.makeLibrary(URL: url)
                Diagnostics.log("shader: loaded precompiled metallib at \(url.path)")
                return library
            } catch {
                Diagnostics.log("shader: bundled metallib failed to load (\(error)); falling back to source")
            }
        } else {
            Diagnostics.log("shader: no bundled metallib; compiling from source")
        }
        let library = try device.makeLibrary(source: metalShaderSource, options: nil)
        Diagnostics.log("shader: compiled from inline source")
        return library
    }

    /// Expands the packed 4-bit frames into an RGBA8 texture array and builds the
    /// mip chain, so the sprite stays clean when it is scaled down on screen.
    private static func makeToasterTexture(device: MTLDevice,
                                           queue: MTLCommandQueue) -> MTLTexture? {
        let width = ToasterFrames.width
        let height = ToasterFrames.height
        let count = ToasterFrames.frameCount
        let pixelsPerFrame = width * height

        guard let packed = Data(base64Encoded: ToasterFrames.packedBase64,
                                options: .ignoreUnknownCharacters),
              packed.count == count * pixelsPerFrame / 2 else {
            Diagnostics.log("Toaster frame pack is the wrong size")
            return nil
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = width
        descriptor.height = height
        descriptor.arrayLength = count
        descriptor.mipmapLevelCount = Int(log2(Double(width))) + 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "ToasterFrames"

        var rgba = [UInt8](repeating: 0, count: pixelsPerFrame * 4)
        packed.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for frame in 0..<count {
                let base = frame * pixelsPerFrame / 2
                for i in 0..<pixelsPerFrame {
                    let byte = bytes[base + i / 2]
                    let index = (i % 2 == 0) ? Int(byte >> 4) : Int(byte & 0x0F)
                    let argb = ToasterFrames.palette[index]
                    let a = Double((argb >> 24) & 0xFF) / 255
                    // Store premultiplied so filtered edges never fringe dark.
                    rgba[i * 4 + 0] = UInt8(Double((argb >> 16) & 0xFF) * a)
                    rgba[i * 4 + 1] = UInt8(Double((argb >> 8) & 0xFF) * a)
                    rgba[i * 4 + 2] = UInt8(Double(argb & 0xFF) * a)
                    rgba[i * 4 + 3] = UInt8(a * 255)
                }
                rgba.withUnsafeBytes { buffer in
                    texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                                    mipmapLevel: 0,
                                    slice: frame,
                                    withBytes: buffer.baseAddress!,
                                    bytesPerRow: width * 4,
                                    bytesPerImage: pixelsPerFrame * 4)
                }
            }
        }

        guard let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }

    private func buildPopulation() {
        for _ in 0..<toastCount {
            var toast = Toast(position: .zero, velocity: .zero, size: 0.1, color: .zero)
            toast.respawn()
            toast.position = SIMD2(Float.random(in: -1.5...1.5), Float.random(in: -1.5...1.5))
            toasts.append(toast)
        }

        for _ in 0..<toasterCount {
            var toaster = FlyingToaster(position: .zero, velocity: .zero, size: 0.11,
                                        phase: 0, flapSpeed: 4)
            toaster.respawn()
            toaster.position = SIMD2(Float.random(in: -1.5...1.5), Float.random(in: -1.5...1.5))
            toasters.append(toaster)
        }

        for _ in 0..<starCount {
            stars.append(Star(position: SIMD2(Float.random(in: -1...1), Float.random(in: -1...1)),
                              size: Float.random(in: 0.0050...0.0140),
                              brightness: Float.random(in: 0.25...1.0),
                              phase: Float.random(in: 0...(Float.pi * 2)),
                              speed: Float.random(in: 0.6...2.4)))
        }
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(Float(size.width), Float(size.height))
        aspect = max(viewportSize.x, 1) / max(viewportSize.y, 1)
        Diagnostics.log("draw: drawableSizeWillChange -> \(size)")
    }

    public func draw(in view: MTKView) {
        drawAttempts += 1
        if drawAttempts <= 3 {
            Diagnostics.log("draw #\(drawAttempts): drawableSize=\(view.drawableSize) "
                            + "bounds=\(view.bounds.size) paused=\(view.isPaused)")
        }

        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTime, 0.05))
        lastTime = now
        elapsed += dt

        viewportSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        aspect = max(viewportSize.x, 1) / max(viewportSize.y, 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            if drawAttempts <= 3 {
                Diagnostics.log("draw #\(drawAttempts): no command buffer, pass descriptor or drawable")
            }
            return
        }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        updateSimulation(dt: dt)
        buildInstances()
        writeFrameUniforms()

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.label = "AfterDark"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(frameUniforms, offset: 0, index: 1)
        encoder.setFragmentTexture(toasterTexture, index: 0)

        drawLayer(encoder, starRange)
        drawLayer(encoder, toastRange)
        drawLayer(encoder, toasterRange)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameCount += 1
        // Heartbeat rather than a single confirmation: if frames stop arriving
        // after the first second, that is a different bug from frames arriving
        // that nobody can see.
        switch frameCount {
        case 60, 600, 1800:
            Diagnostics.log("Animation heartbeat: \(frameCount) frames, "
                            + "elapsed=\(String(format: "%.1f", elapsed))s, "
                            + "window=\(view.window != nil), "
                            + "visible=\(!view.isHidden && view.alphaValue > 0)")
        default:
            break
        }
    }

    private func drawLayer(_ encoder: MTLRenderCommandEncoder, _ range: (start: Int, count: Int)) {
        guard range.count > 0 else { return }
        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: range.count,
                               baseInstance: range.start)
    }

    // MARK: Simulation

    private func updateSimulation(dt: Float) {
        for i in toasts.indices {
            toasts[i].advance(dt: dt)
        }
        for i in toasters.indices {
            toasters[i].advance(dt: dt)
        }
    }

    // MARK: Instance packing

    private func buildInstances() {
        var cursor = 0

        starRange = (cursor, stars.count)
        for star in stars {
            let twinkle = 0.62 + 0.38 * sin(elapsed * star.speed + star.phase)
            let alpha = max(0, min(1, star.brightness * twinkle))
            write(cursor,
                  color: SIMD4(1.0, 1.0, 1.0, alpha),
                  geometry: SIMD4(star.position.x, star.position.y, 0, star.size),
                  shape: SIMD4(1, 1, 0, 0),
                  params: SIMD4(Kind.star.rawValue, 0, 0, 0))
            cursor += 1
        }

        toastRange = (cursor, toasts.count)
        for toast in toasts {
            write(cursor,
                  color: SIMD4(toast.color.x, toast.color.y, toast.color.z, 1.0),
                  geometry: SIMD4(toast.position.x, toast.position.y, Flight.tilt, toast.size),
                  shape: SIMD4(1.02, 1.0, 0, 0),
                  params: SIMD4(Kind.toast.rawValue, 0, 0, 0))
            cursor += 1
        }

        // One sprite instance per toaster; the flap lives in the baked frames.
        toasterRange = (cursor, toasters.count)
        for toaster in toasters {
            let t = 0.5 + 0.5 * sin(elapsed * toaster.flapSpeed + toaster.phase)
            let frame = min(ToasterFrames.frameCount - 1,
                            Int(t * Float(ToasterFrames.frameCount - 1) + 0.5))

            write(cursor,
                  color: SIMD4(1, 1, 1, 1.0),
                  geometry: SIMD4(toaster.position.x, toaster.position.y, Flight.tilt, toaster.size),
                  shape: SIMD4(1.0, 1.0, Self.spritePivot.x, Self.spritePivot.y),
                  params: SIMD4(Kind.toaster.rawValue, 0, Float(frame), 0))
            cursor += 1
        }

        copyScratchToBuffer(count: min(cursor, instanceCapacity))
    }

    private func write(_ index: Int,
                       color: SIMD4<Float>,
                       geometry: SIMD4<Float>,
                       shape: SIMD4<Float>,
                       params: SIMD4<Float>) {
        let o = index * Wire.floatsPerInstance
        guard o + Wire.floatsPerInstance <= scratch.count else { return }

        scratch[o + 0] = color.x
        scratch[o + 1] = color.y
        scratch[o + 2] = color.z
        scratch[o + 3] = color.w

        scratch[o + 4] = geometry.x
        scratch[o + 5] = geometry.y
        scratch[o + 6] = geometry.z
        scratch[o + 7] = geometry.w

        scratch[o + 8] = shape.x
        scratch[o + 9] = shape.y
        scratch[o + 10] = shape.z
        scratch[o + 11] = shape.w

        scratch[o + 12] = params.x
        scratch[o + 13] = params.y
        scratch[o + 14] = params.z
        scratch[o + 15] = params.w
    }

    private func copyScratchToBuffer(count: Int) {
        let floats = count * Wire.floatsPerInstance
        guard floats > 0 else { return }
        scratch.withUnsafeBytes { raw in
            instanceBuffer.contents()
                .copyMemory(from: raw.baseAddress!, byteCount: floats * MemoryLayout<Float>.size)
        }
    }

    private func writeFrameUniforms() {
        let base = frameUniforms.contents().bindMemory(to: Float.self, capacity: 4)
        base[0] = viewportSize.x
        base[1] = viewportSize.y
        base[2] = 0
        base[3] = 0
    }
}
