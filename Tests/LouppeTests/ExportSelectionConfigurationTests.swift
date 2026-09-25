import Foundation
import XCTest
@testable import Louppe

final class ExportSelectionConfigurationTests: XCTestCase {
    func testExplicitSelectionStartsWithEverySelectedDecisionAndMetadata() {
        let items = [
            item("YES.JPG", decision: .yes, stars: .one),
            item("NO.JPG", decision: .no, stars: .four, color: .red),
            item("UNDECIDED.JPG", decision: .undecided, stars: .five, color: .purple),
            item("UNRATED.JPG", decision: .yes),
            item("OUTSIDE.JPG", decision: .yes),
        ]
        let configuration = ExportSelectionConfiguration.initial(
            hasExplicitSelection: true,
            keepersOnly: false
        )

        XCTAssertEqual(configuration.scope, .selected)
        XCTAssertEqual(
            configuration.snapshot(
                items: items,
                filtered: [0],
                selected: [0, 1, 2, 3]
            ).itemIndices,
            [0, 1, 2, 3]
        )
    }

    func testFourFiveStarsIncludesUndecidedAndOtherDecisions() {
        let items = [
            item("UNDECIDED.JPG", decision: .undecided, stars: .five),
            item("YES.JPG", decision: .yes, stars: .four),
            item("NO.JPG", decision: .no, stars: .five),
            item("THREE.JPG", decision: .yes, stars: .three),
        ]
        let configuration = ExportSelectionConfiguration.preset(.fourFiveStars)

        XCTAssertEqual(configuration.scope, .filtered)
        XCTAssertEqual(
            configuration.snapshot(
                items: items,
                filtered: [0, 1, 2, 3],
                selected: []
            ).itemIndices,
            [0, 1, 2]
        )
    }

    func testKeepersCompletionOverridesSelectionAndCurrentFilter() {
        let items = [
            item("HIDDEN_KEEPER.JPG", decision: .yes),
            item("VISIBLE_KEEPER.JPG", decision: .yes, stars: .two),
            item("SELECTED_NO.JPG", decision: .no, stars: .five),
        ]
        let configuration = ExportSelectionConfiguration.initial(
            hasExplicitSelection: true,
            keepersOnly: true
        )

        XCTAssertEqual(configuration.scope, .all)
        XCTAssertEqual(
            configuration.snapshot(
                items: items,
                filtered: [1, 2],
                selected: [2]
            ).itemIndices,
            [0, 1]
        )
    }

    func testOrdinaryExportWithoutSelectionStartsWithFilteredKeepers() {
        let items = [
            item("VISIBLE_KEEPER.JPG", decision: .yes),
            item("HIDDEN_KEEPER.JPG", decision: .yes),
            item("VISIBLE_NO.JPG", decision: .no),
        ]
        let configuration = ExportSelectionConfiguration.initial(
            hasExplicitSelection: false,
            keepersOnly: false
        )

        XCTAssertEqual(configuration.scope, .filtered)
        XCTAssertEqual(
            configuration.snapshot(
                items: items,
                filtered: [0, 2],
                selected: []
            ).itemIndices,
            [0]
        )
    }

    private func item(
        _ id: String,
        decision: Rating,
        stars: StarRating? = nil,
        color: PhotoColorLabel? = nil
    ) -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 1,
            rating: decision,
            starRating: stars,
            colorLabel: color
        ))
    }
}
