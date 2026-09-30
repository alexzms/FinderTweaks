import AppKit
import FinderTweaksCore

/// A "Finder 设置" submenu for Finder's hidden and not-so-hidden preferences.
/// To add one, append to `options`; the key is a com.apple.finder boolean.
final class FinderSettingsFeature: NSObject, Feature {
    let id = "finderSettings"
    let title = "Finder 设置"
    let isToggleable = false
    let needsTracker = false
    var isEnabled = true

    struct Option {
        let key: String
        let title: String
    }

    static let options = [
        Option(key: "_FXShowPosixPathInTitle", title: "窗口标题显示完整路径"),
        Option(key: "AppleShowAllFiles", title: "显示隐藏文件"),
        Option(key: "ShowPathbar", title: "窗口底部显示路径栏"),
        Option(key: "ShowStatusBar", title: "窗口底部显示状态栏"),
        Option(key: "_FXSortFoldersFirst", title: "排序时文件夹排在前面"),
    ]

    /// FXPreferredViewStyle values, in ⌘1…⌘4 order. Folders with their own saved view keep it.
    static let viewStyles = [("icnv", "图标"), ("Nlsv", "列表"), ("clmv", "分栏"), ("glyv", "画廊")]

    func menuItems() -> [NSMenuItem] {
        let submenu = NSMenu()
        let viewMenu = NSMenu()
        let currentStyle = FinderPreferences.string("FXPreferredViewStyle") ?? "icnv"
        for (index, (code, name)) in Self.viewStyles.enumerated() {
            let item = NSMenuItem(title: "\(name)（⌘\(index + 1)）", action: #selector(setViewStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == currentStyle ? .on : .off
            viewMenu.addItem(item)
        }
        let viewItem = NSMenuItem(title: "新窗口默认视图", action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        submenu.addItem(viewItem)
        submenu.addItem(.separator())
        for (index, option) in Self.options.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = FinderPreferences.bool(option.key) ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let restart = NSMenuItem(title: "重启访达", action: #selector(restartFinder), keyEquivalent: "")
        restart.target = self
        submenu.addItem(restart)

        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return [parent]
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        let option = Self.options[sender.tag]
        FinderPreferences.set(option.key, !FinderPreferences.bool(option.key))
        offerRestart()
    }

    @objc private func setViewStyle(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        FinderPreferences.set("FXPreferredViewStyle", code)
        offerRestart()
    }

    private func offerRestart() {
        let alert = NSAlert()
        alert.messageText = "重启访达后生效"
        alert.informativeText = "重启会关闭并重新打开访达窗口，正在进行的拷贝会被中断。"
        alert.addButton(withTitle: "现在重启")
        alert.addButton(withTitle: "稍后")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { FinderPreferences.restartFinder() }
    }

    @objc private func restartFinder() { FinderPreferences.restartFinder() }
}
