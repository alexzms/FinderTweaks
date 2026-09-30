import CoreGraphics
import Testing
@testable import FinderTweaksCore

struct ToolbarInfoTests {
    typealias C = ToolbarInfo.Control

    /// A real macOS 26 Finder window, as recorded in the diagnostics log: back/forward at 211–284,
    /// the title from 288, then view switcher, group, share, tags, action, search.
    static let tahoe = ToolbarInfo(
        windowSize: CGSize(width: 982, height: 436),
        toolbar: CGRect(x: 0, y: 0, width: 982, height: 52),
        title: CGRect(x: 288, y: 0, width: 285, height: 52),
        controls: [
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 211, y: 8, width: 36, height: 36)),
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 248, y: 8, width: 36, height: 36)),
            C(role: "AXRadioGroup", subrole: "", frame: CGRect(x: 576, y: 7, width: 150, height: 38)),
            C(role: "AXRadioButton", subrole: "AXSegment", frame: CGRect(x: 577, y: 8, width: 37, height: 36)),
            C(role: "AXMenuButton", subrole: "", frame: CGRect(x: 737, y: 0, width: 58, height: 52)),
            C(role: "AXButton", subrole: "", frame: CGRect(x: 803, y: 0, width: 41, height: 52)),
            C(role: "AXButton", subrole: "AXSearchField", frame: CGRect(x: 936, y: 7, width: 38, height: 38)),
            C(role: "AXButton", subrole: "AXCloseButton", frame: CGRect(x: 18, y: 18, width: 16, height: 16)),
            C(role: "AXButton", subrole: "AXMinimizeButton", frame: CGRect(x: 41, y: 18, width: 16, height: 16)),
        ],
        isBrowser: true)

    @Test func titleSpanRunsFromBackForwardToNextItem() throws {
        let span = try #require(Self.tahoe.titleSpan())
        #expect(span.minX == 284)
        #expect(span.maxX == 576)
        #expect(span.midY == 26)
    }

    /// The same window after the view switcher and group-by buttons were dragged out: Finder handed the
    /// freed room to the search field (collapsed button → 293 pt field), and the title shrank to 245.
    static let tahoeWithoutViewButtons = ToolbarInfo(
        windowSize: CGSize(width: 982, height: 498),
        toolbar: CGRect(x: 0, y: 0, width: 982, height: 52),
        title: CGRect(x: 288, y: 0, width: 245, height: 52),
        controls: [
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 211, y: 8, width: 36, height: 36)),
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 248, y: 8, width: 36, height: 36)),
            C(role: "AXButton", subrole: "", frame: CGRect(x: 549, y: 0, width: 41, height: 52)),
            C(role: "AXMenuButton", subrole: "", frame: CGRect(x: 590, y: 0, width: 37, height: 52)),
            C(role: "AXButton", subrole: "", frame: CGRect(x: 627, y: 0, width: 43, height: 52)),
            C(role: "AXTextField", subrole: "AXSearchField", frame: CGRect(x: 673, y: 7, width: 293, height: 38)),
        ],
        isBrowser: true)

    @Test func titleSpanEndsAtShareButtonWhenSearchFieldExpands() throws {
        let span = try #require(Self.tahoeWithoutViewButtons.titleSpan())
        #expect(span.minX == 284)
        #expect(span.maxX == 549)
    }

    @Test func withoutTitleUsesWidestGap() throws {
        var info = Self.tahoe
        info.title = nil
        let span = try #require(info.titleSpan())
        #expect(span.minX == 284)
        #expect(span.maxX == 576)
    }

    @Test func controlHeightPrefersSearchField() {
        #expect(Self.tahoe.typicalControlHeight == 38)
    }
}
