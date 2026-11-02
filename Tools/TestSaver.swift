import Cocoa
import ScreenSaver

// Loads a .saver bundle exactly as legacyScreenSaver does — NSBundle, then the
// principal class from Info.plist — and hosts it in a window. This verifies the
// plugin path without waiting for the real screen saver to kick in.
//
//   swiftc -O Tools/TestSaver.swift -o /tmp/testsaver -framework ScreenSaver
//   /tmp/testsaver FlyingToasters.saver

final class Harness: NSObject, NSApplicationDelegate {
    let bundle: Bundle
    var window: NSWindow!

    init(bundle: Bundle) { self.bundle = bundle }

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
        guard let saver = type.init(frame: frame, isPreview: false) else {
            print("FAIL: init(frame:isPreview:) returned nil")
            NSApp.terminate(nil)
            return
        }
        print("instance: \(saver)")

        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Saver Harness"
        window.contentView = saver
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        saver.startAnimation()
        print("OK: hosting saver")
    }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FlyingToasters.saver"
guard let bundle = Bundle(path: path) else {
    fatalError("could not open bundle at \(path)")
}
print("loaded bundle: \(bundle.bundlePath)")
print("executable: \(bundle.executablePath ?? "<none>")")
print("resources: \(bundle.resourcePath ?? "<none>")")

let app = NSApplication.shared
let harness = Harness(bundle: bundle)
app.delegate = harness
app.setActivationPolicy(.regular)
app.run()
