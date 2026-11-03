import Cocoa
import Metal
import FlyingToastersKit

/// A borderless window that can take key events.
private final class SaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One full-screen run: a black, screen-saver-level window on every display,
/// each hosting its own `ToasterView`, torn down on any key, click, scroll or
/// real mouse movement.
///
/// This is what the system screen saver would do, minus `legacyScreenSaver`,
/// whose window handoff is unreliable on macOS 26.
final class SaverSession {

    private(set) var isActive = false

    private var windows: [NSWindow] = []
    private var views: [ToasterView] = []
    private var renderers: [FlyingToastersRenderer] = []
    private var monitors: [Any] = []
    private var timer: Timer?
    private var startedAt = Date()
    private var startMouse = NSPoint.zero
    private var screenCount = 0
    private let onEnd: () -> Void

    /// Input is ignored this long after starting, so the gesture that launched
    /// the session (a hand still resting at the corner) cannot dismiss it.
    private let grace: TimeInterval = 0.8
    /// How far the pointer must travel, in points, to count as "moved".
    private let moveThreshold: CGFloat = 30

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
    }

    func start() {
        guard !isActive else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("[FlyingToasters] no Metal device")
            return
        }

        for screen in NSScreen.screens {
            guard let renderer = FlyingToastersRenderer(device: device) else { continue }

            let window = SaverWindow(contentRect: screen.frame,
                                     styleMask: .borderless,
                                     backing: .buffered,
                                     defer: false,
                                     screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: false)

            let view = ToasterView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                   device: device)
            view.delegate = renderer
            window.contentView = view

            window.orderFrontRegardless()
            view.startAnimating()

            windows.append(window)
            views.append(view)
            renderers.append(renderer)
        }

        guard !windows.isEmpty else { return }

        isActive = true
        startedAt = Date()
        startMouse = NSEvent.mouseLocation
        screenCount = NSScreen.screens.count

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        NSCursor.hide()

        let inputMask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown,
                                                .otherMouseDown, .scrollWheel]
        if let local = NSEvent.addLocalMonitorForEvents(matching: inputMask, handler: { [weak self] event in
            self?.userActivity()
            return nil   // swallow, so the dismissing key does not beep
        }) {
            monitors.append(local)
        }
        // Clicks and scrolls aimed at another app's window still dismiss us.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: inputMask, handler: { [weak self] _ in
            self?.userActivity()
        }) {
            monitors.append(global)
        }

        // Pointer movement is polled, not monitored: it needs no permissions and
        // lets us apply a distance threshold.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func end() {
        guard isActive else { return }
        isActive = false

        timer?.invalidate()
        timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()

        views.forEach { $0.stopAnimating() }
        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        views.removeAll()
        windows.removeAll()
        renderers.removeAll()

        NSCursor.unhide()
        onEnd()
    }

    // MARK: Dismissal

    private func userActivity() {
        guard Date().timeIntervalSince(startedAt) > grace else { return }
        end()
    }

    private func tick() {
        // A display was plugged in or removed; our windows no longer match.
        if NSScreen.screens.count != screenCount {
            end()
            return
        }
        guard Date().timeIntervalSince(startedAt) > grace else {
            startMouse = NSEvent.mouseLocation
            return
        }
        let p = NSEvent.mouseLocation
        if hypot(p.x - startMouse.x, p.y - startMouse.y) > moveThreshold {
            end()
        }
    }
}
