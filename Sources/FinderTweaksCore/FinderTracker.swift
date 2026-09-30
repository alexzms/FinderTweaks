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
}

public enum FinderState {
    /// No Accessibility permission, or Finder isn't the frontmost app.
    case inactive
    /// Finder is frontmost but no browser window has focus (desktop, dialogs, …).
    case noWindow
    case window(FinderWindow)
}

/// Polls the focused Finder window 30×/s while Finder is frontmost and hands each result to observers.
/// Features build on this instead of talking to Accessibility themselves.
public final class FinderTracker {
    public private(set) var trusted = AXIsProcessTrusted()
    public var onTrustChanged: ((Bool) -> Void)?
    /// Set while a feature moves the window itself, so its own drag doesn't count as "unsettled".
    public var isDraggingWindow = false

    private var observers: [(FinderState) -> Void] = []
    private var timer: Timer?
    private var app: AXUIElement?
    private var appPid: pid_t = 0
    private var window: AXUIElement?
    private var windowFrame = CGRect.zero
    private var toolbar: ToolbarInfo?
    private var toolbarAt: TimeInterval = 0
    private var changedAt: TimeInterval = 0
    private var trustCheckedAt: TimeInterval = 0
    private var lastSummary = ""
    private var lastPathSource = ""
    private var fallbackTitle: String?
    private var fallbackPath: String?

    public init() {}

    public func observe(_ handler: @escaping (FinderState) -> Void) {
        observers.append(handler)
    }

    public func start() {
        guard timer == nil else { return }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.write("tracker started")
    }

    public func stop() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        publish(.inactive)
        Log.write("tracker stopped")
    }

    /// Gives the focused Finder window key focus again (e.g. after typing in a panel of ours).
    public func raiseWindow() {
        if let window { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
    }

    /// Moves the focused Finder window; `origin` is in AX coordinates.
    public func moveWindow(to origin: CGPoint) {
        if let window { AX.setPosition(window, origin) }
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - trustCheckedAt > 1 {
            trustCheckedAt = now
            let t = AXIsProcessTrusted()
            if t != trusted {
                trusted = t
                Log.write("accessibility trusted=\(t)")
                onTrustChanged?(t)
            }
        }
        guard trusted, let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == finderBundleID else { publish(.inactive); return }

        if app == nil || appPid != front.processIdentifier {
            appPid = front.processIdentifier
            app = AXUIElementCreateApplication(appPid)
            window = nil
        }
        guard let app, let win = AX.element(AX.copy(app, kAXFocusedWindowAttribute)) else { publish(.noWindow); return }
        let v = AX.multi(win, [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                               kAXTitleAttribute, kAXDocumentAttribute, kAXMinimizedAttribute])
        guard v[0] as? String == kAXWindowRole, v[1] as? String == kAXStandardWindowSubrole,
              (v[6] as? Bool) != true, let frame = AX.rect(v[2], v[3]) else { publish(.noWindow); return }
        let title = (v[4] as? String) ?? ""
        let path = folderPath(title: title, document: v[5] as? String)

        if isDraggingWindow {
            windowFrame = frame
        } else {
            if window == nil || !CFEqual(window!, win) {
                window = win
                toolbar = nil
                changedAt = now
            }
            if frame != windowFrame {
                if frame.size != windowFrame.size { toolbar = nil }
                windowFrame = frame
                changedAt = now
            }
        }
        let settled = isDraggingWindow || now - changedAt > 0.15
        // Re-read the toolbar when the window changes, and every 2 s in case it was customized.
        if settled && (toolbar == nil || now - toolbarAt > 2) {
            toolbarAt = now
            let info = ToolbarProbe.probe(window: win, frame: frame, title: title, hasPath: path != nil)
            if info.summary != lastSummary {
                lastSummary = info.summary
                Log.write("toolbar " + info.summary)
            }
            toolbar = info
        }
        publish(.window(FinderWindow(element: win, pid: appPid, frame: frame, title: title, path: path,
                                     isSettled: settled, toolbar: toolbar)))
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
