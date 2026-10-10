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

    /// Cover Finder's search field with the bar plus a short search button (see PathBarPlacement).
    var compactSearch: Bool {
        get { UserDefaults.standard.object(forKey: "pathBar.compactSearch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pathBar.compactSearch") }
    }

    /// What is on screen: the panel frame (Cocoa coordinates), the room kept at the right end for the
    /// search button, and the button's opacity. Mode switches animate between two of these.
    private struct Layout: Equatable {
        var frame: NSRect
        var reserve: CGFloat
        var buttonAlpha: CGFloat

        init(frame: NSRect, reserve: CGFloat, buttonAlpha: CGFloat) {
            self.frame = frame
            self.reserve = reserve
            self.buttonAlpha = buttonAlpha
        }

        init(_ p: PathBarPlacement, in window: CGRect) {
            frame = Geometry.cocoa(p.rect.offsetBy(dx: window.minX, dy: window.minY))
            reserve = p.searchWidth > 0 ? p.searchWidth + PathBarPlacement.searchGap : 0
            buttonAlpha = p.searchWidth > 0 ? 1 : 0
        }

        static func blend(_ a: Layout, _ b: Layout, _ t: CGFloat) -> Layout {
            func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
            return Layout(frame: NSRect(x: mix(a.frame.minX, b.frame.minX), y: mix(a.frame.minY, b.frame.minY),
                                        width: mix(a.frame.width, b.frame.width),
                                        height: mix(a.frame.height, b.frame.height)),
                          reserve: mix(a.reserve, b.reserve), buttonAlpha: mix(a.buttonAlpha, b.buttonAlpha))
        }
    }

    static let animationDuration: TimeInterval = 0.18

    private var shown: Layout?
    private var animation: (from: Layout, to: Layout, start: TimeInterval)?
    private var animationTimer: Timer?
    private var loggedPlacement: PathBarPlacement?

    private var window: FinderWindow?
    private var currentPath: String?
    private var currentTitle = ""
    private var editing = false
    private var dismissSearchAfterEdit = false
    /// Until then only a typed query counts as searching (Finder is being asked to leave search).
    private var ignoreSearchFocusUntil: TimeInterval = 0
    private var dragging = false
    private var dragWindowOrigin = CGPoint.zero
    private var dragPanelOrigin = NSPoint.zero

    init(tracker: FinderTracker) {
        self.tracker = tracker
        super.init()
        let container = NSView()
        container.wantsLayer = true
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
        tracker.refreshSoon()
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
        ignoreSearchFocusUntil = 0
        if editing {
            dismissSearchAfterEdit = false
            endEditing()
        }
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
            let searching = !w.searchQuery.isEmpty
                || (w.searchFocused && ProcessInfo.processInfo.systemUptime > ignoreSearchFocusUntil)
            guard w.isSettled, let toolbar = w.toolbar, toolbar.isBrowser,
                  let p = PathBarPlacement.compute(in: toolbar, mode: searching ? .searching : .idle,
                                                   compactSearch: compactSearch)
            else { hide(); return }
            log(p)
            let rect = p.rect.offsetBy(dx: w.frame.minX, dy: w.frame.minY)
            guard !Occlusion.check(rect, window: w.frame, finderPid: w.pid) else { hide(); return }
            present(Layout(p, in: w.frame))
        }
    }

    private func log(_ p: PathBarPlacement) {
        guard p != loggedPlacement else { return }
        loggedPlacement = p
        let r = p.rect
        Log.write("pathBar at \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)) search=\(Int(p.searchWidth))")
    }

    private func setContent(path: String?, title: String) {
        guard path != currentPath || title != currentTitle else { return }
        currentPath = path
        currentTitle = title
        if !editing { bar.setDisplay(path: path, title: title) }
    }

    // MARK: Showing, animating, hiding

    /// Switching between idle, searching and editing keeps the bar's top-left corner in place and
    /// animates the width. Anything else — first appearance, the window moved — snaps.
    private func present(_ target: Layout) {
        if let animation, animation.to == target { return }
        guard panel.isVisible, let current = shown,
              abs(current.frame.minX - target.frame.minX) < 1, abs(current.frame.maxY - target.frame.maxY) < 1 else {
            stopAnimation()
            apply(target)
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        guard current != target else { return }
        animation = (current, target, ProcessInfo.processInfo.systemUptime)
        if animationTimer == nil {
            let t = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(stepAnimation), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            animationTimer = t
        }
    }

    @objc private func stepAnimation() {
        guard let a = animation else { stopAnimation(); return }
        let t = min(1, CGFloat((ProcessInfo.processInfo.systemUptime - a.start) / Self.animationDuration))
        let eased = t * t * (3 - 2 * t)
        apply(t >= 1 ? a.to : Layout.blend(a.from, a.to, eased))
        if t >= 1 {
            stopAnimation()
            if editing { scrollEditorToCaret() }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animation = nil
    }

    /// Path capsule on the left; the search button pinned to the right end, faded in or out.
    private func apply(_ l: Layout) {
        shown = l
        if panel.frame != l.frame { panel.setFrame(l.frame, display: false) }
        let w = l.frame.width, h = l.frame.height
        let buttonWidth = PathBarPlacement.searchButtonWidth
        bar.frame = NSRect(x: 0, y: 0, width: max(0, w - l.reserve), height: h)
        searchButton.frame = NSRect(x: w - buttonWidth, y: 0, width: buttonWidth, height: h)
        searchButton.alphaValue = l.buttonAlpha
        searchButton.isHidden = l.buttonAlpha < 0.01
        for view in [bar, searchButton] as [NSView] {
            view.needsLayout = true
            view.needsDisplay = true
        }
        panel.displayIfNeeded()
    }

    private func hide() {
        endEditing(restoreFocus: false)
        stopAnimation()
        bar.hovered = false
        if panel.isVisible { panel.orderOut(nil) }
    }

    // MARK: Editing

    func beginEditing() {
        guard !editing, panel.isVisible else { return }
        editing = true
        // Clicked the path while Finder's search had the cursor but nothing typed: treat it as giving up
        // on the search, so the bar doesn't snap back to the narrow searching width afterwards.
        dismissSearchAfterEdit = compactSearch && window.map { $0.searchFocused && $0.searchQuery.isEmpty } ?? false
        bar.setEditing(true, text: currentPath.map(Paths.abbreviate) ?? "")
        // Typing a path always gets the wide idle layout (search button included), even if Finder's
        // search had squeezed the bar.
        if let w = window, let toolbar = w.toolbar,
           let p = PathBarPlacement.compute(in: toolbar, mode: .idle, compactSearch: compactSearch) {
            present(Layout(p, in: w.frame))
        }
        panel.makeKey()
        panel.makeFirstResponder(bar.field)
        if let editor = bar.field.currentEditor() as? NSTextView {
            editor.selectAll(nil)
            scrollEditorToCaret()
        }
    }

    private func scrollEditorToCaret() {
        guard let editor = bar.field.currentEditor() as? NSTextView else { return }
        let length = (editor.string as NSString).length
        let selection = editor.selectedRange()
        // With everything selected, show the end of the path — that's the part that matters.
        let target = selection.length == length ? NSRange(location: length, length: 0) : selection
        editor.scrollRangeToVisible(target)
    }

    func endEditing(restoreFocus: Bool = true) {
        guard editing else { return }
        editing = false
        bar.field.abortEditing()
        bar.setEditing(false, text: "")
        bar.setDisplay(path: currentPath, title: currentTitle)
        if restoreFocus && panel.isKeyWindow {
            // Hand the keyboard back to Finder. Showing the panel again right away keeps it on screen,
            // so the next update animates it to the idle or searching width.
            panel.orderOut(nil)
            tracker.raiseWindow()
            panel.orderFrontRegardless()
            if dismissSearchAfterEdit {
                ignoreSearchFocusUntil = ProcessInfo.processInfo.systemUptime + 0.5
                tracker.dismissEmptySearch()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in self?.tracker.refreshSoon() }
            }
        }
        dismissSearchAfterEdit = false
        tracker.refreshSoon()
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
        stopAnimation()
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
        tracker.refreshSoon()
    }
}
