import Foundation
import XCTest
@testable import Louppe

final class FolderHierarchyTests: XCTestCase {
    func testNaturalDepthFirstOrderKeepsParentsBeforeChildren() {
        let expected = [
            "ROOT.JPG", "Day 2/parent.JPG", "Day 2/Part 2/a.JPG",
            "Day 2/Part 10/b.JPG", "Day 2-extra/sibling.JPG",
            "Day 10/parent.JPG", "Day 10/Part 2/c.JPG",
        ]
        let items = expected.reversed().map { makeItem($0) }
        let sort = PhotoSort(key: .folderHierarchy)
        let index = prepared(items, sort: sort)
        XCTAssertEqual(index.visibleIndices.map { items[$0].id }, expected)
        XCTAssertEqual(items.sorted(by: sort.areInOrder).map(\.id), expected)
        XCTAssertEqual(index.visibleGroups.compactMap(\.title), [
            "Source folder", "Day 2", "Day 2/Part 2", "Day 2/Part 10",
            "Day 2-extra", "Day 10", "Day 10/Part 2",
        ])
    }

    func testReverseChangesSiblingOrderButKeepsParentFirstAndFilesChronological() {
        let expected = [
            "ROOT.JPG", "Day 10/z.JPG", "Day 10/a.JPG",
            "Day 10/Part 2/c.JPG", "Day 2-extra/sibling.JPG",
            "Day 2/parent.JPG", "Day 2/Part 10/b.JPG", "Day 2/Part 2/a.JPG",
        ]
        let items = expected.reversed().map {
            makeItem($0, captureDate: $0 == "Day 10/z.JPG" ? Date(timeIntervalSince1970: 1) : nil)
        }
        let sort = PhotoSort(key: .folderHierarchy, ascending: false)
        let index = prepared(items, sort: sort)
        XCTAssertEqual(index.visibleIndices.map { items[$0].id }, expected)
        XCTAssertEqual(items.sorted(by: sort.areInOrder).map(\.id), expected)
        for (position, itemIndex) in index.visibleIndices.enumerated() {
            XCTAssertEqual(index.location(forItemIndex: itemIndex)?.position, position)
        }
    }

    func testFilteringPreservesFullPathGroupIDsAndRebuildsLocations() throws {
        let items = [
            makeItem("ROOT.JPG"), makeItem("Trip/first.JPG"),
            makeItem("Trip/second.PNG"), makeItem("Trip/Raw/deep.PNG"),
            makeItem("Other/Raw/other.PNG"),
        ]
        let sort = PhotoSort(key: .folderHierarchy)
        var index = prepared(items, sort: sort)
        let originalGroups = Dictionary(uniqueKeysWithValues: index.visibleGroups.map {
            ($0.title!, $0.id)
        })
        var filter = PhotoFilter()
        filter.excludedTypes = ["JPEG"]
        index.applyFilter(filter, to: items, sort: sort, isGroupingEnabled: true)
        XCTAssertEqual(index.visibleGroups.compactMap(\.title), ["Other/Raw", "Trip", "Trip/Raw"])
        XCTAssertEqual(index.visibleGroups.map(\.id), [
            originalGroups["Other/Raw"]!, originalGroups["Trip"]!, originalGroups["Trip/Raw"]!,
        ])
        XCTAssertNil(index.location(forItemIndex: 0))
        XCTAssertNil(index.location(forItemIndex: 1))
        XCTAssertEqual(index.visibleGroupTitles, [4: "Other/Raw", 2: "Trip", 3: "Trip/Raw"])
        XCTAssertEqual(index.location(forItemIndex: 2), .init(position: 1, groupIndex: 1, positionInGroup: 0))
        XCTAssertEqual(index.visibleEntries.map(\.id), ["Other/Raw/other.PNG", "Trip/second.PNG", "Trip/Raw/deep.PNG"])
    }

