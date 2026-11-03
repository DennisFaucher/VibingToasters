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

    /// Marks the start of a new host process in the log.
    ///
    /// The log is appended to across processes, not truncated: the saver now
    /// exits its host after every session, so truncating per process would
    /// erase the previous (possibly black) run before anyone could read it. The
    /// file is only trimmed once it grows past a size cap.
    public static func reset() {
        guard !didResetThisProcess else { return }
        didResetThisProcess = true
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        if size > 256_000 { try? FileManager.default.removeItem(at: logURL) }
        log("===== host process start pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "age=\(processAge().map { String(format: "%.1fs", $0) } ?? "?") =====")
    }

    /// Seconds since this process was launched. The host is respawned by the
    /// system right after it exits, long before the next trigger builds a view,
    /// so "first log line" is not the launch time; this is.
    public static func processAge() -> TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, ProcessInfo.processInfo.processIdentifier]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date().timeIntervalSince1970 - (Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
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
