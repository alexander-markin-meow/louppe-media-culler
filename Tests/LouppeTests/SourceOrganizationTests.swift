import Foundation
import XCTest
@testable import Louppe

final class SourceOrganizationTests: XCTestCase {
    func testDateTakenOnlyPresetEnablesNoOtherFolderLevel() {
        let preset = SourceOrganizationConfiguration.dateTakenOnly

        XCTAssertEqual(
            preset.enabledLevels.map(\.kind),
            [.dateTaken]
        )
        XCTAssertEqual(preset.dateGranularity, .day)
        XCTAssertEqual(preset.containerName, "Organized")
    }

    func testExFATSafetySelectsScopedFoundationRenameFallback() {
        let exFAT = SourceOrganizationStorageSafety(
            fileSystemName: "exfat"
        )
        let apfs = SourceOrganizationStorageSafety(
            fileSystemName: "apfs"
        )

        XCTAssertEqual(exFAT.noOverwriteRenameStrategy, .foundation)
        XCTAssertEqual(apfs.noOverwriteRenameStrategy, .exclusivePOSIX)
        XCTAssertEqual(exFAT.directorySyncPolicy, .allowUnsupported)
        XCTAssertEqual(apfs.directorySyncPolicy, .required)
    }

    func testCancelledPlanStopsBeforeFilesystemPlanning() throws {
        let fixture = try makeFixture(named: "Cancelled")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try SourceOrganizationPlanner.makePlan(
                sourceFolder: fixture.photos,
                selectedItems: [],
                familyContextItems: [],
                configuration: configuration(levels: [.decision]),
                knownOriginFolderPathBytesByFileID: [:],
                isCancelled: { true }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    @MainActor
    func testSessionStoreRescanKeepsOrganizationUndoAndRestoresLayout() async throws {
        let fixture = try makeFixture(named: "SessionRoundTrip")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceDirectory = try directory("Trips", under: fixture.photos)
        let source = sourceDirectory.appendingPathComponent("A.png")
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try png.write(to: source)
        let backup = fixture.root.appendingPathComponent(
            "Backup",
            isDirectory: true
        )
        let store = SessionStore(
            persistence: SessionPersistence(backupDirectory: backup),
            saveTrailingDelay: 0.01,
            saveMaximumDelay: 0.02,
            operationJournalDirectory: fixture.journals
        )
        store.openFolder(fixture.photos)
        try await waitUntil {
            if case .ready = store.phase { return store.items.count == 1 }
            return false
        }
        store.rate(.yes, at: 0)
        let snapshot = try XCTUnwrap(
            store.sourceOrganizationPlanningSnapshot(scope: .all)
        )
        let organizedPlan = try SourceOrganizationPlanner.makePlan(
            sourceFolder: snapshot.sourceFolder,
            selectedItems: snapshot.selectedItems,
            familyContextItems: snapshot.familyContextItems,
            configuration: configuration(levels: [.decision]),
            knownOriginFolderPathBytesByFileID:
                snapshot.knownOriginFolderPathBytesByFileID
        )
        let destination = fixture.photos.appendingPathComponent(
            "Organized/Yes/A.png"
        )

        store.startSourceOrganization(organizedPlan)
        try await waitUntil {
            if case .ready = store.phase {
                return !store.isFileOperationRunning
                    && FileManager.default.fileExists(atPath: destination.path)
            }
            return false
        }
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(
            store.items.first?.primaryURL.resolvingSymlinksInPath().path,
            destination.resolvingSymlinksInPath().path
        )
        let repeatedSnapshot = try XCTUnwrap(
            store.sourceOrganizationPlanningSnapshot(scope: .all)
        )
        let repeatedPlan = try SourceOrganizationPlanner.makePlan(
            sourceFolder: repeatedSnapshot.sourceFolder,
            selectedItems: repeatedSnapshot.selectedItems,
            familyContextItems: repeatedSnapshot.familyContextItems,
            configuration: configuration(levels: [.decision]),
            knownOriginFolderPathBytesByFileID:
                repeatedSnapshot.knownOriginFolderPathBytesByFileID
        )
        XCTAssertTrue(repeatedPlan.collisions.isEmpty)
        XCTAssertEqual(repeatedPlan.alreadyOrganizedItemCount, 1)

        store.undo()
        XCTAssertTrue(store.isOrganizePresented)
        try await waitUntil {
            if case .ready = store.phase {
                return !store.isFileOperationRunning
                    && FileManager.default.fileExists(atPath: source.path)
            }
            return false
        }
        XCTAssertEqual(
            store.items.first?.primaryURL.resolvingSymlinksInPath().path,
            source.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(try Data(contentsOf: source), png)
    }

    func testPriorityOrderControlsNestedFolderOrder() throws {
        let fixture = try makeFixture(named: "Priority")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceDirectory = try directory("Trips", under: fixture.photos)
        let source = try mediaFile("A.JPG", under: sourceDirectory)
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 8, day: 17)
            )
        )
        let item = makeItem(
            id: "Trips/A.JPG",
            url: source,
            captureDate: date,
            rating: .yes
        )

        let decisionThenDate = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.decision, .dateTaken]
        )
        let dateThenDecision = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.dateTaken, .decision]
        )
        let dateFolder = SourceOrganizationPlanner.dateFolderLabel(
            date,
            granularity: .day
        )

        XCTAssertEqual(
            decisionThenDate.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent(
                "Organized/Yes/\(dateFolder)/A.JPG"
            ).path
        )
        XCTAssertEqual(
            dateThenDecision.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent(
                "Organized/\(dateFolder)/Yes/A.JPG"
            ).path
        )
    }

    func testExistingFolderCanBeFlattenedOrPreservedAtTwoDepths() throws {
        let fixture = try makeFixture(named: "ExistingFolder")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let trip = try directory("Trips/Italy", under: fixture.photos)
        let source = try mediaFile("A.JPG", under: trip)
        let item = makeItem(
            id: "Trips/Italy/A.JPG",
            url: source,
            rating: .yes
        )

        let flattened = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.decision]
        )
        let topLevel = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.existingFolder, .decision],
            existingDepth: .topLevel
        )
        let fullPath = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.existingFolder, .decision],
            existingDepth: .fullPath
        )

        XCTAssertEqual(
            flattened.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent("Organized/Yes/A.JPG").path
        )
        XCTAssertEqual(
            topLevel.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent(
                "Organized/Trips/Yes/A.JPG"
            ).path
        )
        XCTAssertEqual(
            fullPath.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent(
                "Organized/Trips/Italy/Yes/A.JPG"
            ).path
        )
    }

    func testRememberedOriginPreventsRepeatedOrganizationFromNesting() throws {
        let fixture = try makeFixture(named: "RememberedOrigin")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let currentDirectory = try directory(
            "Organized/Yes/2026/",
            under: fixture.photos
        )
        let source = try mediaFile("A.JPG", under: currentDirectory)
        let item = makeItem(
            id: "Organized/Yes/2026/A.JPG",
            url: source,
            rating: .yes
        )
        let configuration = configuration(
            levels: [.dateTaken, .decision, .existingFolder],
            dateGranularity: .year,
            existingDepth: .fullPath
        )
        let result = try SourceOrganizationPlanner.makePlan(
            sourceFolder: fixture.photos,
            selectedItems: [item],
            familyContextItems: [item],
            configuration: configuration,
            knownOriginFolderPathBytesByFileID: [
                item.primaryFile.id: Data("Trips/Italy".utf8),
            ]
        )

        XCTAssertEqual(
            result.mappings.first?.destination.path,
            fixture.photos.appendingPathComponent(
                "Organized/Unknown Date/Yes/Trips/Italy/A.JPG"
            ).path
        )
        XCTAssertFalse(
            result.mappings.first?.destination.path.contains(
                "Organized/Yes/2026/Organized"
            ) ?? true
        )
    }

    func testCollisionsBlockWholePlanWithoutAddingSuffixes() throws {
        let fixture = try makeFixture(named: "Collision")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstDirectory = try directory("First", under: fixture.photos)
        let secondDirectory = try directory("Second", under: fixture.photos)
        let first = try mediaFile("A.JPG", under: firstDirectory)
        let second = try mediaFile("A.JPG", under: secondDirectory)
        let items = [
            makeItem(id: "First/A.JPG", url: first, rating: .yes),
            makeItem(id: "Second/A.JPG", url: second, rating: .yes),
        ]

        let result = try plan(
            fixture: fixture,
            selected: items,
            levels: [.decision]
        )

        XCTAssertFalse(result.canExecute)
        XCTAssertEqual(result.collisions.count, 1)
        XCTAssertEqual(result.collisions.first?.sources.count, 2)
        XCTAssertFalse(
            result.mappings.contains {
                $0.destination.lastPathComponent.contains(" 2")
            }
        )
    }

    func testExistingDestinationBlocksButExactCurrentPathIsAlreadyOrganized() throws {
        let fixture = try makeFixture(named: "ExistingDestination")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceDirectory = try directory("Trips", under: fixture.photos)
        let source = try mediaFile("A.JPG", under: sourceDirectory)
        let destinationDirectory = try directory(
            "Organized/Yes",
            under: fixture.photos
        )
        _ = try mediaFile("A.JPG", under: destinationDirectory)
        let sourceItem = makeItem(
            id: "Trips/A.JPG",
            url: source,
            rating: .yes
        )

        let blocked = try plan(
            fixture: fixture,
            selected: [sourceItem],
            levels: [.decision]
        )
        XCTAssertFalse(blocked.canExecute)
        XCTAssertEqual(blocked.collisions.count, 1)

        try FileManager.default.removeItem(at: source)
        let current = makeItem(
            id: "Organized/Yes/A.JPG",
            url: destinationDirectory.appendingPathComponent("A.JPG"),
            rating: .yes
        )
        let already = try plan(
            fixture: fixture,
            selected: [current],
            levels: [.decision],
            origins: [current.primaryFile.id: Data("Trips".utf8)]
        )
        XCTAssertTrue(already.collisions.isEmpty)
        XCTAssertEqual(already.alreadyOrganizedItemCount, 1)
        XCTAssertEqual(already.movingFileCount, 0)
        XCTAssertFalse(already.canExecute)
    }

    func testWorkerMovesPairAndXMPThenUndoRestoresOriginals() throws {
        let fixture = try makeFixture(named: "MoveAndUndo")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceDirectory = try directory("Trips", under: fixture.photos)
        let raw = try mediaFile("A.NEF", under: sourceDirectory)
        let jpeg = try mediaFile("A.JPG", under: sourceDirectory)
        let xmp = sourceDirectory.appendingPathComponent("A.xmp")
        let acr = sourceDirectory.appendingPathComponent("A.acr")
        try Data("xmp metadata".utf8).write(to: xmp)
        try Data("heavy edits".utf8).write(to: acr)
        let item = makePair(
            id: "Trips/A.NEF",
            raw: raw,
            jpeg: jpeg,
            rating: .yes
        )
        let organizedPlan = try plan(
            fixture: fixture,
            selected: [item],
            levels: [.decision]
        )

        XCTAssertEqual(organizedPlan.sidecarFileCount, 1)
        XCTAssertEqual(organizedPlan.excludedACRCompanionCount, 1)
        let result = SourceOrganizationWorker.organize(
            organizedPlan,
            journalDirectory: fixture.journals
        ) { _, _ in }
        let destination = fixture.photos.appendingPathComponent(
            "Organized/Yes",
            isDirectory: true
        )

        XCTAssertEqual(result.movedFiles, 3)
        XCTAssertEqual(result.failedItems, 0)
        XCTAssertNotNil(result.undoRecord)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jpeg.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("A.NEF").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("A.JPG").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("A.xmp").path
        ))
        XCTAssertEqual(try Data(contentsOf: acr), Data("heavy edits".utf8))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourceDirectory.path),
            "legacy folders are deliberately retained even when empty"
        )

        let undo = SourceOrganizationWorker.undo(
            try XCTUnwrap(result.undoRecord),
            currentItems: [],
            journalDirectory: fixture.journals
        ) { _, _ in }
        XCTAssertEqual(undo.movedFiles, 3)
        XCTAssertEqual(undo.failedItems, 0)
        XCTAssertEqual(try Data(contentsOf: raw), Data("A.NEF".utf8))
        XCTAssertEqual(try Data(contentsOf: jpeg), Data("A.JPG".utf8))
        XCTAssertEqual(try Data(contentsOf: xmp), Data("xmp metadata".utf8))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destination.path),
            "undo restores files but does not delete the folders Louppe made"
        )
        XCTAssertFalse(
            FileOperationJournal.hasPendingOperations(
                directory: fixture.journals
            )
        )
    }

    func testExFATCompatibilityProbeProvesNoOverwriteMoveAndCleansUp() throws {
        let fixture = try makeFixture(named: "ExFATProbe")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try SourceOrganizationWorker
            .verifyExFATMoveCompatibilityForTesting(in: fixture.photos)

        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.photos,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".louppe-move-probe-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testSharedXMPSidecarBlocksPartialFamilyScope() throws {
        let fixture = try makeFixture(named: "PartialXMPFamily")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceDirectory = try directory("Trips", under: fixture.photos)
        let raw = try mediaFile("A.NEF", under: sourceDirectory)
        let jpeg = try mediaFile("A.JPG", under: sourceDirectory)
        try Data("shared xmp".utf8).write(
            to: sourceDirectory.appendingPathComponent("A.xmp")
        )
        let rawItem = makeItem(id: "Trips/A.NEF", url: raw, rating: .yes)
        let jpegItem = makeItem(id: "Trips/A.JPG", url: jpeg, rating: .yes)

        let result = try SourceOrganizationPlanner.makePlan(
            sourceFolder: fixture.photos,
            selectedItems: [rawItem],
            familyContextItems: [rawItem, jpegItem],
            configuration: configuration(levels: [.decision]),
            knownOriginFolderPathBytesByFileID: [:]
        )

        XCTAssertFalse(result.canExecute)
        XCTAssertTrue(result.collisions.contains {
            $0.message.contains("shared XMP sidecar")
        })
    }

    func testSchemaSixOriginBytesAreRestoredOnlyBySchemaSix() throws {
        let fixture = try makeFixture(named: "SchemaOrigin")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try mediaFile("A.JPG", under: fixture.photos)
        let item = makeItem(id: "A.JPG", url: source)
        let identity = try XCTUnwrap(item.primaryFile.scannedIdentity)
        let entry = SessionEntry(
            filename: item.primaryFile.id,
            pairedFilename: nil,
            rating: Rating.undecided.rawValue,
            ratedAt: nil,
            fileIdentity: identity,
            organizationOriginFolderPathBytes: Data("Trips/Italy".utf8)
        )
        let current = SessionFile(
            version: 6,
            sourcePath: fixture.photos.path,
            scannedAt: Date(),
            entries: [entry],
            fileIDEncoding: .percentEncodedFileSystemPath
        )
        let older = SessionFile(
            version: 5,
            sourcePath: fixture.photos.path,
            scannedAt: Date(),
            entries: [entry],
            fileIDEncoding: .percentEncodedFileSystemPath
        )

        XCTAssertEqual(
            SessionRatingIndex(session: current).value(for: item.primaryFile)?
                .organizationOriginFolderPathBytes,
            Data("Trips/Italy".utf8)
        )
        XCTAssertNil(
            SessionRatingIndex(session: older).value(for: item.primaryFile)?
                .organizationOriginFolderPathBytes
        )
    }

    func testInterruptedOrganizationJournalUsesMoveRecoveryRules() throws {
        let fixture = try makeFixture(named: "Recovery")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try mediaFile("A.JPG", under: fixture.photos)
        let destinationDirectory = try directory(
            "Organized/Yes",
            under: fixture.photos
        )
        let destination = destinationDirectory.appendingPathComponent("A.JPG")
        let writer = try FileOperationJournal.start(
            kind: .organizeSource,
            seeds: [
                .init(
                    itemID: "A.JPG",
                    source: source,
                    destination: destination,
                    expectedIdentity: try FileOperationJournal.captureIdentity(
                        at: source
                    )
                ),
            ],
            directory: fixture.journals
        )
        try writer.mark(.started, fileAt: 0)
        try DurableFileIO.atomicExclusiveRename(from: source, to: destination)
        let identity = try FileOperationJournal.captureIdentity(at: destination)
        try writer.mark(
            .completed,
            fileAt: 0,
            identityAt: destination,
            expectedIdentity: identity
        )
        XCTAssertTrue(
            FileOperationJournal.finalize(
                writer,
                operationIsConsistent: false
            )
        )

        let report = FileOperationJournal.recoverPendingOperations(
            directory: fixture.journals
        )
        XCTAssertEqual(report.unresolvedOperations, 0)
        XCTAssertEqual(report.preservedMoves, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("A.JPG".utf8))
    }

    private struct Fixture {
        let root: URL
        let photos: URL
        let journals: URL
    }

    private func makeFixture(named name: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Louppe-SourceOrganization-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let journals = root.appendingPathComponent("Journals", isDirectory: true)
        try FileManager.default.createDirectory(
            at: photos,
            withIntermediateDirectories: true
        )
        return Fixture(root: root, photos: photos, journals: journals)
    }

    private func directory(_ path: String, under root: URL) throws -> URL {
        let result = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: result,
            withIntermediateDirectories: true
        )
        return result
    }

    private func mediaFile(_ name: String, under directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    private func makeItem(
        id: String,
        url: URL,
        captureDate: Date? = nil,
        rating: Rating = .undecided
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            primaryURL: url,
            pairedURL: nil,
            captureDate: captureDate,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 5,
            rating: rating
        )
    }

    private func makePair(
        id: String,
        raw: URL,
        jpeg: URL,
        rating: Rating
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            primaryURL: raw,
            pairedURL: jpeg,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 5,
            pairedFileSize: 5,
            rating: rating
        )
    }

    private func configuration(
        levels: [SourceOrganizationLevelKind],
        dateGranularity: SourceOrganizationDateGranularity = .day,
        existingDepth: SourceOrganizationExistingFolderDepth = .topLevel
    ) -> SourceOrganizationConfiguration {
        SourceOrganizationConfiguration(
            levels: levels.map {
                SourceOrganizationLevel(kind: $0, isEnabled: true)
            },
            dateGranularity: dateGranularity,
            existingFolderDepth: existingDepth,
            containerName: "Organized"
        )
    }

    private func plan(
        fixture: Fixture,
        selected: [PhotoItem],
        levels: [SourceOrganizationLevelKind],
        dateGranularity: SourceOrganizationDateGranularity = .day,
        existingDepth: SourceOrganizationExistingFolderDepth = .topLevel,
        origins: [String: Data] = [:]
    ) throws -> SourceOrganizationPlan {
        try SourceOrganizationPlanner.makePlan(
            sourceFolder: fixture.photos,
            selectedItems: selected,
            familyContextItems: selected,
            configuration: configuration(
                levels: levels,
                dateGranularity: dateGranularity,
                existingDepth: existingDepth
            ),
            knownOriginFolderPathBytesByFileID: origins
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(8),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("timed out waiting for source organization")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
