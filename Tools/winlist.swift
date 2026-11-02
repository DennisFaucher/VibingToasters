import CoreGraphics
import Foundation

// Prints "<window id>\t<owner>\t<bounds>" for matching windows. The owner
// substring defaults to "FlyingToasters"; pass one to target another process
// (e.g. the saver harness).
//
//   WID=$(swift Tools/winlist.swift | head -1 | cut -f1)
//   screencapture -x -o -l "$WID" /tmp/ft.png
//
// Capture by window ID rather than with a bare `screencapture`, which grabs
// whatever happens to be frontmost.

let match = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FlyingToasters"

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for window in list {
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        guard owner.contains(match) else { continue }
        let number = window[kCGWindowNumber as String] as? Int ?? -1
        let bounds = window[kCGWindowBounds as String] ?? ""
        print("\(number)\t\(owner)\t\(bounds)")
    }
}
