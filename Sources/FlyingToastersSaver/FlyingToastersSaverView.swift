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

    /// How many saver views are alive in this process. The host does not discard
    /// the previous instance when it starts a new session, so this climbing past 1
    /// on the second trigger is normal — and it is the clue when the newest view
    /// draws fine but something older is covering it.
    private static var liveInstances = 0

    /// Monotonic session number. Used to decide whether an ended session was the
    /// last one, or whether a newer instance has already taken over.
    private static var latestInstance = 0
    private var instanceNumber = 0

    deinit {
        Self.liveInstances -= 1
        Diagnostics.log("saver: deinit, live instances now \(Self.liveInstances)")
    }

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
        Diagnostics.log("saver: startAnimation window=\(window != nil) bounds=\(bounds.size)")
        metalView?.startAnimating()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        Diagnostics.log("saver: stopAnimation")
        metalView?.stopAnimating()
    }

    /// MTKView draws itself; the host only needs to clear behind it.
    public override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
    }

    // MARK: Setup

    private func buildScene(isPreview: Bool) {
        Diagnostics.reset()
        Self.liveInstances += 1
        Self.latestInstance += 1
        instanceNumber = Self.latestInstance
        Diagnostics.log("saver: buildScene preview=\(isPreview) frame=\(frame) bounds=\(bounds) "
                        + "liveInstances=\(Self.liveInstances) instance=\(instanceNumber)")

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
        view.onLeaveWindow = { [weak self] in
            self?.endSessionIfLast()
        }
        addSubview(view)

        // Identity of this instance, so a multi-display run can be told apart.
        let screenInfo = window?.screen.map {
            "screen=\($0.frame.size) scale=\($0.backingScaleFactor)"
        } ?? "screen=nil"
        Diagnostics.log("saver: metal view added frame=\(view.frame) "
                        + "inWindow=\(view.window != nil) \(screenInfo)")

        self.renderer = renderer
        self.metalView = view
    }

    /// Lets a finished session take the host process with it.
    ///
    /// `legacyScreenSaver` does not reuse or dispose of saver views across
    /// sessions: it constructs a new one each time and gives it a new window.
    /// On macOS 26+, the first session in a process renders and every later one
    /// draws into a window that never appears — a verified 1800 frames of output
    /// with nothing on screen. Nothing inside our layer can fix that, because
    /// every property we can observe is correct.
    ///
    /// Exiting when the final session ends means the next trigger gets a fresh
    /// host process, which is the one state known to work. The delay and the
    /// `latestInstance` re-check keep us from racing a newer session that is
    /// already starting.
    private func endSessionIfLast() {
        guard !isPreview else { return }
        let mine = instanceNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard mine == Self.latestInstance else {
                Diagnostics.log("saver: session \(mine) ended, but session "
                                + "\(Self.latestInstance) took over; staying alive")
                return
            }
            Diagnostics.log("saver: last session ended, exiting host process "
                            + "so the next run starts clean")
            exit(0)
        }
    }
}
