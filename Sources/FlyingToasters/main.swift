import Cocoa
import Metal
import FlyingToastersKit

@main
struct FlyingToastersApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var renderer: FlyingToastersRenderer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            presentFatalError("This Mac does not expose a Metal device.")
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Flying Toasters"
        window.center()
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)

        let view = ToasterView(frame: frame, device: device)
        view.onKey = { [weak self] keyCode in
            switch keyCode {
            case 53, 12:                 // esc, q
                NSApp.terminate(nil)
            case 3:                      // f
                self?.window.toggleFullScreen(nil)
            default:
                break
            }
        }

        guard let renderer = FlyingToastersRenderer(device: device) else {
            presentFatalError("Failed to initialise the Metal renderer. See the console log for details.")
            return
        }
        self.renderer = renderer
        view.delegate = renderer

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Flying Toasters"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
