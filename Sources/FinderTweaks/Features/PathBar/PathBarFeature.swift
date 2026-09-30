import AppKit
import FinderTweaksCore

/// Parks an editable, tail-first path bar over the focused Finder window's title.
/// Click to type a path (Return jumps, Tab completes, Esc cancels); drag it to move the window.
final class PathBarFeature: NSObject, Feature, NSTextFieldDelegate, NSWindowDelegate {
    let id = "pathBar"
    let title = "路径栏"
    let isToggleable = true
    let needsTracker = true
    var isEnabled = false {
        didSet { if !isEnabled { hide() } }
    }

    private let tracker: FinderTracker
    private let panel = OverlayPanel()
    let bar = PathBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
    let searchButton = SearchButtonView(frame: NSRect(x: 0, y: 0, width: 110, height: 28))
    private var placement: PathBarPlacement?

    /// Cover Finder's search field with the bar plus a short search button (see PathBarPlacement).
    var compactSearch: Bool {
        get { UserDefaults.standard.object(forKey: "pathBar.compactSearch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pathBar.compactSearch") }
    }

    private var window: FinderWindow?
    private var currentPath: String?
    private var currentTitle = ""
    private var editing = false
    private var dragging = false
    private var dragWindowOrigin = CGPoint.zero
    private var dragPanelOrigin = NSPoint.zero
    private var updates = 0
    private var occluded = false

    init(tracker: FinderTracker) {
        self.tracker = tracker
        super.init()
        let container = NSView()
        container.addSubview(bar)
        container.addSubview(searchButton)
        panel.contentView = container
        panel.delegate = self
        bar.feature = self
        bar.field.delegate = self
        searchButton.feature = self
        tracker.observe { [weak self] state in self?.update(state) }
    }

