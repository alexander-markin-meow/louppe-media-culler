import Foundation
import XCTest
@testable import Louppe

final class DuplicateBurstAnalysisTests: XCTestCase {
    @MainActor
    func testGroupedReviewCacheFollowsFiltersSensitivityAndFreshAnalysis() async throws {
        let store = SessionStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.items = [
            item(id: "A.JPG", captureDate: start),
            item(id: "B.JPG", captureDate: start.addingTimeInterval(1)),
            item(id: "C.PNG", captureDate: start.addingTimeInterval(5)),
        ]
        store.phase = .ready
        store.rebuildDerivedDataForTesting()
        store.setBurstGroupingInterval(2)
        store.enterGroupedReview(.captureBursts)
        try await waitForAnalysis(store)
        XCTAssertEqual(store.visibleIndices, [0, 1])

        store.setBurstGroupingInterval(10)
        XCTAssertEqual(store.visibleIndices, [0, 1, 2])
        store.filter.excludedTypes = ["PNG"]
        XCTAssertEqual(store.visibleIndices, [0, 1])
        XCTAssertEqual(store.visibleGroups.first?.title,
                       "Capture burst · 2 items · close capture times")
        store.filter.excludedTypes = []
        XCTAssertEqual(store.visibleIndices, [0, 1, 2])

        // A refreshed analysis must invalidate membership even when the user
        // keeps the same review mode and sensitivity selected.
        store.items = [
            item(id: "A.JPG", captureDate: start),
            item(id: "B.JPG", captureDate: start.addingTimeInterval(20)),
            item(id: "C.PNG", captureDate: start.addingTimeInterval(21)),
        ]
        store.rebuildDerivedDataForTesting()
        store.analyzeDuplicateAndBurstGroups()
        try await waitForAnalysis(store)
        XCTAssertEqual(store.visibleIndices, [1, 2])
        store.exitGroupedReview()
        XCTAssertEqual(store.visibleIndices, [0, 1, 2])
    }

