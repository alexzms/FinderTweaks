import AppKit

public enum Geometry {
    /// AX/CG global coordinates (origin top-left of the primary screen) → Cocoa (origin bottom-left).
    public static func cocoa(_ r: CGRect) -> NSRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX.rounded(), y: (h - r.maxY).rounded(), width: r.width.rounded(), height: r.height.rounded())
    }
}

/// True when some other window covers `rect` (AX coordinates) above the given Finder window — e.g.
/// Finder became active by a click on the desktop while its window is buried under another app.
public enum Occlusion {
    public static func check(_ rect: CGRect, window: CGRect, finderPid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let me = getpid()
        for info in list {  // front to back
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if pid == finderPid && layer == 0 &&
                abs(b.minX - window.minX) < 2 && abs(b.minY - window.minY) < 2 &&
                abs(b.width - window.width) < 2 && abs(b.height - window.height) < 2 {
                return false  // reached the Finder window itself; nothing above it overlaps
            }
            let relevant = layer == 0 || (pid == finderPid && layer > 0 && layer < 20)
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            if relevant && pid != me && alpha > 0.05 && b.intersects(rect) { return true }
        }
        return false
    }
}
