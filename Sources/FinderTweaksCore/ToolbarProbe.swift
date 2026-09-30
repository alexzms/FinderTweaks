import ApplicationServices

/// Layout of a Finder window's toolbar. All frames are relative to the window's top-left corner
/// (AX orientation, y grows downward), so they stay valid while the window moves.
public struct ToolbarInfo: Equatable {
    public struct Control: Equatable {
        public let role: String
        public let subrole: String
        public let frame: CGRect

        public init(role: String, subrole: String, frame: CGRect) {
            self.role = role
            self.subrole = subrole
            self.frame = frame
        }
    }

    public static let windowButtonSubroles: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton",
                                                           "AXFullScreenButton"]

    public var windowSize: CGSize
    public var toolbar: CGRect?
    /// The element showing the window title, when it could be matched.
    public var title: CGRect?
    /// Buttons, menus, search etc. inside the toolbar band (window buttons included).
    public var controls: [Control]
    /// A file browser window (not Settings, Get Info, …).
    public var isBrowser: Bool

    public init(windowSize: CGSize, toolbar: CGRect?, title: CGRect?, controls: [Control], isBrowser: Bool) {
        self.windowSize = windowSize
        self.toolbar = toolbar
        self.title = title
        self.controls = controls
        self.isBrowser = isBrowser
    }

    /// The free horizontal stretch that holds the title: from the right edge of whatever sits left of
    /// it (back/forward) to the left edge of the first item after it. Without a title, the widest gap.
    public func titleSpan() -> (minX: CGFloat, maxX: CGFloat, midY: CGFloat)? {
        let frames = controls.map(\.frame)
        if let t = title {
            let left = frames.filter { $0.maxX <= t.minX + 2 }.map(\.maxX).max() ?? (t.minX - 4)
            let right = frames.filter { $0.minX >= t.minX + 8 }.map(\.minX).min() ?? (windowSize.width - 8)
            return (left, right, t.midY)
        }
        guard let gap = Self.widestGap(frames, from: 8, to: windowSize.width - 8) else { return nil }
        let midY = Self.median(frames.map(\.midY)) ?? toolbar?.midY ?? 16
        return (gap.0, gap.1, midY)
    }

    /// The search field while it is shown as a full field (it collapses to a button when room runs out).
    /// Finder gives it all the free room in the toolbar before the title gets any.
    public var expandedSearchField: CGRect? {
        controls.first { $0.role == "AXTextField" && $0.subrole == "AXSearchField" }?.frame
    }

    /// Height of the toolbar's own controls, to size things placed among them.
    public var typicalControlHeight: CGFloat? {
        controls.first { $0.subrole == "AXSearchField" }?.frame.height
            ?? Self.median(controls.filter { !Self.windowButtonSubroles.contains($0.subrole) }.map(\.frame.height))
    }

    public var summary: String {
        func s(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
        let items = controls.map { c in
            "\(c.role.dropFirst(2))\(c.subrole.isEmpty ? "" : "/" + c.subrole.dropFirst(2))@\(s(c.frame))"
        }
        return "win \(Int(windowSize.width))x\(Int(windowSize.height)) browser=\(isBrowser)"
            + " toolbar=\(toolbar.map(s) ?? "none") title=\(title.map(s) ?? "none")"
            + " controls=[\(items.joined(separator: " "))]"
    }

    static func widestGap(_ rects: [CGRect], from lo: CGFloat, to hi: CGFloat) -> (CGFloat, CGFloat)? {
        var best: (CGFloat, CGFloat)?
        var cursor = lo
        for r in rects.sorted(by: { $0.minX < $1.minX }) {
            if r.minX - cursor > (best.map { $0.1 - $0.0 } ?? 0) { best = (cursor, r.minX) }
            cursor = max(cursor, r.maxX)
        }
        if hi - cursor > (best.map { $0.1 - $0.0 } ?? 0) { best = (cursor, hi) }
        return best
    }

    static func median(_ xs: [CGFloat]) -> CGFloat? {
        guard !xs.isEmpty else { return nil }
        return xs.sorted()[xs.count / 2]
    }
}

/// Reads a Finder window's toolbar through Accessibility, without descending into file lists.
public enum ToolbarProbe {
    static let skipRoles: Set<String> = ["AXScrollArea", "AXOutline", "AXTable", "AXList", "AXBrowser",
                                         "AXGrid", "AXWebArea", "AXMenuBar", "AXMenu"]
    static let controlRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXRadioButton",
                                            "AXRadioGroup", "AXCheckBox", "AXTextField", "AXComboBox",
                                            "AXSegmentedControl", "AXSlider"]

    public struct Result {
        public let info: ToolbarInfo
        /// Finder's search field element, when expanded.
        public let searchField: AXUIElement?
    }

    public static func probe(window: AXUIElement, frame F: CGRect, title: String, hasPath: Bool) -> Result {
        var nodes: [AXNode] = []
        var budget = 400
        func walk(_ list: [AXNode], depth: Int) {
            for node in list where budget > 0 {
                budget -= 1
                if let f = node.frame, !(f.maxY > F.minY && f.minY < F.minY + 80) { continue }
                nodes.append(node)
                if depth < 8 && !skipRoles.contains(node.role) {
                    walk(AX.children(node.element).compactMap(AXNode.init), depth: depth + 1)
                }
            }
        }
        walk(AX.children(window).compactMap(AXNode.init), depth: 0)

        func rel(_ r: CGRect) -> CGRect { r.offsetBy(dx: -F.minX, dy: -F.minY) }
        let toolbar = nodes.first { $0.role == "AXToolbar" }?.frame.map(rel)
        let bandTop = toolbar?.minY ?? 0
        let bandBottom = toolbar?.maxY ?? 32
        let inside = CGRect(origin: .zero, size: F.size).insetBy(dx: -2, dy: -2)
        func inBand(_ r: CGRect) -> Bool { inside.contains(r) && r.midY > bandTop && r.midY < bandBottom }

        // The element showing the window title; prefer static text over e.g. a button with that name.
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var titleFrame: CGRect?
        var titleIsText = false
        for node in nodes where !wanted.isEmpty && node.text == wanted {
            guard let f = node.frame.map(rel), f.width > 2, inBand(f) else { continue }
            let isText = node.role == "AXStaticText"
            if titleFrame == nil || (isText && !titleIsText) {
                titleFrame = f
                titleIsText = isText
            }
        }

        let controls = nodes.compactMap { n -> ToolbarInfo.Control? in
            guard controlRoles.contains(n.role), let f = n.frame.map(rel), f != titleFrame,
                  f.width > 4, f.height > 4, f.width < F.width * 0.6, inBand(f) else { return nil }
            return ToolbarInfo.Control(role: n.role, subrole: n.subrole, frame: f)
        }
        let isBrowser = nodes.contains { $0.role == "AXSplitGroup" } || (hasPath && toolbar != nil)
        let info = ToolbarInfo(windowSize: F.size, toolbar: toolbar, title: titleFrame, controls: controls,
                               isBrowser: isBrowser)
        let search = nodes.first { $0.role == "AXTextField" && $0.subrole == "AXSearchField" }?.element
        return Result(info: info, searchField: search)
    }
}
