import AppKit
import ApplicationServices
import FinderTweaksCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let tracker = FinderTracker()
    private(set) lazy var features: [Feature] = [
        PathBarFeature(tracker: tracker),
        FinderSettingsFeature(),
    ]
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launched \(Bundle.main.bundlePath)")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "FinderTweaks")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        for feature in features where feature.isToggleable {
            feature.isEnabled = UserDefaults.standard.object(forKey: "feature.\(feature.id)") as? Bool ?? true
        }
        tracker.onTrustChanged = { granted in if granted { Self.requestAutomation() } }
        if AXIsProcessTrusted() {
            Self.requestAutomation()
        } else {
            Self.promptForAccessibility()
        }
        updateTracker()
    }

    private func updateTracker() {
        if features.contains(where: { $0.isEnabled && $0.needsTracker }) { tracker.start() } else { tracker.stop() }
    }

    static func promptForAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// Asks up front for permission to drive Finder, so the prompt doesn't interrupt the first use.
    static func requestAutomation() {
        DispatchQueue.global().async {
            Log.write("automation allowed=\(FinderScript.automationAllowed(ask: true))")
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "FinderTweaks", nil)
        if AXIsProcessTrusted() {
            add(menu, "✓ 正在运行", nil)
        } else {
            add(menu, "⚠︎ 需要“辅助功能”权限，点此打开设置…", #selector(openAccessibilitySettings))
        }
        menu.addItem(.separator())
        for feature in features {
            if feature.isToggleable {
                let item = add(menu, feature.title, #selector(toggleFeature(_:)))
                item.representedObject = feature
                item.state = feature.isEnabled ? .on : .off
            }
            feature.menuItems().forEach(menu.addItem)
        }
        menu.addItem(.separator())
        add(menu, "登录时自动启动", #selector(toggleLoginItem)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, "打开诊断日志", #selector(openLog))
        menu.addItem(.separator())
        add(menu, "退出 FinderTweaks", #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        guard let feature = sender.representedObject as? Feature else { return }
        feature.isEnabled.toggle()
        UserDefaults.standard.set(feature.isEnabled, forKey: "feature.\(feature.id)")
        Log.write("feature \(feature.id) enabled=\(feature.isEnabled)")
        updateTracker()
    }

    @objc private func openAccessibilitySettings() {
        Self.promptForAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.write("login item error: \(error)")
            let alert = NSAlert()
            alert.messageText = "无法设置登录时启动"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
}
