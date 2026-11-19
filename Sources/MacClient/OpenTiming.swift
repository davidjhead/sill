import Foundation
import StreamProtocol

/// How long a window takes from the pick to its picture, step by step, written to
/// ~/Library/Logs/Sill Viewer/open-timing.log while the `SillTiming` default is on
/// (`defaults write me.saffer.sill.client SillTiming -bool YES`, then relaunch). Each line is the
/// milliseconds since the last pick: the pick sent, the host's list naming the source, each of the
/// stream's parameter sets (a second set before the picture means the host restarted the stream),
/// its keyframes with their size, and the first frame routed into the window, for 5 s after the pick. Any thread.
enum OpenTiming {
    static let enabled = UserDefaults.standard.bool(forKey: "SillTiming")
    private static let lock = NSLock()
    private static var start: CFAbsoluteTime = 0
    private static var source = ""
    private static var drawn = false
    private static var sets = 0
    /// Seconds after a pick that its stream is followed: a restart after the first picture shows too.
    private static let window: CFAbsoluteTime = 5
    private static weak var pickedFeed: FrameSink?
    /// The picked window's feed: the timing ends when the main stream draws into it.
    static var feed: FrameSink? { lock.lock(); defer { lock.unlock() }; return drawn ? nil : pickedFeed }
    private static let file: FileHandle? = {
        guard enabled else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sill Viewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("open-timing.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    /// A pick sent: the clock starts again.
    static func picked(_ s: StreamSource, _ note: String = "", feed: FrameSink? = nil) {
        guard enabled else { return }
        lock.lock(); start = CFAbsoluteTimeGetCurrent(); source = "\(s)"; drawn = false; sets = 0; pickedFeed = feed; lock.unlock()
        write("── pick \(s) \(note)")
    }

    static func mark(_ what: String) {
        guard enabled else { return }
        lock.lock(); let ok = start > 0 && CFAbsoluteTimeGetCurrent() - start < window; lock.unlock()
        if ok { write(what) }
    }

    static func parameterSets() {
        guard enabled else { return }
        lock.lock(); sets += 1; let n = sets, ok = start > 0 && CFAbsoluteTimeGetCurrent() - start < window; lock.unlock()
        if ok { write("parameter sets #\(n)") }
    }

    static func frame(_ bytes: Int, keyframe: Bool) {
        guard enabled, keyframe else { return }
        mark("keyframe \(bytes / 1024) KB")
    }

    /// The first frame of the picked source's stream into its window: the end of the timing.
    static func firstDrawn(_ bytes: Int, keyframe: Bool) {
        guard enabled else { return }
        lock.lock(); let first = start > 0 && !drawn; drawn = true; lock.unlock()
        if first { write("first frame into the window (\(keyframe ? "keyframe" : "frame"), \(bytes / 1024) KB) ══ done") }
    }

    private static func write(_ line: String) {
        lock.lock()
        let ms = start > 0 ? Int((CFAbsoluteTimeGetCurrent() - start) * 1000) : 0
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime, .withFractionalSeconds])
        file?.write(Data("\(stamp) +\(String(format: "%5d", ms)) ms  \(line)\n".utf8))
        lock.unlock()
    }
}
