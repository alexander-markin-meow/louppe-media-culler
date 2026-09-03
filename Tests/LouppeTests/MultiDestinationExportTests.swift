import Foundation
import XCTest
@testable import Louppe

final class MultiDestinationExportTests: XCTestCase {
    func testMultiRouteCapacityAddsRoutesOnOneVolumeWithoutOverflow() {
        XCTAssertEqual(
            ExportDestinationValidator.combinedRequiredCapacity([80, 80]),
            160
        )
        XCTAssertEqual(
            ExportDestinationValidator.combinedRequiredCapacity([
                Int64.max - 4,
                10,
            ]),
            Int64.max
        )
    }

    func testEvaluationShowsOverlapAndNeverAddsUnmatchedItemsToARoute() {
        let routedTwice = item(
            "FIVE-YES.JPG",
            rating: .yes,
            stars: .five
        )
        let yesOnly = item("YES.JPG", rating: .yes)
        let unmatched = item("NO.JPG", rating: .no)
        let routes = [
            MultiDestinationExportRoute(predicate: .decision(.yes)),
            MultiDestinationExportRoute(predicate: .stars(.stars(.five))),
        ]

        let evaluation = MultiDestinationExportEvaluation.evaluate(
            routes: routes,
            items: [routedTwice, yesOnly, unmatched]
        )

        XCTAssertEqual(evaluation.overlappingItemIndices, [0])
        XCTAssertEqual(evaluation.routeMatches[0].itemIndices, [1])
        XCTAssertTrue(evaluation.routeMatches[1].itemIndices.isEmpty)
        XCTAssertEqual(evaluation.unmatchedItemIndices, [2])
        XCTAssertFalse(
            evaluation.routeMatches.contains {
                $0.itemIndices.contains(2)
            },
            "unmatched media must have no implicit fallback route"
        )
    }

