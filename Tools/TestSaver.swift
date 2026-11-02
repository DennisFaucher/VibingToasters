import Cocoa
import ScreenSaver

// Loads a .saver bundle exactly as legacyScreenSaver does — NSBundle, then the
// principal class from Info.plist — and hosts it in a window.
//
//   swiftc -O Tools/TestSaver.swift -o /tmp/testsaver -framework ScreenSaver
//   /tmp/testsaver FlyingToasters.saver            # single session
//   /tmp/testsaver FlyingToasters.saver --cycle    # repeat sessions, as the host does
//
// `--cycle` matters. The real host does not create a fresh view per session and
// throw the old one away: it calls startAnimation() on the previous instance and
// then constructs a new one, so several saver views can be alive at once. The
// black-screen bug only appears on the second and later sessions, so a single-shot
// harness cannot see it.

final class Harness: NSObject, NSApplicationDelegate {
    let bundle: Bundle
    let cycles: Bool
    var window: NSWindow!
    var current: ScreenSaverView?
    var session = 0

    init(bundle: Bundle, cycles: Bool) {
        self.bundle = bundle
        self.cycles = cycles
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let principal = bundle.principalClass else {
            print("FAIL: no principal class in Info.plist")
            NSApp.terminate(nil)
            return
        }
        print("principal class: \(principal)")

        guard let type = principal as? ScreenSaverView.Type else {
            print("FAIL: principal class is not a ScreenSaverView")
            NSApp.terminate(nil)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Saver Harness"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startSession(type: type, frame: frame)

        if cycles {
            Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                self.startSession(type: type, frame: frame)
            }
        }
    }

    private func startSession(type: ScreenSaverView.Type, frame: NSRect) {
        session += 1
        print("--- session \(session) ---")

        // Mimic the host: the previous instance gets startAnimation() again...
        current?.startAnimation()

        // ...and then a whole new instance is constructed and displayed.
        guard let saver = type.init(frame: frame, isPreview: false) else {
            print("FAIL: init(frame:isPreview:) returned nil")
            return
        }
        window.contentView = saver
        saver.startAnimation()
        current = saver
        print("session \(session) hosting \(saver)")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let cycles = args.contains("--cycle")
args.removeAll { $0 == "--cycle" }
let path = args.first ?? "FlyingToasters.saver"

guard let bundle = Bundle(path: path) else {
    fatalError("could not open bundle at \(path)")
}
print("loaded bundle: \(bundle.bundlePath)")
print("resources: \(bundle.resourcePath ?? "<none>")")
print("cycle mode: \(cycles)")

let app = NSApplication.shared
let harness = Harness(bundle: bundle, cycles: cycles)
app.delegate = harness
app.setActivationPolicy(.regular)
app.run()