    func testRootAndLiteralRootLabelsRemainDistinctGroups() {
        let items = [makeItem("ROOT.JPG"), makeItem("Source folder/a.JPG"), makeItem("None/a.JPG")]
        let index = prepared(items)
        XCTAssertEqual(index.visibleGroups.count, 3)
        XCTAssertEqual(Set(index.visibleGroups.map(\.id)).count, 3)
        XCTAssertFalse(PhotoSort.Key.folderHierarchy.sameGroup(items[0], items[1]))
        XCTAssertFalse(PhotoSort.Key.folderHierarchy.sameGroup(items[0], items[2]))
    }

    func testByteDistinctUnicodeFoldersNeverMergeOrInterleave() {
        let items = [
            makeItem("caf%C3%A9/z.JPG", displayPath: "caf\u{00E9}/z.JPG"),
            makeItem("cafe%CC%81/a.JPG", displayPath: "cafe\u{0301}/a.JPG"),
            makeItem("caf%C3%A9/a.JPG", displayPath: "caf\u{00E9}/a.JPG"),
            makeItem("cafe%CC%81/z.JPG", displayPath: "cafe\u{0301}/z.JPG"),
        ]
        XCTAssertEqual(items[0].subfolder, items[1].subfolder, "Swift display-string equality normalizes Unicode")
        for ascending in [true, false] {
            let sort = PhotoSort(key: .folderHierarchy, ascending: ascending)
            let index = prepared(items, sort: sort)
            XCTAssertEqual(index.visibleGroups.count, 2)
            XCTAssertEqual(Set(index.visibleGroups.map(\.id)).count, 2)
            XCTAssertTrue(index.visibleGroups.allSatisfy { $0.indices.count == 2 })
            XCTAssertEqual(index.visibleIndices.map { items[$0].id }, items.sorted(by: sort.areInOrder).map(\.id))
            XCTAssertEqual(
                items.sorted(by: sort.areInOrder).map(\.id),
                items.reversed().sorted(by: sort.areInOrder).map(\.id)
            )
        }
    }

    func testNaturalComparisonTiesStayDeterministicAndFoldersStayContiguous() {
        let items = [
            "Day 02/z.JPG", "Day 2/a.JPG", "Day 02/a.JPG", "Day 2/z.JPG",
            "day 2/Child/nested.JPG", "Day 2/Child/nested.JPG",
        ].map { makeItem($0) }
        for ascending in [true, false] {
            let sort = PhotoSort(key: .folderHierarchy, ascending: ascending)
            let index = prepared(items, sort: sort)
            let reverseIndex = prepared(Array(items.reversed()), sort: sort)
            XCTAssertEqual(Set(index.visibleGroups.map(\.id)).count, index.visibleGroups.count)
            XCTAssertEqual(
                index.visibleEntries.map(\.id), reverseIndex.visibleEntries.map(\.id)
            )
            XCTAssertEqual(index.visibleEntries.map(\.id), items.sorted(by: sort.areInOrder).map(\.id))
        }
    }

    func testGroupingCanBeHiddenWithoutChangingHierarchyOrder() {
        let items = [makeItem("B/a.JPG"), makeItem("A/B/a.JPG"), makeItem("A/a.JPG"), makeItem("root.JPG")]
        let sort = PhotoSort(key: .folderHierarchy)
        var index = prepared(items, sort: sort)
        let expected = index.visibleIndices
        index.rebuildGroups(for: items, sort: sort, isGroupingEnabled: false)
        XCTAssertEqual(index.visibleIndices, expected)
        XCTAssertEqual(index.visibleGroups.map(\.id), [.ungrouped])
        XCTAssertNil(index.visibleGroups.first?.title)
        XCTAssertTrue(index.visibleGroupTitles.isEmpty)
        XCTAssertEqual(index.visibleLocations.count, items.count)
    }

