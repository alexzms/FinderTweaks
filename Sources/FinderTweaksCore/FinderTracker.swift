import AppKit
import ApplicationServices

/// A snapshot of the focused Finder browser window.
public struct FinderWindow {
    public let element: AXUIElement
    public let pid: pid_t
    /// AX global coordinates (origin top-left of the primary screen, y down).
    public let frame: CGRect
    public let title: String
    /// The folder on display, when it is a real folder (not Recents, AirDrop, a search, …).
    public let path: String?
    /// False while the window is being moved or resized, and for 150 ms after.
    public let isSettled: Bool
    /// Toolbar layout; nil until the window has settled after a resize.
    public let toolbar: ToolbarInfo?
    /// Finder's search field has keyboard focus.
    public let searchFocused: Bool
    /// What is typed in Finder's search field.
    public let searchQuery: String

    public var isSearching: Bool { searchFocused || !searchQuery.isEmpty }
}

public enum FinderState {
    /// No Accessibility permission, or Finder isn't the frontmost app.
    case inactive
    /// Finder is frontmost but no browser window has focus (desktop, dialogs, …).
    case noWindow
    case window(FinderWindow)
}

/// Watches the focused Finder window and hands each new reading to observers. Features build on this
/// instead of talking to Accessibility themselves.
///
/// Event-driven, so it costs next to nothing while nothing happens: Accessibility notifications from
/// Finder (focus, title, move/resize, search text) and app switches trigger a re-read. While the mouse
/// button is down — the window may be dragged or resized, which Finder doesn't report live — it polls
/// at 30 Hz. A 1 s heartbeat catches anything missed and re-reads the toolbar every 2 s.
public final class FinderTracker {
    public private(set) var trusted = AXIsProcessTrusted()
    public var onTrustChanged: ((Bool) -> Void)?
    /// Set while a feature moves the window itself, so its own drag doesn't count as "unsettled".
    public var isDraggingWindow = false

    private var observers: [(FinderState) -> Void] = []
    private var heartbeat: Timer?
    private var burst: Timer?
    private var burstUntil: TimeInterval = 0
    private var refreshQueued = false
    private var settleCheck: DispatchWorkItem?
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private var app: AXUIElement?
    private var appPid: pid_t = 0
    private var axObserver: AXObserver?
    private var observedWindow: AXUIElement?
    private var observedSearch: AXUIElement?

    private var window: AXUIElement?
    private var windowFrame = CGRect.zero
    private var toolbar: ToolbarInfo?
    private var searchField: AXUIElement?
    private var wasSearching = false
    private var toolbarAt: TimeInterval = 0
    private var changedAt: TimeInterval = 0
    private var lastSummary = ""
    private var lastPathSource = ""
    private var fallbackTitle: String?
    private var fallbackPath: String?

    static let appNotifications = [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
                                   kAXWindowCreatedNotification]
    static let windowNotifications = [kAXWindowMovedNotification, kAXWindowResizedNotification,
                                      kAXTitleChangedNotification, kAXUIElementDestroyedNotification,
                                      kAXWindowMiniaturizedNotification]
    static let searchNotifications = [kAXValueChangedNotification]

    public init() {}

    public func observe(_ handler: @escaping (FinderState) -> Void) {
        observers.append(handler)
    }

    public var isRunning: Bool { heartbeat != nil }

    public func start() {
        guard heartbeat == nil else { return }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        let t = Timer(timeInterval: 1, target: self, selector: #selector(beat), userInfo: nil, repeats: true)
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshSoon() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in self?.mouseActivity(event)
        }
        Log.write("tracker started")
        refreshSoon()
    }

    public func stop() {
        guard let heartbeat else { return }
        heartbeat.invalidate()
        self.heartbeat = nil
        burst?.invalidate()
        burst = nil
        settleCheck?.cancel()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        activationObserver = nil
        mouseMonitor = nil
        detachObserver()
        publish(.inactive)
        Log.write("tracker stopped")
    }

