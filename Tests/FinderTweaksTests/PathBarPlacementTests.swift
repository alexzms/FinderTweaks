import CoreGraphics
import Testing
@testable import FinderTweaks
@testable import FinderTweaksCore

struct PathBarPlacementTests {
    typealias C = ToolbarInfo.Control

    /// macOS 26 Finder with the search item right after the title: back/forward end at 284,
    /// the title starts at 288, the search field spans 536–837, share/action/tags follow.
    static let toolbar = ToolbarInfo(
        windowSize: CGSize(width: 982, height: 498),
        toolbar: CGRect(x: 0, y: 0, width: 982, height: 52),
        title: CGRect(x: 288, y: 0, width: 245, height: 52),
        controls: [
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 211, y: 8, width: 36, height: 36)),
            C(role: "AXButton", subrole: "AXSegment", frame: CGRect(x: 248, y: 8, width: 36, height: 36)),
            C(role: "AXTextField", subrole: "AXSearchField", frame: CGRect(x: 536, y: 7, width: 301, height: 38)),
            C(role: "AXButton", subrole: "", frame: CGRect(x: 849, y: 0, width: 41, height: 52)),
        ],
        isBrowser: true)

    func place(_ mode: PathBarPlacement.Mode, compact: Bool = true) throws -> PathBarPlacement {
        try #require(PathBarPlacement.compute(in: Self.toolbar, mode: mode, compactSearch: compact))
    }

    @Test func idleCoversSearchFieldAndEndsInSearchButton() throws {
        let p = try place(.idle)
        #expect(p.rect == CGRect(x: 290, y: 7, width: 547, height: 38))
        #expect(p.searchWidth == 110)
    }

    @Test func searchingStepsBackToTheTitle() throws {
        let p = try place(.searching)
        #expect(p.rect.minX == 290)
        #expect(p.rect.maxX == 530)
        #expect(p.searchWidth == 0)
    }

    @Test func modesShareTheTopLeftCorner() throws {
        // The bar animates between modes only when its top-left corner stays put.
        let corners = try [PathBarPlacement.Mode.idle, .searching].map { try place($0).rect.origin }
        #expect(Set(corners.map { "\($0)" }).count == 1)
    }

    @Test func withoutCompactSearchEveryModeKeepsToTheTitle() throws {
        for mode in [PathBarPlacement.Mode.idle, .searching] {
            let p = try place(mode, compact: false)
            #expect(p.rect.maxX == 530)
            #expect(p.searchWidth == 0)
        }
    }
}
