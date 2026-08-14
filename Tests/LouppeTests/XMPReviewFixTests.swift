import Foundation
import XCTest
@testable import Louppe

/// Regressions found reviewing the XMP interoperability branch: the sidecar
/// resolver's per-directory index, Move's reporting when only the old source
/// packet survives, a pair split across sidecar families, and the resolver
/// sheet's tolerance for a malformed conflict list.
final class XMPReviewFixTests: XCTestCase {
    /// The resolver indexes the whole listing once instead of rescanning it
    /// per family. Every family must still adopt exactly its own packet and
    /// never a same-directory neighbour's.
    func testEveryFamilyInOneDirectoryResolvesItsOwnExistingPacket() throws {
        let root = try temporaryDirectory("ResolverIndex")
        var members: [XMPStemFamilyMember] = []
        let familyCount = 24
        for index in 0..<familyCount {
            let stem = String(format: "IMG_%04d", index)
            let media = root.appendingPathComponent("\(stem).NEF")
            try Data("raw \(index)".utf8).write(to: media)
            try Data("packet \(index)".utf8).write(
                to: root.appendingPathComponent("\(stem).xmp")
            )
            members.append(try XMPStemFamilyMember(
                mediaURL: media,
                metadata: metadata()
            ))
        }
        // One neighbour also carries an application-private packet and a
        // heavy-edit companion, so the index's partitioning is exercised.
        try Data("darktable history".utf8).write(
            to: root.appendingPathComponent("IMG_0000.NEF.xmp")
        )
        try Data("heavy edits".utf8).write(
            to: root.appendingPathComponent("IMG_0000.acr")
        )

        let families = try XMPSidecarResolver.resolve(members: members)

        XCTAssertEqual(families.count, familyCount)
        for family in families {
            let stem = (family.members[0].mediaPath.url.lastPathComponent
                as NSString).deletingPathExtension
            XCTAssertEqual(family.disposition, .publish)
            XCTAssertEqual(
                family.canonicalSidecar?.url.lastPathComponent,
                "\(stem).xmp"
            )
            let expectedQualified = stem == "IMG_0000"
                ? ["IMG_0000.NEF.xmp"]
                : []
            XCTAssertEqual(
                family.extensionQualifiedSidecars.map(\.url.lastPathComponent),
                expectedQualified
            )
            XCTAssertEqual(
                family.excludedACRCompanions.map(\.url.lastPathComponent),
                stem == "IMG_0000" ? ["IMG_0000.acr"] : []
            )
        }
    }

    /// The media of this item reached the destination with durable completed
    /// checkpoints, so its ids must be reported even when the old source
    /// packet could not be retired. Withholding them would leave the session
    /// holding photos whose files are gone from the source folder.
    func testMoveReportsMovedPhotosWhenOnlySidecarRetirementFails() async throws {
        let root = try temporaryDirectory("RetirementFailure")
        let source = try directory("Source", in: root)
        let destination = try directory("Destination", in: root)
        let journals = root.appendingPathComponent("Journals")
        let media = source.appendingPathComponent("RETIRE.NEF")
        let sidecar = source.appendingPathComponent("RETIRE.xmp")
        try Data("raw".utf8).write(to: media)
        try packet(decision: .no, stars: .one, color: .yellow).write(to: sidecar)
        let selected = try item(media, stars: .four, color: .blue)
        let plan = try await XMPExportPlanner.prepare(
            selected: [selected],
            familyContextItems: [selected],
            profile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: source.path
            )
        }

