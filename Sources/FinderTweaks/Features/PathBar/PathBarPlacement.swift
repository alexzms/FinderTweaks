import AppKit
import FinderTweaksCore

/// Where the bar sits, relative to the window's top-left (AX coordinates): over the title, spanning
/// from the back/forward buttons to the first toolbar item after the title.
///
/// Live-tunable, no rebuild needed, e.g.:
///   defaults write io.github.alexzms.FinderTweaks pathBar.insetLeft -float 10
/// Keys: pathBar.insetLeft / insetRight (6), height (0 = match toolbar), offsetY (0), minWidth (120),
///       pathBar.placement = "above" (float above the window instead).
enum PathBarPlacement {
    private static func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
        guard let n = UserDefaults.standard.object(forKey: "pathBar." + key) as? NSNumber else { return fallback }
        return CGFloat(n.doubleValue)
    }

    static func rect(in toolbar: ToolbarInfo) -> CGRect? {
        let customHeight = number("height", 0)
        let h = customHeight > 0 ? customHeight : min(34, max(22, toolbar.typicalControlHeight ?? 28))
        if UserDefaults.standard.string(forKey: "pathBar.placement") == "above" {
            return CGRect(x: 12, y: -h - 6, width: toolbar.windowSize.width - 24, height: h)
        }
        guard let span = toolbar.titleSpan() else { return nil }
        let x0 = span.minX + number("insetLeft", 6)
        let x1 = span.maxX - number("insetRight", 6)
        guard x1 - x0 >= number("minWidth", 120) else { return nil }
        return CGRect(x: x0, y: (span.midY - h / 2 + number("offsetY", 0)).rounded(), width: x1 - x0, height: h)
    }
}