    func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "紧凑搜索框", action: #selector(toggleCompactSearch), keyEquivalent: "")
        item.target = self
        item.indentationLevel = 1
        item.state = compactSearch ? .on : .off
        return [item]
    }

    @objc private func toggleCompactSearch() {
        compactSearch.toggle()
        Log.write("pathBar compactSearch=\(compactSearch)")
        guard compactSearch, !FinderToolbar.searchFollowsTitle else { return }
        let alert = NSAlert()
        alert.messageText = "把搜索框移到标题右边？"
        alert.informativeText = "紧凑搜索框需要搜索框紧挨着窗口标题。会调整访达工具栏的顺序并重启访达，正在进行的拷贝会被中断。"
        alert.addButton(withTitle: "移动并重启访达")
        alert.addButton(withTitle: "取消")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            FinderToolbar.moveSearchAfterTitle()
            FinderPreferences.restartFinder()
        }
    }

    func focusFinderSearch() {
        tracker.focusSearchField()
    }

    private func update(_ state: FinderState) {
        guard isEnabled else { return }
        switch state {
        case .inactive:
            hide()
        case .noWindow:
            // While typing, our panel holds keyboard focus and Finder may report no focused window.
            if !editing { hide() }
        case .window(let w):
            guard !editing, !dragging else { return }
            window = w
            setContent(path: w.path, title: w.title)
            guard w.isSettled, let toolbar = w.toolbar, toolbar.isBrowser,
                  let p = PathBarPlacement.compute(in: toolbar, coverSearch: compactSearch && !w.isSearching)
            else { hide(); return }
            if p != placement {
                placement = p
                let r = p.rect
                Log.write("pathBar at \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)) search=\(Int(p.searchWidth))")
                layoutContent(p)
            }
            let target = p.rect.offsetBy(dx: w.frame.minX, dy: w.frame.minY)
            updates &+= 1
            if updates % 2 == 0 { occluded = Occlusion.check(target, window: w.frame, finderPid: w.pid) }
            guard !occluded else { hide(); return }
            show(at: Geometry.cocoa(target))
        }
    }

    private func setContent(path: String?, title: String) {
        guard path != currentPath || title != currentTitle else { return }
        currentPath = path
        currentTitle = title
        if !editing { bar.setDisplay(path: path, title: title) }
    }

    /// Path capsule on the left; with compact search, the search button at the right end.
    private func layoutContent(_ p: PathBarPlacement) {
        let w = p.rect.width, h = p.rect.height
        let searchSpace = p.searchWidth > 0 ? p.searchWidth + PathBarPlacement.searchGap : 0
        bar.frame = NSRect(x: 0, y: 0, width: w - searchSpace, height: h)
        searchButton.frame = NSRect(x: w - p.searchWidth, y: 0, width: p.searchWidth, height: h)
        searchButton.isHidden = p.searchWidth == 0
        for view in [bar, searchButton] as [NSView] {
            view.needsLayout = true
            view.needsDisplay = true
        }
    }

    private func show(at rect: NSRect) {
        if panel.frame != rect { panel.setFrame(rect, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func hide() {
        endEditing(restoreFocus: false)
        bar.hovered = false
        if panel.isVisible { panel.orderOut(nil) }
    }

    // MARK: Editing

    func beginEditing() {
        guard !editing, panel.isVisible else { return }
        editing = true
        bar.setEditing(true, text: currentPath.map(Paths.abbreviate) ?? "")
        panel.makeKey()
        panel.makeFirstResponder(bar.field)
        if let editor = bar.field.currentEditor() as? NSTextView {
            editor.selectAll(nil)
            editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    func endEditing(restoreFocus: Bool = true) {
        guard editing else { return }
        editing = false
        bar.field.abortEditing()
        bar.setEditing(false, text: "")
        bar.setDisplay(path: currentPath, title: currentTitle)
        if restoreFocus && panel.isKeyWindow {
            // Hand the keyboard back to Finder; the next update brings the bar back.
            panel.orderOut(nil)
            tracker.raiseWindow()
        }
    }

    private func commit() {
        guard let target = Paths.resolve(bar.field.stringValue, base: currentPath) else {
            bar.flash("找不到这个路径", error: true)
            return
        }
        if let error = FinderScript.go(to: target) {
            bar.flash(error, error: true)
            return
        }
        currentPath = target.isFolder ? target.path : (target.path as NSString).deletingLastPathComponent
        endEditing()
    }

    private func complete(in editor: NSTextView) {
        let text = editor.string
        switch Paths.complete(text, base: currentPath) {
        case .replaced(let s):
            editor.insertText(s, replacementRange: NSRange(location: 0, length: (text as NSString).length))
            editor.scrollRangeToVisible(editor.selectedRange())
        case .ambiguous(let names):
            let shown = names.prefix(4).joined(separator: "  ")
            bar.flash(names.count > 4 ? shown + "  …共 \(names.count) 项" : shown, error: false)
        case .none:
            NSSound.beep()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commit(); return true
        case #selector(NSResponder.cancelOperation(_:)): endEditing(); return true
        case #selector(NSResponder.insertTab(_:)): complete(in: textView); return true
        default: return false
        }
    }

    func controlTextDidChange(_ notification: Notification) { bar.clearFlash() }

    func windowDidResignKey(_ notification: Notification) { endEditing(restoreFocus: false) }

    @objc func editPath() { beginEditing() }

    @objc func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentPath ?? currentTitle, forType: .string)
    }

    // MARK: Dragging the bar moves the Finder window (the bar covers the toolbar's drag area)

    func beginWindowDrag() {
        guard let window else { return }
        dragging = true
        tracker.isDraggingWindow = true
        dragWindowOrigin = window.frame.origin
        dragPanelOrigin = panel.frame.origin
    }

    func dragWindow(by delta: CGSize) {
        guard dragging else { return }
        tracker.moveWindow(to: CGPoint(x: dragWindowOrigin.x + delta.width, y: dragWindowOrigin.y - delta.height))
        panel.setFrameOrigin(NSPoint(x: dragPanelOrigin.x + delta.width, y: dragPanelOrigin.y + delta.height))
    }

    func endWindowDrag() {
        dragging = false
        tracker.isDraggingWindow = false
    }
}
