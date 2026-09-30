import AppKit

public let finderBundleID = "com.apple.finder"

/// Drives Finder through AppleScript (needs the "Automation → Finder" permission).
public enum FinderScript {
    @discardableResult
    public static func run(_ source: String) -> (result: String?, error: String?) {
        var info: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&info)
        if let info {
            let code = (info["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
            Log.write("applescript error \(code)")
            if code == -1743 { return (nil, "没有控制“访达”的权限：系统设置 › 隐私与安全性 › 自动化") }
            let message = (info["NSAppleScriptErrorBriefMessage"] as? String) ?? (info["NSAppleScriptErrorMessage"] as? String)
            return (nil, message ?? "访达返回错误 \(code)")
        }
        return (out?.stringValue, nil)
    }

    static func literal(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Points the front Finder window at a folder, or at a file's folder with the file selected.
    /// Returns an error message, or nil on success.
    public static func go(to target: Paths.Target) -> String? {
        if target.isFolder {
            return run("""
            set theFolder to (POSIX file \(literal(target.path))) as alias
            tell application "Finder" to set target of front Finder window to theFolder
            """).error
        }
        let parent = (target.path as NSString).deletingLastPathComponent
        return run("""
        set theFolder to (POSIX file \(literal(parent))) as alias
        set theItem to (POSIX file \(literal(target.path))) as alias
        tell application "Finder"
            set target of front Finder window to theFolder
            select theItem
        end tell
        """).error
    }

    /// Fallback for windows that expose neither a document URL nor a POSIX title.
    public static func frontFolderPath() -> String? {
        guard automationAllowed(ask: false) else { return nil }
        let script = #"tell application "Finder" to return POSIX path of (target of front Finder window as alias)"#
        guard var path = run(script).result else { return nil }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Checks (and with `ask`, requests) permission to send Apple Events to Finder. Blocks while the
    /// system prompt is up, so call it off the main thread when asking.
    public static func automationAllowed(ask: Bool) -> Bool {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: finderBundleID).aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) == 0
    }
}

/// Finder's own preferences (com.apple.finder). Finder only picks up changes after a restart.
public enum FinderPreferences {
    static let domain = finderBundleID as CFString

    public static func bool(_ key: String) -> Bool {
        switch CFPreferencesCopyAppValue(key as CFString, domain) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["yes", "true", "1"].contains(s.lowercased())
        default: return false
        }
    }

    public static func string(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain) as? String
    }

    public static func set(_ key: String, _ value: Bool) {
        CFPreferencesSetAppValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("finder pref \(key)=\(value)")
    }

    public static func set(_ key: String, _ value: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFString, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("finder pref \(key)=\(value)")
    }

    /// Same as `killall Finder`: Finder relaunches right away and reopens its windows.
    public static func restartFinder() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run()
    }
}
