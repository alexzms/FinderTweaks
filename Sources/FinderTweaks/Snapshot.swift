import AppKit

/// Renders feature UI offscreen to PNGs, to check looks in light/dark without driving Finder.
enum Snapshot {
    final class Backdrop: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }

    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let deep = NSHomeDirectory() + "/Documents/Projects/2026/a-rather-long-folder-name/最终的文件夹"
        let cases: [(String, NSAppearance.Name, (PathBarView) -> Void)] = [
            ("pathbar-light-long", .aqua, { $0.setDisplay(path: deep, title: "") }),
            ("pathbar-dark-long", .darkAqua, { $0.setDisplay(path: deep, title: "") }),
            ("pathbar-light-short", .aqua, { $0.setDisplay(path: NSHomeDirectory() + "/Downloads", title: "") }),
            ("pathbar-light-hover-root", .aqua, { $0.setDisplay(path: "/", title: ""); $0.hovered = true }),
            ("pathbar-light-editing", .aqua, { $0.setEditing(true, text: "~/Library/Application Support/Cl") }),
            ("pathbar-dark-candidates", .darkAqua, {
                $0.setEditing(true, text: "~/Library/Application Support/Cl")
                $0.flash("Claude  CloudDocs  CloudKit  …共 7 项", error: false)
            }),
            ("pathbar-light-error", .aqua, { $0.setEditing(true, text: "~/nope"); $0.flash("找不到这个路径", error: true) }),
            ("pathbar-dark-recents", .darkAqua, { $0.setDisplay(path: nil, title: "最近使用") }),
        ]
        for (name, appearance, configure) in cases {
            let backdrop = Backdrop(frame: NSRect(x: 0, y: 0, width: 460, height: 48))
            backdrop.appearance = NSAppearance(named: appearance)
            let bar = PathBarView(frame: NSRect(x: 20, y: 10, width: 420, height: 28))
            backdrop.addSubview(bar)
            configure(bar)
            bar.layout()
            write(backdrop, to: "\(dir)/\(name).png")
        }
        print("wrote \(cases.count) snapshots to \(dir)")
    }

    static func write(_ view: NSView, to path: String) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                             pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
