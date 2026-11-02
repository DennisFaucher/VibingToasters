import Cocoa
import Metal
import MetalKit

/// A Metal view pre-configured to run continuously off MTKView's own display link.
///
/// Both front ends (the app and the screen saver) host one of these, so the
/// configuration lives in one place and cannot drift between them.
public final class ToasterView: MTKView {

    /// Called for key presses. The app uses it for ⌘-less shortcuts; the screen
    /// saver leaves it nil because the system owns input there.
    public var onKey: ((UInt16) -> Void)?

    public override var acceptsFirstResponder: Bool { true }

    public init(frame: NSRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        autoResizeDrawable = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
    }

    public required init(coder: NSCoder) {
        fatalError("ToasterView is only created programmatically")
    }

    public override func keyDown(with event: NSEvent) {
        onKey?(event.keyCode)
        super.keyDown(with: event)
    }
}
