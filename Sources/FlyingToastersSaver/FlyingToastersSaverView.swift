import Cocoa
import Metal
import MetalKit
import ScreenSaver
import FlyingToastersKit

/// The screen saver plugin.
///
/// macOS loads this class as the principal class of `FlyingToasters.saver`, inside
/// Apple's `legacyScreenSaver` host, one instance per display. It does nothing
/// clever: it hosts a `ToasterView` and lets MTKView's display link drive the
/// renderer, exactly as the standalone app does.
@objc(FlyingToastersSaverView)
public final class FlyingToastersSaverView: ScreenSaverView {

    private var renderer: FlyingToastersRenderer?
    private var metalView: ToasterView?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        buildScene(isPreview: isPreview)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildScene(isPreview: isPreview)
    }

    public override var isOpaque: Bool { true }

    // MARK: Animation

    public override func startAnimation() {
        super.startAnimation()
        metalView?.isPaused = false
    }

    public override func stopAnimation() {
        super.stopAnimation()
        metalView?.isPaused = true
    }

    /// MTKView draws itself; the host only needs to clear behind it.
    public override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
    }

    // MARK: Setup

    private func buildScene(isPreview: Bool) {
        Diagnostics.reset()
        Diagnostics.log("saver: buildScene preview=\(isPreview) frame=\(frame) bounds=\(bounds)")

        wantsLayer = true

        // Sizes are in normalised device coordinates, so the composition is the
        // same at any view size and the preview tile does not need rescaling.
        // Only the object count is thinned, so a small thumbnail is not a solid
        // field of stars.
        let density: Float = isPreview ? 0.5 : 1.0

        guard let device = MTLCreateSystemDefaultDevice() else {
            Diagnostics.log("saver: no Metal device")
            return
        }
        Diagnostics.log("saver: device \(device.name)")

        guard let renderer = FlyingToastersRenderer(device: device, density: density) else {
            Diagnostics.log("saver: renderer init failed")
            return
        }

        let view = ToasterView(frame: bounds, device: device)
        view.delegate = renderer
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        Diagnostics.log("saver: metal view added with frame \(view.frame)")

        self.renderer = renderer
        self.metalView = view
    }
}
