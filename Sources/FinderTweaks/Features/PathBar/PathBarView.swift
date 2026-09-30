import AppKit
import FinderTweaksCore

/// Borderless floating panel that can take keyboard focus without activating this app,
/// so Finder stays the frontmost app while you type a path.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 28),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // An accessory app has no Edit menu, so the standard editing shortcuts are wired up by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            let shift = flags.contains(.shift)
            switch key {
            case "x" where !shift: return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c" where !shift: return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v" where !shift: return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "a" where !shift: return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "z":
                guard let undo = firstResponder?.undoManager else { return false }
                if shift { undo.redo() } else { undo.undo() }
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The capsule itself: folder icon + tail-first path label, swapped for a text field while editing.
final class PathBarView: NSView {
    enum Style { case normal, editing, error }

    static let font = NSFont.systemFont(ofSize: 13)
    static let boldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    let field = NSTextField(string: "")
    let hint = NSTextField(labelWithString: "")
    weak var feature: PathBarFeature?

    var style = Style.normal { didSet { needsDisplay = true } }
    var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }

    private var flashGeneration = 0
    private var mouseDownAt: NSPoint?
    private var draggingWindow = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .secondaryLabelColor

        label.font = Self.font
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        field.font = Self.font
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = "输入路径后回车 · Tab 补全 · Esc 取消"
        field.isHidden = true

        hint.font = .systemFont(ofSize: 11)
        hint.lineBreakMode = .byTruncatingTail
        hint.isHidden = true

        [icon, label, field, hint].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Content

    func setDisplay(path: String?, title: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        let text = NSMutableAttributedString()
        if let path {
            let (parent, last) = Paths.split(Paths.abbreviate(path))
            text.append(NSAttributedString(string: parent, attributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]))
            text.append(NSAttributedString(string: last, attributes: [.font: Self.boldFont, .foregroundColor: NSColor.labelColor]))
            icon.image = Self.icon(for: path)
        } else {
            text.append(NSAttributedString(string: title, attributes: [.font: Self.boldFont, .foregroundColor: NSColor.labelColor]))
            icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        }
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text
    }

    func setEditing(_ on: Bool, text: String) {
        clearFlash()
        style = on ? .editing : .normal
        label.isHidden = on
        field.isHidden = !on
        if on { field.stringValue = text }
        hovered = false
    }

    /// Shows a short message at the right end of the bar (errors in red, completion candidates in grey).
    func flash(_ message: String, error: Bool) {
        hint.stringValue = message
        hint.textColor = error ? .systemRed : .secondaryLabelColor
        hint.isHidden = false
        if error { style = .error }
        needsLayout = true
        flashGeneration += 1
        let generation = flashGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 2.5 : 4)) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.clearFlash()
        }
    }

    func clearFlash() {
        flashGeneration += 1
        guard !hint.isHidden || style == .error else { return }
        hint.isHidden = true
        if style == .error { style = field.isHidden ? .normal : .editing }
        needsLayout = true
    }

    private static var iconCache: (path: String, image: NSImage)?
    private static func icon(for path: String) -> NSImage {
        if let cached = iconCache, cached.path == path { return cached.image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        iconCache = (path, image)
        return image
    }

    // MARK: Layout & drawing

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 10, y: ((h - 16) / 2).rounded(), width: 16, height: 16)
        let x: CGFloat = 31
        var width = bounds.width - x - 12
        if !hint.isHidden {
            hint.sizeToFit()
            let hw = min(hint.frame.width, bounds.width * 0.5)
            hint.frame = NSRect(x: bounds.width - 12 - hw, y: ((h - hint.frame.height) / 2).rounded(),
                                width: hw, height: hint.frame.height)
            width -= hw + 8
        }
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: x, y: ((h - lh) / 2).rounded(), width: max(0, width), height: lh)
        let fh = field.intrinsicContentSize.height
        field.frame = NSRect(x: x, y: ((h - fh) / 2).rounded(), width: max(0, width), height: fh)
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = style == .normal ? 1 : 2
        let r = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let capsule = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        var fill = NSColor.controlBackgroundColor
        if hovered && style == .normal { fill = fill.blended(withFraction: 0.06, of: .labelColor) ?? fill }
        fill.setFill()
        capsule.fill()
        let stroke: NSColor = switch style {
        case .normal: .separatorColor
        case .editing: .controlAccentColor
        case .error: .systemRed
        }
        stroke.setStroke()
        capsule.lineWidth = lineWidth
        capsule.stroke()
    }

    // MARK: Mouse: click = edit, drag = move the Finder window, right-click = menu

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return style == .normal ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        guard style == .normal else { return }
        mouseDownAt = NSEvent.mouseLocation
        draggingWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownAt, let feature else { return }
        let p = NSEvent.mouseLocation
        let delta = CGSize(width: p.x - start.x, height: p.y - start.y)
        if !draggingWindow {
            guard hypot(delta.width, delta.height) >= 3 else { return }
            draggingWindow = true
            feature.beginWindowDrag()
        }
        feature.dragWindow(by: delta)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownAt = nil; draggingWindow = false }
        guard mouseDownAt != nil, let feature else { return }
        if draggingWindow { feature.endWindowDrag() } else { feature.beginEditing() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard style == .normal, let feature else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: "编辑路径", action: #selector(PathBarFeature.editPath), keyEquivalent: "").target = feature
        menu.addItem(withTitle: "拷贝路径", action: #selector(PathBarFeature.copyPath), keyEquivalent: "").target = feature
        return menu
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
}
