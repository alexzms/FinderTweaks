import AppKit

/// One Finder enhancement. To add one: create Features/<Name>/, conform to this protocol, and list it
/// in `AppDelegate.features`. Features that react to Finder windows observe the shared `FinderTracker`.
protocol Feature: AnyObject {
    /// Stable key; the on/off state is stored under "feature.<id>" in the app's defaults.
    var id: String { get }
    /// Menu bar title.
    var title: String { get }
    /// Toggleable features get a checkmark item in the menu; others only contribute `menuItems()`.
    var isToggleable: Bool { get }
    /// Whether the feature needs the window tracker running while enabled.
    var needsTracker: Bool { get }
    var isEnabled: Bool { get set }
    /// Extra items for the menu bar menu (rebuilt each time the menu opens).
    func menuItems() -> [NSMenuItem]
}

extension Feature {
    func menuItems() -> [NSMenuItem] { [] }
}
