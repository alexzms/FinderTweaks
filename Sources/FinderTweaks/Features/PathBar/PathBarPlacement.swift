import AppKit
import FinderTweaksCore

/// Where the bar sits, relative to the window's top-left (AX coordinates): over the title, spanning
/// from the back/forward buttons to the first toolbar item after the title.
///
/// Compact search: when Finder's search field sits right after the title, the bar also covers it and
/// ends in a short search button of its own; Finder's field is uncovered again while it is in use.
///
/// Live-tunable, no rebuild needed, e.g.:
///   defaults write io.github.alexzms.FinderTweaks pathBar.insetLeft -float 10
/// Keys: pathBar.insetLeft / insetRight (6), height (0 = match toolbar), offsetY (0), minWidth (120),
///       searchWidth (110), pathBar.placement = "above" (float above the window instead).
struct PathBarPlacement: Equatable {
    var rect: CGRect
    /// Width of the compact search button at the right end; 0 when there is none.
    var searchWidth: CGFloat

    static let searchGap: CGFloat = 8

    private static func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
        guard let n = UserDefaults.standard.object(forKey: "pathBar." + key) as? NSNumber else { return fallback }
        return CGFloat(n.doubleValue)
    }

    static func compute(in toolbar: ToolbarInfo, coverSearch: Bool) -> PathBarPlacement? {
        let customHeight = number("height", 0)
        var h = customHeight > 0 ? customHeight : min(40, max(22, toolbar.typicalControlHeight ?? 28))
        if UserDefaults.standard.string(forKey: "pathBar.placement") == "above" {
            return PathBarPlacement(rect: CGRect(x: 12, y: -h - 6, width: toolbar.windowSize.width - 24, height: h),
                                    searchWidth: 0)
        }
        guard let span = toolbar.titleSpan() else { return nil }
        let minWidth = number("minWidth", 120)
        let x0 = span.minX + number("insetLeft", 6)
        var x1 = span.maxX - number("insetRight", 6)
        var searchWidth: CGFloat = 0
        if coverSearch, let search = toolbar.expandedSearchField, abs(search.minX - span.maxX) < 1 {
            let wanted = number("searchWidth", 110)
            if search.maxX - x0 - wanted - searchGap >= minWidth {
                x1 = search.maxX
                searchWidth = wanted
                h = max(h, search.height)  // fully hide Finder's field underneath
            }
        }
        guard x1 - x0 >= minWidth else { return nil }
        let rect = CGRect(x: x0, y: (span.midY - h / 2 + number("offsetY", 0)).rounded(), width: x1 - x0, height: h)
        return PathBarPlacement(rect: rect, searchWidth: searchWidth)
    }
}