    func testEmptyAndRootOnlySessionsRemainValid() {
        let empty = prepared([])
        XCTAssertTrue(empty.visibleIndices.isEmpty)
        XCTAssertTrue(empty.visibleGroups.isEmpty)
        let rootOnly = prepared([makeItem("10.JPG"), makeItem("2.JPG")])
        XCTAssertEqual(rootOnly.visibleEntries.map(\.id), ["2.JPG", "10.JPG"])
        XCTAssertEqual(rootOnly.visibleGroups.compactMap(\.title), ["Source folder"])
    }

    @MainActor
    func testSessionNavigationSelectionAndFilteringUseExistingAuthority() {
        let store = SessionStore()
        store.items = [makeItem("B/1.JPG"), makeItem("A/Sub/1.JPG"), makeItem("A/1.PNG"), makeItem("root.JPG")]
        store.sort = PhotoSort(key: .folderHierarchy)
        store.phase = .ready
        store.setIndex(3)
        store.goNext()
        XCTAssertEqual(store.currentItem?.id, "A/1.PNG")
        store.selectRange(to: 0)
        XCTAssertEqual(store.selectedIndices, [0, 1, 2])
        store.sort.ascending = false
        XCTAssertEqual(store.selectedIndices, [0, 1, 2])
        XCTAssertEqual(store.visibleIndices, [3, 0, 2, 1])
        store.filter.excludedTypes = ["JPEG"]
        XCTAssertEqual(store.visibleIndices, [2])
        XCTAssertEqual(store.selectedIndices, [2])
        XCTAssertEqual(store.currentItem?.id, "A/1.PNG")
    }

    func testRealScannedRelativePathsAndPairsFollowHierarchyWithoutChangingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LouppeHierarchy-\(UUID())")
        let filenames = ["ROOT.txt", "Day 2/parent.txt", "Day 2/Sub/paired.NEF", "Day 2/Sub/paired.JPG", "Day 10/last.txt"]
        defer { try? FileManager.default.removeItem(at: root) }
        for filename in filenames {
            let url = root.appendingPathComponent(filename)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(filename.utf8).write(to: url)
        }
        let items = try FolderScanner.scan(root, pairingMode: .together) { _ in }
        let index = prepared(items)
        XCTAssertEqual(index.visibleGroups.compactMap(\.title), ["Source folder", "Day 2", "Day 2/Sub", "Day 10"])
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.filter { $0.pairedURL != nil }.count, 1)
        for filename in filenames {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(filename)), Data(filename.utf8))
        }
    }

    func testLargeSessionRanksRepeatedFoldersAndRetainsEveryLocation() {
        let items = (0..<10_000).map { index in
            makeItem("Day \(index % 25)/Part \(index % 3)/Photo \(index).JPG")
        }
        let start = Date.timeIntervalSinceReferenceDate
        let index = prepared(items)
        print("10k folder hierarchy sort + groups: \(Date.timeIntervalSinceReferenceDate - start)s")
        XCTAssertEqual(index.visibleGroups.count, 75)
        XCTAssertEqual(Set(index.visibleIndices).count, items.count)
        XCTAssertEqual(index.visibleLocations.count, items.count)
        for (position, itemIndex) in index.visibleIndices.enumerated() {
            XCTAssertEqual(index.location(forItemIndex: itemIndex)?.position, position)
        }
    }

    private func prepared(_ items: [PhotoItem], sort: PhotoSort = .init(key: .folderHierarchy)) -> PreparedSessionIndex {
        var index = PreparedSessionIndex()
        index.rebuildItems(items, sort: sort)
        index.applyFilter(PhotoFilter(), to: items, sort: sort, isGroupingEnabled: true)
        return index
    }

    private func makeItem(_ id: String, displayPath: String? = nil, captureDate: Date? = nil) -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(displayPath ?? id)"),
            displayRelativePath: displayPath,
            captureDate: captureDate,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 1
        ))
    }
}
