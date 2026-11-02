import Foundation

/// File-based diagnostics.
///
/// The screen saver runs inside Apple's sandboxed `legacyScreenSaver` host. That
/// process has no Mach-lookup exception for `MTLCompilerService`, and its unified
/// logging is not reliably reachable either — so a failure there presents as an
/// unexplained black screen. This writes plain lines to the host's container
/// temporary directory, which is the only location the sandbox permits and is
/// readable from outside:
///
///     ~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/tmp/FlyingToastersSaver.log
///
/// `NSLog` is kept alongside it so the standalone app behaves as before.
public enum Diagnostics {

    public static var logURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FlyingToastersSaver.log")
    }

    private static var didResetThisProcess = false

    /// Truncates the log once per process.
    ///
    /// Not once per instance: the host creates one screen saver view per display,
    /// and resetting each time would leave only the last display's history — which
    /// is exactly the wrong thing to hide when one screen is black and another is
    /// fine.
    public static func reset() {
        guard !didResetThisProcess else { return }
        didResetThisProcess = true
        try? FileManager.default.removeItem(at: logURL)
    }

    public static func log(_ message: String) {
        NSLog("[FlyingToasters] %@", message)

        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp)  \(message)\n".data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