    func testRoutingPlanCopiesPairTogetherToItsRouteAndLeavesUnmatchedSourceAlone() async throws {
        let fixture = try fixture(named: "PairAndUnmatched")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let raw = fixture.source.appendingPathComponent("KEEP.NEF")
        let jpeg = fixture.source.appendingPathComponent("KEEP.JPG")
        let rejected = fixture.source.appendingPathComponent("LEAVE.JPG")
        try Data("raw bytes".utf8).write(to: raw)
        try Data("jpeg bytes".utf8).write(to: jpeg)
        try Data("rejected bytes".utf8).write(to: rejected)
        let paired = item(
            "KEEP.NEF",
            url: raw,
            pairedURL: jpeg,
            rating: .yes,
            fileSize: 9
        )
        let leftBehind = item(
            "LEAVE.JPG",
            url: rejected,
            rating: .no,
            fileSize: 14
        )
        let routes = [
            MultiDestinationExportRoute(
                predicate: .decision(.yes),
                destination: fixture.firstDestination
            )
        ]

        let work = try await MultiDestinationExportPlanner.prepare(.init(
            routes: routes,
            items: [paired, leftBehind],
            sourceFolder: fixture.source,
            includeXMP: false,
            familyContextItems: [paired, leftBehind],
            sessionGeneration: 1,
            xmpProfile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        ))

        XCTAssertEqual(work.plan.routes.count, 1)
        XCTAssertEqual(work.plan.routes[0].itemCount, 1)
        XCTAssertEqual(work.plan.routes[0].mediaFileCount, 2)
        XCTAssertEqual(work.plan.unmatchedNames, ["LEAVE.JPG"])
        XCTAssertEqual(work.plan.workerPlan.totalFiles, 2)

        let result = ExportWorker.copy(
            work.selectedItems,
            to: fixture.firstDestination,
            preparedPlan: work.plan.workerPlan,
            journalDirectory: fixture.journals
        ) { _, _ in }

        XCTAssertEqual(result.copiedFiles, 2)
        XCTAssertEqual(result.failedPhotos, 0)
        XCTAssertFalse(result.requiresRecovery)
        XCTAssertEqual(
            try Data(contentsOf: fixture.firstDestination.appendingPathComponent("KEEP.NEF")),
            Data("raw bytes".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: fixture.firstDestination.appendingPathComponent("KEEP.JPG")),
            Data("jpeg bytes".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("LEAVE.JPG").path
        ))
        XCTAssertEqual(try Data(contentsOf: rejected), Data("rejected bytes".utf8))
        XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: fixture.journals))
    }

    func testRoutingPlanRejectsDuplicateDestinationAliases() async throws {
        let fixture = try fixture(named: "DuplicateDestination")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yes = fixture.source.appendingPathComponent("YES.JPG")
        let no = fixture.source.appendingPathComponent("NO.JPG")
        try Data("yes".utf8).write(to: yes)
        try Data("no".utf8).write(to: no)
        let items = [
            item("YES.JPG", url: yes, rating: .yes),
            item("NO.JPG", url: no, rating: .no),
        ]
        let routes = [
            MultiDestinationExportRoute(
                predicate: .decision(.yes),
                destination: fixture.firstDestination
            ),
            MultiDestinationExportRoute(
                predicate: .decision(.no),
                destination: fixture.firstDestination
            ),
        ]

        do {
            _ = try await MultiDestinationExportPlanner.prepare(.init(
                routes: routes,
                items: items,
                sourceFolder: fixture.source,
                includeXMP: false,
                familyContextItems: items,
                sessionGeneration: 1,
                xmpProfile: .universal,
                visibleDecisionKeywords: false,
                allowExternalLabelReplacement: false
            ))
            XCTFail("duplicate destinations must not produce a routing plan")
        } catch let error as ExportDestinationValidator.ValidationError {
            XCTAssertEqual(error, .duplicateMultiDestination)
        }
    }

    func testRoutingCopyCancellationRollsBackOnlyTheInProgressPair() async throws {
        let fixture = try fixture(named: "CancelledPair")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let raw = fixture.source.appendingPathComponent("PAIR.NEF")
        let jpeg = fixture.source.appendingPathComponent("PAIR.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)
        let paired = item(
            "PAIR.NEF",
            url: raw,
            pairedURL: jpeg,
            rating: .yes
        )
        let route = MultiDestinationExportRoute(
            predicate: .decision(.yes),
            destination: fixture.firstDestination
        )
        let work = try await MultiDestinationExportPlanner.prepare(.init(
            routes: [route],
            items: [paired],
            sourceFolder: fixture.source,
            includeXMP: false,
            familyContextItems: [paired],
            sessionGeneration: 1,
            xmpProfile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        ))
        let cancellation = ExportWorker.CancelFlag()
        let result = ExportWorker.copy(
            work.selectedItems,
            to: fixture.firstDestination,
            preparedPlan: work.plan.workerPlan,
            journalDirectory: fixture.journals,
            isCancelled: { cancellation.isSet },
            afterStagedFile: { _ in cancellation.set() }
        ) { _, _ in }

        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.copiedFiles, 0)
        XCTAssertEqual(result.failedPhotos, 0)
        XCTAssertFalse(result.requiresRecovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpeg.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("PAIR.NEF").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("PAIR.JPG").path
        ))
        XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: fixture.journals))
    }

    func testInterruptedMultiRouteCopyRecoveryPublishesVerifiedStagedFile() async throws {
        let fixture = try fixture(named: "InterruptedRecovery")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yes = fixture.source.appendingPathComponent("YES.JPG")
        let no = fixture.source.appendingPathComponent("NO.JPG")
        try Data("yes".utf8).write(to: yes)
        try Data("no".utf8).write(to: no)
        let items = [
            item("YES.JPG", url: yes, rating: .yes),
            item("NO.JPG", url: no, rating: .no),
        ]
        let work = try await MultiDestinationExportPlanner.prepare(.init(
            routes: [
                MultiDestinationExportRoute(
                    predicate: .decision(.yes),
                    destination: fixture.firstDestination
                ),
                MultiDestinationExportRoute(
                    predicate: .decision(.no),
                    destination: fixture.secondDestination
                ),
            ],
            items: items,
            sourceFolder: fixture.source,
            includeXMP: false,
            familyContextItems: items,
            sessionGeneration: 1,
            xmpProfile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        ))
        let plannedFiles = work.plan.workerPlan.items.flatMap { item in
            item.files.map { (item.itemID, $0) }
        }
        let writer = try FileOperationJournal.start(
            kind: .exportCopy,
            seeds: plannedFiles.map { itemID, file in
                FileOperationJournal.Seed(
                    itemID: itemID,
                    source: file.source,
                    destination: file.target,
                    expectedIdentity: file.scannedIdentity,
                    role: file.role,
                    expectedSourceDigest: file.expectedSourceDigest,
                    preparedContentDigest: nil
                )
            },
            directory: fixture.journals
        )
        let first = plannedFiles[0].1
        let temporary = try XCTUnwrap(writer.temporaryURL(at: 0))
        try writer.mark(.started, fileAt: 0)
        try FileManager.default.copyItem(at: first.source, to: temporary)
        let copiedIdentity = try FileOperationJournal.captureIdentity(at: temporary)
        try writer.mark(
            .staged,
            fileAt: 0,
            identityAt: temporary,
            expectedIdentity: copiedIdentity,
            includeStatusChange: false
        )
        // Deliberately leave the activated plan behind as a process crash
        // would. Releasing the lock without committing lets recovery inspect
        // the exact staged inode rather than guessing by filename.
        XCTAssertTrue(FileOperationJournal.finalize(
            writer,
            operationIsConsistent: false
        ))

        let recovery = FileOperationJournal.recoverPendingOperations(
            directory: fixture.journals
        )
        XCTAssertEqual(recovery.unresolvedOperations, 0)
        XCTAssertEqual(recovery.preservedCopies, 1)
        XCTAssertEqual(try Data(contentsOf: first.target), Data("yes".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plannedFiles[1].1.target.path))
        XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: fixture.journals))
    }

    func testRouteCopiesCompleteSameStemFamilyAndPreparedXMPSidecarTogether() async throws {
        let fixture = try fixture(named: "FamilyWithXMP")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let raw = fixture.source.appendingPathComponent("FAMILY.NEF")
        let jpeg = fixture.source.appendingPathComponent("FAMILY.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)
        let paired = item(
            "FAMILY.NEF",
            url: raw,
            pairedURL: jpeg,
            rating: .yes
        )
        let work = try await MultiDestinationExportPlanner.prepare(.init(
            routes: [MultiDestinationExportRoute(
                predicate: .decision(.yes),
                destination: fixture.firstDestination
            )],
            items: [paired],
            sourceFolder: fixture.source,
            includeXMP: true,
            familyContextItems: [paired],
            sessionGeneration: 1,
            xmpProfile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        ))

        XCTAssertNotNil(work.plan.xmpPlan)
        XCTAssertEqual(work.plan.routes[0].mediaFileCount, 2)
        XCTAssertEqual(
            work.plan.routes[0].files.filter {
                $0.role == .preparedXMP
            }.count,
            1
        )
        let result = ExportWorker.copy(
            work.selectedItems,
            to: fixture.firstDestination,
            xmpPlan: work.plan.xmpPlan,
            preparedPlan: work.plan.workerPlan,
            journalDirectory: fixture.journals
        ) { _, _ in }

        XCTAssertEqual(result.copiedFiles, 3)
        XCTAssertEqual(result.xmpSummary?.mediaFiles, 2)
        XCTAssertEqual(result.xmpSummary?.created, 1)
        XCTAssertFalse(result.requiresRecovery)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("FAMILY.NEF").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("FAMILY.JPG").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.firstDestination.appendingPathComponent("FAMILY.xmp").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpeg.path))
        XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: fixture.journals))
    }

    func testIncludingXMPSidecarsRejectsSplitSameStemFamilyAcrossRoutes() async throws {
        let fixture = try fixture(named: "SplitXMPFamily")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let raw = fixture.source.appendingPathComponent("SPLIT.NEF")
        let jpeg = fixture.source.appendingPathComponent("SPLIT.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)
        let rawItem = item("SPLIT.NEF", url: raw, rating: .yes)
        let jpegItem = item("SPLIT.JPG", url: jpeg, rating: .no)
        let items = [rawItem, jpegItem]
        let routes = [
            MultiDestinationExportRoute(
                predicate: .fileType("RAW"),
                destination: fixture.firstDestination
            ),
            MultiDestinationExportRoute(
                predicate: .fileType("JPEG"),
                destination: fixture.secondDestination
            ),
        ]

        do {
            _ = try await MultiDestinationExportPlanner.prepare(.init(
                routes: routes,
                items: items,
                sourceFolder: fixture.source,
                includeXMP: true,
                familyContextItems: items,
                sessionGeneration: 1,
                xmpProfile: .universal,
                visibleDecisionKeywords: false,
                allowExternalLabelReplacement: false
            ))
            XCTFail("a shared sidecar family must not be silently split")
        } catch let error as MultiDestinationExportPlanner.PlannerError {
            XCTAssertEqual(error, .splitXMPFamily)
        }
    }

    func testRouteLabelsAreExplicitForVoiceOverAndContainNoAnyFallback() {
        XCTAssertEqual(
            MultiDestinationRoutePredicate.decision(.yes).displayName,
            "Decision: Yes"
        )
        XCTAssertEqual(
            MultiDestinationRoutePredicate.stars(.stars(.five)).displayName,
            "Stars: 5 stars"
        )
        XCTAssertEqual(
            MultiDestinationRoutePredicate.mediaKind(.video).displayName,
            "Media type: Videos"
        )
    }

    private func fixture(named name: String) throws -> (
        root: URL,
        source: URL,
        firstDestination: URL,
        secondDestination: URL,
        journals: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LouppeMultiDestinationTests-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        let journals = root.appendingPathComponent("Journals", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        return (root, source, first, second, journals)
    }

    private func item(
        _ id: String,
        url: URL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-item.JPG"),
        pairedURL: URL? = nil,
        rating: Rating = .undecided,
        stars: StarRating? = nil,
        mediaKind: MediaKind = .photo,
        fileSize: Int64 = 1
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            primaryURL: url,
            pairedURL: pairedURL,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            mediaKind: mediaKind,
            fileSize: fileSize,
            pairedFileSize: pairedURL == nil ? 0 : fileSize,
            rating: rating,
            starRating: stars
        )
    }
}
