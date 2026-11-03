import Cocoa

/// Fires once when the pointer rests in the top-right corner of any display.
///
/// The system hot corner can only run built-in actions, so this replaces it.
/// Position is polled (`NSEvent.mouseLocation`), which needs no permissions.
final class HotCornerMonitor {

    /// How close to the corner counts, in points.
    private let reach: CGFloat = 3
    /// How long the pointer must rest there, so a fast swipe past does nothing.
    private let dwell: TimeInterval = 0.25

    private var timer: Timer?
    private var enteredAt: Date?
    /// Cleared after firing; set again only once the pointer has left the corner,
    /// so a pointer parked in the corner does not retrigger every session.
    private var armed = true

    private let isBusy: () -> Bool
    private let onTrigger: () -> Void

    init(isBusy: @escaping () -> Bool, onTrigger: @escaping () -> Void) {
        self.isBusy = isBusy
        self.onTrigger = onTrigger
    }

    func start() {
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func pointerInTopRight() -> Bool {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let f = screen.frame
            return p.x >= f.maxX - reach && p.x <= f.maxX
                && p.y >= f.maxY - reach && p.y <= f.maxY
        }
    }

    private func tick() {
        guard pointerInTopRight() else {
            armed = true
            enteredAt = nil
            return
        }
        guard armed, !isBusy() else { return }

        if let entered = enteredAt {
            if Date().timeIntervalSince(entered) >= dwell {
                armed = false
                enteredAt = nil
                onTrigger()
            }
        } else {
            enteredAt = Date()
        }
    }
}