    @MainActor
    private func waitForAnalysis(_ store: SessionStore) async throws {
        let deadline = Date().addingTimeInterval(5)
        while store.isDuplicateBurstAnalysisRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.duplicateBurstAnalysisState, .ready)
    }

    func testLargeNearMatchingFamiliesStayOneGroup() {
        let fingerprints = (0..<4_000).map { index in
            DuplicateBurstAnalysis.VisualFingerprint(
                itemID: String(format: "%05d", index),
                hash: index < 2_000 ? 0 : 1
            )
        }
        let result = DuplicateBurstAnalysis.Result(
            exactDuplicateItemSets: [], visualFingerprints: fingerprints,
            burstCandidates: [], analyzedExactFileCount: 0,
            analyzedVisualPhotoCount: fingerprints.count
        )
        let start = Date()
        let groups = result.groups(for: .likelySimilarPhotos, visualDistance: 1, burstInterval: 2)
        print("Large similar families: \(Date().timeIntervalSince(start)) seconds")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.itemIDs, fingerprints.map(\.itemID))
    }

    func testFilteredGroupTitleCountsOnlyVisibleMembers() {
        let items = [item(id: "A.JPG"), item(id: "B.JPG"), item(id: "C.PNG")]
        var index = PreparedSessionIndex()
        index.rebuildItems(items, sort: PhotoSort())
        var filter = PhotoFilter()
        filter.excludedTypes = ["PNG"]
        index.applyFilter(filter, to: items, sort: PhotoSort(), isGroupingEnabled: true)
        index.applyGroupedReview([
            .init(id: "group", mode: .exactDuplicates, itemIDs: items.map(\.id))
        ], to: items)
        XCTAssertEqual(index.visibleGroups.first?.indices, [0, 1])
        XCTAssertEqual(index.visibleGroups.first?.title,
                       "Exact duplicates · 2 items · matching file fingerprints")
    }

    func testExactDuplicateFilesMergeRAWJPEGProjectionIntoOneReviewGroup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouppeDuplicateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rawA = directory.appendingPathComponent("A.RAW")
        let rawB = directory.appendingPathComponent("B.RAW")
        let jpegA = directory.appendingPathComponent("A.JPG")
        let jpegB = directory.appendingPathComponent("B.JPG")
        try Data("same raw bytes".utf8).write(to: rawA)
        try Data("same raw bytes".utf8).write(to: rawB)
        try Data("same jpeg bytes".utf8).write(to: jpegA)
        try Data("same jpeg bytes".utf8).write(to: jpegB)

        let result = try DuplicateBurstAnalysis.analyze([
            input(
                id: "A.RAW",
                exactFiles: [rawA, jpegA].map {
                    DuplicateBurstAnalysis.ExactFile(
                        reviewItemID: "A.RAW",
                        url: $0,
                        fileSize: Int64((try? Data(contentsOf: $0).count) ?? 0)
                    )
                }
            ),
            input(
                id: "B.RAW",
                exactFiles: [rawB, jpegB].map {
                    DuplicateBurstAnalysis.ExactFile(
                        reviewItemID: "B.RAW",
                        url: $0,
                        fileSize: Int64((try? Data(contentsOf: $0).count) ?? 0)
                    )
                }
            ),
        ])

        let groups = result.groups(
            for: .exactDuplicates,
            visualDistance: 8,
            burstInterval: 2
        )
        XCTAssertEqual(groups.map(\.itemIDs), [["A.RAW", "B.RAW"]])
        XCTAssertEqual(
            groups.first?.title,
            "Exact duplicates · 2 items · matching file fingerprints"
        )
    }

    func testVisualSensitivityOnlyGroupsNearbyPerceptualHashes() {
        let result = DuplicateBurstAnalysis.Result(
            exactDuplicateItemSets: [],
            visualFingerprints: [
                .init(itemID: "A", hash: 0x1111_0000_0000_0000),
                .init(itemID: "B", hash: 0x1111_0000_0000_0003),
                .init(itemID: "C", hash: 0x2222_0000_0000_0000),
            ],
            burstCandidates: [],
            analyzedExactFileCount: 0,
            analyzedVisualPhotoCount: 3
        )

        XCTAssertTrue(result.groups(
            for: .likelySimilarPhotos,
            visualDistance: 1,
            burstInterval: 2
        ).isEmpty)
        XCTAssertEqual(
            result.groups(
                for: .likelySimilarPhotos,
                visualDistance: 2,
                burstInterval: 2
            ).map(\.itemIDs),
            [["A", "B"]]
        )
    }

    func testBurstGroupsUseConsecutiveCaptureTimeGap() {
        let start = Date(timeIntervalSince1970: 1_000)
        let result = DuplicateBurstAnalysis.Result(
            exactDuplicateItemSets: [],
            visualFingerprints: [],
            burstCandidates: [
                .init(itemID: "A", captureDate: start),
                .init(itemID: "B", captureDate: start.addingTimeInterval(1.8)),
                .init(itemID: "C", captureDate: start.addingTimeInterval(5)),
                .init(itemID: "D", captureDate: start.addingTimeInterval(6.9)),
            ],
            analyzedExactFileCount: 0,
            analyzedVisualPhotoCount: 0
        )

        XCTAssertEqual(
            result.groups(
                for: .captureBursts,
                visualDistance: 8,
                burstInterval: 2
            ).map(\.itemIDs),
            [["A", "B"], ["C", "D"]]
        )
        XCTAssertTrue(result.groups(
            for: .captureBursts,
            visualDistance: 8,
            burstInterval: 1
        ).isEmpty)
    }

    func testPreparedIndexKeepsOnlyFilteredGroupMembersAndRestoresNoDuplicates() {
        let items = [
            item(id: "A.JPG"),
            item(id: "B.JPG"),
            item(id: "C.PNG"),
        ]
        var index = PreparedSessionIndex()
        index.rebuildItems(items, sort: PhotoSort())
        var filter = PhotoFilter()
        filter.excludedTypes = ["PNG"]
        index.applyFilter(filter, to: items, sort: PhotoSort(), isGroupingEnabled: true)
        index.applyGroupedReview([
            .init(
                id: "exact-A",
                mode: .exactDuplicates,
                itemIDs: ["A.JPG", "C.PNG"]
            ),
            .init(
                id: "exact-overlap",
                mode: .exactDuplicates,
                itemIDs: ["A.JPG", "B.JPG"]
            ),
        ], to: items)

        XCTAssertEqual(index.visibleIndices, [0, 1])
        XCTAssertEqual(index.visibleGroups.count, 1)
        XCTAssertEqual(index.visibleGroups.first?.title, "Exact duplicates · 2 items · matching file fingerprints")
    }

    private func input(
        id: String,
        exactFiles: [DuplicateBurstAnalysis.ExactFile]
    ) -> DuplicateBurstAnalysis.Input {
        DuplicateBurstAnalysis.Input(
            id: id,
            mediaKind: .photo,
            captureDate: nil,
            exactFiles: exactFiles,
            visualFiles: []
        )
    }

    private func item(id: String, captureDate: Date? = nil) -> PhotoItem {
        PhotoItem(
            id: id,
            primaryURL: URL(fileURLWithPath: "/tmp/\(id)"),
            pairedURL: nil,
            captureDate: captureDate,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 1
        )
    }
}
