import Foundation

/// Diagnostics log at ~/Library/Logs/FinderTweaks.log (`make logs`).
/// Records geometry and status only — never folder or file names.
public enum Log {
    public static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/FinderTweaks.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func write(_ message: String) {
        let data = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000 {
            try? fm.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
