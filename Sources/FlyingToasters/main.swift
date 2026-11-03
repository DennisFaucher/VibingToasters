import Cocoa
import Metal
import FlyingToastersKit

/// How the app was launched.
///
///     FlyingToasters            background agent: menu-bar item + top-right hot corner
///     FlyingToasters --saver    run full screen once, then quit (for Shortcuts / testing)
///     FlyingToasters --window   the original 1280x800 window
enum Mode {
    case agent, saverOnce, window
}

@main
struct FlyingToastersApp {
    static func main() {
        let args = CommandLine.arguments
        let mode: Mode = args.contains("--window") ? .window
                       : args.contains("--saver") ? .saverOnce
                       : .agent

        let app = NSApplication.shared
        let delegate = AppDelegate(mode: mode)
        app.delegate = delegate
        // Agent and saver modes have no Dock icon or menu bar of their own.
        app.setActivationPolicy(mode == .window ? .regular : .accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let mode: Mode

    // Window mode.
    private var window: NSWindow!
    private var renderer: FlyingToastersRenderer!

    // Agent and saver modes.
    private var session: SaverSession?
    private var hotCorner: HotCornerMonitor?
    private var statusItem: NSStatusItem?

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .window:
            launchWindow()
        case .saverOnce:
            let session = SaverSession(onEnd: { NSApp.terminate(nil) })
            self.session = session
            session.start()
            if !session.isActive { NSApp.terminate(nil) }
        case .agent:
            launchAgent()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        mode == .window
    }

    // MARK: Agent

    private func launchAgent() {
        let session = SaverSession(onEnd: {})
        self.session = session

        let corner = HotCornerMonitor(isBusy: { session.isActive },
                                      onTrigger: { session.start() })
        corner.start()
        hotCorner = corner

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🍞"
        let menu = NSMenu()
        let start = NSMenuItem(title: "Start Flying Toasters", action: #selector(startNow), keyEquivalent: "")
        start.target = self
        menu.addItem(start)
        let info = NSMenuItem(title: "Hot corner: top right", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func startNow() {
        // Let the menu finish closing before the full-screen windows appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.session?.start()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Window mode

    private func launchWindow() {
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
        view.startAnimating()
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