        // The retirement rename and its quarantine both live beside the old
        // source packet, and the final progress callback lands after every
        // file has a completed checkpoint but before the cleanup runs.
        let result = ExportWorker.move(
            [selected],
            to: destination,
            xmpPlan: plan,
            journalDirectory: journals
        ) { done, total in
            guard done == total else { return }
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: source.path
            )
        }

        XCTAssertEqual(result.movedItemIDs, [selected.id])
        XCTAssertEqual(result.failedPhotos, 0)
        XCTAssertTrue(result.requiresRecovery)
        XCTAssertEqual(result.inconsistentPhotos, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("RETIRE.NEF").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("RETIRE.xmp").path
        ))
    }

    /// A pair matched across subfolders belongs to one sidecar family per
    /// directory, and one collision suffix cannot name a shared packet for
    /// two of them. Preflight must exclude both packets explicitly so the
    /// confirmed plan is exactly the plan the worker receives.
    func testPairSplitAcrossSubfoldersIsSkippedDuringPreflight() async throws {
        let root = try temporaryDirectory("SplitFamily")
        let rawFolder = try directory("RAW", in: root)
        let jpegFolder = try directory("JPEG", in: root)
        let destination = try directory("Destination", in: root)
        let raw = rawFolder.appendingPathComponent("SPLIT.NEF")
        let jpeg = jpegFolder.appendingPathComponent("SPLIT.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)
        let paired = PhotoItem(
            primaryFile: try file(raw, stars: .three, color: .green),
            pairedFile: try file(jpeg, stars: .three, color: .green)
        )
        let xmp = try await XMPExportPlanner.prepare(
            selected: [paired],
            familyContextItems: [paired],
            profile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        )
        XCTAssertEqual(xmp.families.count, 2)
        XCTAssertEqual(xmp.count(.crossFolderPair), 2)
        XCTAssertEqual(xmp.issueFamilies.count, 2)
        XCTAssertTrue(xmp.familyByMediaPath.isEmpty)

        let plan = try ExportWorker.makePlan(
            for: [paired],
            in: destination,
            xmpPlan: xmp,
            mode: .copy
        )

        XCTAssertEqual(plan.unplannedSidecarFamilyCount, 0)
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(
            plan.items[0].files.map(\.role),
            [.media, .media]
        )
    }

    /// Confirmation freezes destination names as well as XMP bytes. If a
    /// different process claims one of those names before Start, the worker
    /// must fail safely instead of silently executing a newly suffixed plan.
    func testPreparedCopyPlanIsThePlanExecutedAfterConfirmation() async throws {
        let root = try temporaryDirectory("ImmutableDestinationPlan")
        let source = try directory("Source", in: root)
        let destination = try directory("Destination", in: root)
        let journals = root.appendingPathComponent("Journals")
        let media = source.appendingPathComponent("FROZEN.NEF")
        try Data("original media".utf8).write(to: media)
        let selected = try item(media, stars: .four, color: .blue)
        let xmp = try await XMPExportPlanner.prepare(
            selected: [selected],
            familyContextItems: [selected],
            profile: .universal,
            visibleDecisionKeywords: false,
            allowExternalLabelReplacement: false
        )
        let preparedPlan = try ExportWorker.makePlan(
            for: [selected],
            in: destination,
            xmpPlan: xmp,
            mode: .copy
        )
        let mediaTarget = try XCTUnwrap(
            preparedPlan.items[0].files.first(where: { $0.role == .media })
        ).target
        let lateContents = Data("late external file".utf8)
        try lateContents.write(to: mediaTarget)

        let result = ExportWorker.copy(
            [selected],
            to: destination,
            xmpPlan: xmp,
            preparedPlan: preparedPlan,
            journalDirectory: journals
        ) { _, _ in }

        XCTAssertEqual(result.failedPhotos, 1)
        XCTAssertFalse(result.requiresRecovery)
        XCTAssertEqual(try Data(contentsOf: mediaTarget), lateContents)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted(),
            [mediaTarget.lastPathComponent]
        )
        XCTAssertEqual(try Data(contentsOf: media), Data("original media".utf8))
        XCTAssertFalse(
            FileOperationJournal.hasPendingOperations(directory: journals)
        )
    }

    /// A completed Move must leave the live session even when a later journal
    /// cleanup still needs attention. Recovery can remain nonmodal for review,
    /// so waiting for its rescan would leave a missing original on screen.
    @MainActor
    func testCompletedMoveLeavesSessionBeforeRecoveryFinishes() throws {
        let root = try temporaryDirectory("MoveRecoverySession")
        let journals = try directory("Journals", in: root)
        let firstURL = root.appendingPathComponent("FIRST.NEF")
        let secondURL = root.appendingPathComponent("SECOND.NEF")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let first = try item(firstURL)
        let second = try item(secondURL)
        let store = SessionStore(
            operationJournalDirectory: journals,
            automaticallyRecoversInterruptedOperations: false
        )
        store.items = [first, second]
        store.phase = .ready
        store.rebuildDerivedDataForTesting()

        XCTAssertTrue(store.exportWillStart(mode: .move))
        store.finishExport(
            mode: .move,
            movedIDs: [first.id],
            requiresRecovery: true,
            interruptionMessage: "Old XMP cleanup is still pending"
        )

        XCTAssertEqual(store.items.map(\.id), [second.id])
        XCTAssertEqual(store.currentItem?.id, second.id)
    }

    /// SessionStore's mutation boundary already rejects duplicate rows. The
    /// sheet that presents them must not trap before it can.
    @MainActor
    func testConflictResolverToleratesDuplicateConflictIdentifiers() async throws {
        let root = try temporaryDirectory("DuplicateRows")
        let raw = root.appendingPathComponent("DUP.NEF")
        let jpeg = root.appendingPathComponent("DUP.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)
        let rawItem = PhotoItem(
            primaryFile: try file(raw, decision: .yes, stars: .five, color: .green)
        )
        let jpegItem = PhotoItem(
            primaryFile: try file(jpeg, decision: .no, stars: .two, color: .red)
        )
        let input = try XMPPublicationInput(
            items: [rawItem],
            familyContextItems: [rawItem, jpegItem],
            sessionGeneration: 1,
            profile: .captureOne,
            visibleDecisionKeywords: true
        )
        let preflight = await XMPPublicationPlanner.preflight(
            input,
            isCancelled: { false },
            progress: { _, _ in }
        )
        let conflict = try XCTUnwrap(
            try XCTUnwrap(preflight).resolvableSameStemConflicts.first
        )

        var applied: [XMPConflictResolutionRequest] = []
        let view = XMPConflictResolverView(
            conflicts: [conflict, conflict],
            onCancel: {},
            onApply: { applied = $0 }
        )

        XCTAssertEqual(view.conflicts.count, 2)
        XCTAssertTrue(applied.isEmpty)
    }

    // MARK: - Helpers

    private func metadata() -> XMPPublicationMetadata {
        XMPPublicationMetadata(
            decision: .yes,
            stars: .three,
            colorLabel: .green,
            profile: .universal
        )
    }

    private func packet(
        decision: Rating,
        stars: StarRating?,
        color: PhotoColorLabel?
    ) throws -> Data {
        try XMPFieldMapping.merge(
            packet: nil,
            metadata: XMPPublicationMetadata(
                decision: decision,
                stars: stars,
                colorLabel: color,
                profile: .universal
            )
        )
    }

    private func file(
        _ url: URL,
        decision: Rating = .yes,
        stars: StarRating? = nil,
        color: PhotoColorLabel? = nil
    ) throws -> PhotoFile {
        PhotoFile(
            id: url.lastPathComponent,
            url: url,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            fileSize: Int64((try? Data(contentsOf: url).count) ?? 0),
            scannedIdentity: try FileOperationJournal.captureIdentity(at: url),
            rating: decision,
            starRating: stars,
            colorLabel: color
        )
    }

    private func item(
        _ url: URL,
        decision: Rating = .yes,
        stars: StarRating? = nil,
        color: PhotoColorLabel? = nil
    ) throws -> PhotoItem {
        PhotoItem(primaryFile: try file(
            url,
            decision: decision,
            stars: stars,
            color: color
        ))
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "louppe-xmp-review-\(name)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func directory(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }
}
