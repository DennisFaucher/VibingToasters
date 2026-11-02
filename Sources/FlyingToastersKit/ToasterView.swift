import Cocoa
import Metal
import MetalKit

/// A Metal view pre-configured to run continuously off MTKView's own display link.
///
/// Both front ends (the app and the screen saver) host one of these, so the
/// configuration lives in one place and cannot drift between them.
///
/// The display link is deliberately **not** started in `init`. MTKView will
/// happily draw before it has a window, presenting into a layer that has no
/// surface behind it, and on the screen saver host that came back as a
/// permanently black screen. Frames only start once someone asks for animation
/// *and* the view is actually attached to a window.
public final class ToasterView: MTKView {

    /// Called for key presses. The app uses it for ⌘-less shortcuts; the screen
    /// saver leaves it nil because the system owns input there.
    public var onKey: ((UInt16) -> Void)?

    /// Animation is the default intent — the view exists to animate. Pausing is
    /// opt-in via `stopAnimating()`, so a host that never calls `startAnimation()`
    /// still gets motion once the view is on screen.
    private var wantsAnimation = true

    public override var acceptsFirstResponder: Bool { true }

    public init(frame: NSRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        autoResizeDrawable = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        isPaused = true
    }

    public required init(coder: NSCoder) {
        fatalError("ToasterView is only created programmatically")
    }

    // MARK: Animation control

    public func startAnimating() {
        wantsAnimation = true
        isPaused = (window == nil)
        Diagnostics.log("view: startAnimating -> paused=\(isPaused) window=\(window != nil)")
    }

    public func stopAnimating() {
        wantsAnimation = false
        isPaused = true
        Diagnostics.log("view: stopAnimating")
    }

    /// Called when the view is detached from its window, i.e. the session ended.
    public var onLeaveWindow: (() -> Void)?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isPaused = !(wantsAnimation && window != nil)
        Diagnostics.log("view: viewDidMoveToWindow window=\(window != nil) "
                        + "paused=\(isPaused) bounds=\(bounds.size) "
                        + "superview=\(superview.map { String(describing: type(of: $0)) } ?? "nil") "
                        + "layer=\(layer.map { String(describing: type(of: $0)) } ?? "nil")")
        if window == nil {
            onLeaveWindow?()
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        Diagnostics.log("view: viewDidMoveToSuperview superview="
                        + "\(superview.map { String(describing: type(of: $0)) } ?? "nil")")
    }

    public override func keyDown(with event: NSEvent) {
        onKey?(event.keyCode)
        super.keyDown(with: event)
    }
}