    /// Re-read on the next run loop pass; repeated calls coalesce into one read.
    public func refreshSoon() {
        guard heartbeat != nil, !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshQueued = false
            self?.refresh()
        }
    }

    /// Gives the focused Finder window key focus again (e.g. after typing in a panel of ours).
    public func raiseWindow() {
        if let window { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
    }

    /// Moves the focused Finder window; `origin` is in AX coordinates.
    public func moveWindow(to origin: CGPoint) {
        if let window { AX.setPosition(window, origin) }
    }

    /// Puts the cursor in Finder's search field, falling back to sending ⌘F to Finder.
    public func focusSearchField() {
        defer { refreshSoon() }
        if let searchField,
           AXUIElementSetAttributeValue(searchField, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            return
        }
        Log.write("search field focus via AX failed; sending ⌘F")
        sendKey(3 /* F */, flags: .maskCommand)
    }

    /// If Finder's search field still has the cursor but nothing typed, press Esc in it so Finder
    /// leaves search. Called after the user turned to the path bar instead.
    public func dismissEmptySearch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let field = self.searchField else { return }
            let s = AX.multi(field, [kAXFocusedAttribute, kAXValueAttribute])
            guard (s[0] as? Bool) == true, ((s[1] as? String) ?? "").isEmpty else { return }
            self.sendKey(53 /* Esc */, flags: [])
            self.refreshSoon()
        }
    }

    private func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown)
            event?.flags = flags
            event?.postToPid(appPid)
        }
    }

    // MARK: Triggers

    @objc private func beat() {
        let t = AXIsProcessTrusted()
        if t != trusted {
            trusted = t
            Log.write("accessibility trusted=\(t)")
            onTrustChanged?(t)
        }
        refresh()
    }

    private func mouseActivity(_ event: NSEvent) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleID else { return }
        startBurst(for: event.type == .leftMouseUp ? 0.4 : 0.3)
    }

    /// Poll at 30 Hz for a while — Finder doesn't report a window drag or resize as it happens.
    private func startBurst(for seconds: TimeInterval) {
        burstUntil = max(burstUntil, ProcessInfo.processInfo.systemUptime + seconds)
        guard burst == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(burstTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        burst = t
    }

    @objc private func burstTick() {
        refresh()
        if ProcessInfo.processInfo.systemUptime > burstUntil {
            burst?.invalidate()
            burst = nil
        }
    }

    // MARK: Accessibility notifications

    private func attachObserver(pid: pid_t, app: AXUIElement) {
        detachObserver()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<FinderTracker>.fromOpaque(refcon).takeUnretainedValue().refreshSoon()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else {
            Log.write("AXObserverCreate failed")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func detachObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        observedWindow = nil
        observedSearch = nil
    }

    /// Re-points per-element notifications when the focused window or its search field changes.
    private func watch(_ element: AXUIElement?, current: inout AXUIElement?, names: [String]) {
        guard let observer = axObserver else { return }
        if let old = current, let element, CFEqual(old, element) { return }
        if let old = current {
            for name in names { AXObserverRemoveNotification(observer, old, name as CFString) }
        }
        current = element
        if let element {
            for name in names {
                AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }

    // MARK: Reading Finder

    private func refresh() {
        guard heartbeat != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard trusted, let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == finderBundleID else { publish(.inactive); return }

        if app == nil || appPid != front.processIdentifier {
            appPid = front.processIdentifier
            let element = AXUIElementCreateApplication(appPid)
            app = element
            window = nil
            attachObserver(pid: appPid, app: element)
        }
        guard let app, let win = AX.element(AX.copy(app, kAXFocusedWindowAttribute)) else { publish(.noWindow); return }
        let v = AX.multi(win, [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                               kAXTitleAttribute, kAXDocumentAttribute, kAXMinimizedAttribute])
        guard v[0] as? String == kAXWindowRole, v[1] as? String == kAXStandardWindowSubrole,
              (v[6] as? Bool) != true, let frame = AX.rect(v[2], v[3]) else { publish(.noWindow); return }
        let title = (v[4] as? String) ?? ""
        let path = folderPath(title: title, document: v[5] as? String)
        watch(win, current: &observedWindow, names: Self.windowNotifications)

        if isDraggingWindow {
            windowFrame = frame
        } else {
            if window == nil || !CFEqual(window!, win) {
                window = win
                toolbar = nil
                searchField = nil
                changedAt = now
            }
            if frame != windowFrame {
                if frame.size != windowFrame.size { toolbar = nil; searchField = nil }
                windowFrame = frame
                changedAt = now
            }
        }
        let settled = isDraggingWindow || now - changedAt > 0.15
        if !settled { scheduleSettleCheck(after: changedAt + 0.16 - now) }
        // Re-read the toolbar when the window changes, and every 2 s in case it was customized.
        if settled && (toolbar == nil || now - toolbarAt > 2) {
            toolbarAt = now
            let result = ToolbarProbe.probe(window: win, frame: frame, title: title, hasPath: path != nil)
            if result.info.summary != lastSummary {
                lastSummary = result.info.summary
                Log.write("toolbar " + result.info.summary)
            }
            toolbar = result.info
            searchField = result.searchField
            watch(searchField, current: &observedSearch, names: Self.searchNotifications)
        }
        var focused = false
        var query = ""
        if let searchField {
            let s = AX.multi(searchField, [kAXFocusedAttribute, kAXValueAttribute])
            focused = (s[0] as? Bool) == true
            query = (s[1] as? String) ?? ""
        }
        let searching = focused || !query.isEmpty
        if searching != wasSearching {
            wasSearching = searching
            Log.write("searching=\(searching)")
        }
        publish(.window(FinderWindow(element: win, pid: appPid, frame: frame, title: title, path: path,
                                     isSettled: settled, toolbar: toolbar, searchFocused: focused,
                                     searchQuery: query)))
    }

    private func scheduleSettleCheck(after delay: TimeInterval) {
        settleCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        settleCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: work)
    }

    private func folderPath(title: String, document: String?) -> String? {
        let path: String?
        let source: String
        if let document, let url = URL(string: document), url.isFileURL {
            path = (url as NSURL).filePathURL?.path ?? url.path
            source = "document"
        } else if title.hasPrefix("/") {
            path = title  // Finder's _FXShowPosixPathInTitle puts the full path in the title
            source = "title"
        } else {
            if title != fallbackTitle {
                fallbackTitle = title
                fallbackPath = FinderScript.frontFolderPath()
            }
            path = fallbackPath
            source = path == nil ? "none" : "applescript"
        }
        if source != lastPathSource {
            lastPathSource = source
            Log.write("path source=\(source)")
        }
        return path
    }

    private func publish(_ state: FinderState) {
        for observer in observers { observer(state) }
    }
}
