import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Louppe

final class FileSafetyAuditRegressionTests: XCTestCase {
    func testEquivalentNamesWithinXMPFamilyFailBeforeDestinationProbes() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try directory("Destination", in: root)
        let urls = ["PHOTO.JPG", "PHOTO.jpg"].map { root.appendingPathComponent($0) }
        let members = try urls.map {
            try XMPStemFamilyMember(mediaURL: $0, metadata: XMPPublicationMetadata(
                decision: .undecided, stars: nil, colorLabel: nil, profile: .universal
            ))
        }
        let resolved = try XMPSidecarResolver.resolve(
            members: members, directoryEntries: [], caseSensitiveNames: true
        )
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].members.count, 2)
        let paths = Set(members.map(\.mediaPath))
        let family = XMPExportPreparedFamily(
            id: "case-sensitive-family", filenames: urls.map(\.lastPathComponent),
            selectedMediaPaths: paths, allMediaPaths: paths, category: .create,
            message: "", changeCounts: XMPPublicationChangeCounts(),
            bestEffortFilenames: [], excludedACRCompanionCount: 0,
            canonicalSourceWasPresent: false, recognizedApplicationPacketCount: 0,
            canonicalSource: nil, canonicalSourceIdentity: nil,
            canonicalSourceDigest: nil, finalPacket: Data("packet".utf8),
            applicationPackets: [], sameStemConflict: nil
        )
        var probes = 0
        XCTAssertThrowsError(try ExportWorker.makePlan(
            for: urls.map { item($0) }, in: destination,
            xmpPlan: XMPExportPreparedPlan(selectedItemCount: 2, physicalFileCount: 2, families: [family]),
            destinationEntryExists: { _ in probes += 1; return false }
        )) { error in
            guard case ExportWorker.PlanningError.conflictingFamilyNames = error else {
                return XCTFail("Unexpected planning error: \(error)")
            }
        }
        XCTAssertEqual(probes, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }

    func testRepeatedBasenamesNeedOneDestinationProbePerFile() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try directory("Destination", in: root)
        let count = 800
        let items = (0..<count).map { index in
            item(root.appendingPathComponent("Folder-\(index)/PHOTO.JPG"), id: "Folder-\(index)/PHOTO.JPG")
        }
        var probes = 0
        let plan = try ExportWorker.makePlan(
            for: items, in: destination,
            destinationEntryExists: { _ in probes += 1; return false }
        )
        XCTAssertEqual(probes, count, "The deterministic I/O count must remain linear.")
        XCTAssertEqual(plan.items[0].files[0].target.lastPathComponent, "PHOTO.JPG")
        XCTAssertEqual(plan.items[count - 1].files[0].target.lastPathComponent, "PHOTO (799).JPG")
        XCTAssertEqual(Set(plan.items.flatMap(\.files).map(\.target)).count, count)
    }

    func testSuffixCachePreservesWholeFamilyAndAlreadySuffixedNames() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try directory("Destination", in: root)
        try Data("occupied raw".utf8).write(to: destination.appendingPathComponent("PHOTO.NEF"))
        let pair = PhotoItem(
            id: "Pair/PHOTO.NEF", primaryURL: root.appendingPathComponent("Pair/PHOTO.NEF"),
            pairedURL: root.appendingPathComponent("Pair/PHOTO.JPG"), captureDate: nil,
            cameraModel: nil, lensModel: nil, fileSize: 1, pairedFileSize: 1
        )
        let plan = try ExportWorker.makePlan(for: [
            pair,
            item(root.appendingPathComponent("Single/PHOTO.JPG"), id: "Single/PHOTO.JPG"),
            item(root.appendingPathComponent("Named/PHOTO (1).JPG"), id: "Named/PHOTO (1).JPG"),
            item(root.appendingPathComponent("Last/PHOTO.JPG"), id: "Last/PHOTO.JPG"),
        ], in: destination)
        XCTAssertEqual(plan.items[0].files.map { $0.target.lastPathComponent }, ["PHOTO (1).NEF", "PHOTO (1).JPG"])
        XCTAssertEqual(plan.items[1].files[0].target.lastPathComponent, "PHOTO.JPG", "A RAW-only collision must not force a JPEG-only group's starting suffix.")
        XCTAssertEqual(plan.items[2].files[0].target.lastPathComponent, "PHOTO (1) (1).JPG")
        XCTAssertEqual(plan.items[3].files[0].target.lastPathComponent, "PHOTO (2).JPG")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("PHOTO.NEF")), Data("occupied raw".utf8))
    }

    func testCancellationDuringCollisionSearchStopsCopyBeforeJournalActivation() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try directory("Destination", in: root)
        let flag = ExportWorker.CancelFlag()
        var probes = 0
        XCTAssertThrowsError(try ExportWorker.makePlan(
            for: [item(root.appendingPathComponent("PHOTO.JPG"))], in: destination,
            isCancelled: { flag.isSet },
            destinationEntryExists: { _ in
                probes += 1
                if probes == 4 { flag.request(.userConfirmed) }
                return true
            }
        )) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(probes, 4)

        let source = root.appendingPathComponent("ACTUAL.JPG")
        try Data("original".utf8).write(to: source)
        let selected = try verifiedItem(source)
        let journals = root.appendingPathComponent("Journals")
        let result = ExportWorker.copy(
            [selected], to: destination, journalDirectory: journals,
            isCancelled: { flag.isSet }, cancellationReason: { flag.reason },
            progress: { _, _ in }
        )
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.cancellationReason, .userConfirmed)
        XCTAssertFalse(result.journalFailure)
        XCTAssertFalse(result.requiresRecovery)
        XCTAssertEqual(result.failedPhotos, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journals.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
    }

    func testOrganizationRejectsHiddenAndPackageContainers() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("PHOTO.JPG")
        try Data("photo".utf8).write(to: source)
        let selected = try verifiedItem(source)
        for name in [".Hidden", "Photos.app", "Photos.bundle", "Photos.photoslibrary", "Photos.framework"] {
            var config = SourceOrganizationConfiguration.initial(hasMultipleTopLevelFolders: false)
            config.containerName = name
            XCTAssertThrowsError(try SourceOrganizationPlanner.makePlan(
                sourceFolder: root, selectedItems: [selected], familyContextItems: [selected],
                configuration: config, knownOriginFolderPathBytesByFileID: [:]
            ), name)
            XCTAssertEqual(try Data(contentsOf: source), Data("photo".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
    }

    func testOrganizationRefusesFinderHiddenFolderBeforeAndAfterPreview() throws {
        for hideBeforePlanning in [true, false] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let photos = try directory("Photos", in: root)
            let container = try directory("Visible", in: photos)
            let source = photos.appendingPathComponent("PHOTO.JPG")
            try Data("photo".utf8).write(to: source)
            let selected = try verifiedItem(source)
            var config = SourceOrganizationConfiguration.initial(hasMultipleTopLevelFolders: false)
            config.containerName = "Visible"
            config.levels = [.init(kind: .decision, isEnabled: true)]
            if hideBeforePlanning { try setFinderHidden(container) }
            let plan = try SourceOrganizationPlanner.makePlan(
                sourceFolder: photos, selectedItems: [selected], familyContextItems: [selected],
                configuration: config, knownOriginFolderPathBytesByFileID: [:]
            )
            if hideBeforePlanning {
                XCTAssertFalse(plan.canExecute)
                XCTAssertTrue(plan.collisions.contains { $0.message.contains("visible folder") })
            } else {
                XCTAssertTrue(plan.canExecute)
                try setFinderHidden(container)
                let journals = root.appendingPathComponent("Journals")
                let moved = SourceOrganizationWorker.organize(plan, journalDirectory: journals, progress: { _, _ in })
                XCTAssertEqual(moved.movedFiles, 0)
                XCTAssertEqual(moved.failedItems, 1)
                XCTAssertFalse(moved.requiresRecovery)
                XCTAssertNil(moved.undoRecord)
                XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: journals))
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("photo".utf8))
        }
    }

    private func setFinderHidden(_ url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { Darwin.chflags($0!, UInt32(UF_HIDDEN)) }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        XCTAssertEqual(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
    }

    func testGeneratedOrganizationFoldersRemainScannableAndUndoable() throws {
        for camera in [".Camera", "Photos.app", "Photos.photoslibrary"] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let photos = try directory("Photos", in: root)
            let source = photos.appendingPathComponent("PHOTO.JPG")
            try Data("photo".utf8).write(to: source)
            let selected = try verifiedItem(source, camera: camera)
            var config = SourceOrganizationConfiguration.initial(hasMultipleTopLevelFolders: false)
            config.levels = [.init(kind: .camera, isEnabled: true)]
            let plan = try SourceOrganizationPlanner.makePlan(
                sourceFolder: photos, selectedItems: [selected], familyContextItems: [selected],
                configuration: config, knownOriginFolderPathBytesByFileID: [:]
            )
            XCTAssertTrue(plan.canExecute, camera)
            let journals = root.appendingPathComponent("Journals")
            let moved = SourceOrganizationWorker.organize(plan, journalDirectory: journals, progress: { _, _ in })
            XCTAssertEqual(moved.movedFiles, 1, camera)
            XCTAssertFalse(moved.requiresRecovery, camera)
            let scan = try FolderScanner.scan(photos, progress: { _ in })
            XCTAssertEqual(scan.count, 1, camera)
            let undo = try XCTUnwrap(moved.undoRecord)
            let restored = SourceOrganizationWorker.undo(undo, currentItems: scan, journalDirectory: journals, progress: { _, _ in })
            XCTAssertEqual(restored.movedFiles, 1, camera)
            XCTAssertEqual(try Data(contentsOf: source), Data("photo".utf8))
            XCTAssertEqual(try FolderScanner.scan(photos, progress: { _ in }).count, 1)
        }
    }

    func testGeneratedMovePartialRecoveryRemovesOnlyRecordedInode() throws {
        for variant in ["recorded-partial", "recorded-quarantine", "recorded-complete", "staged-complete", "staged-partial", "unrecorded", "replacement"] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("PHOTO.JPG")
            let destination = root.appendingPathComponent("DONE.JPG")
            let packetTarget = root.appendingPathComponent("DONE.xmp")
            let journals = root.appendingPathComponent("Journals")
            let bytes = Data("original".utf8)
            let packet = Data("intended complete packet".utf8)
            try bytes.write(to: source)
            let writer = try FileOperationJournal.start(kind: .exportMove, seeds: [
                .init(itemID: "family", source: source, destination: destination),
                .init(itemID: "family", source: source, destination: packetTarget,
                      role: .preparedXMP, preparedContentDigest: Data(SHA256.hash(data: packet))),
            ], directory: journals)
            try completeMove(writer, at: 0, from: source, to: destination)
            let partial = try XCTUnwrap(writer.temporaryURL(at: 1))
            try writer.mark(.started, fileAt: 1)
            try DurableFileIO.writeNewFile((variant == "recorded-complete" || variant == "staged-complete") ? packet : Data("partial".utf8), to: partial, fullSync: true)
            if variant != "unrecorded" {
                let identity = try FileOperationJournal.captureIdentity(at: partial)
                try writer.mark(variant.hasPrefix("staged-") ? .staged : .started, fileAt: 1, identityAt: partial, expectedIdentity: identity, includeStatusChange: false)
            }
            if variant == "recorded-quarantine" {
                try DurableFileIO.atomicExclusiveRename(from: partial, to: packetTarget)
                try DurableFileIO.syncRenameDirectories(from: partial, to: packetTarget, fullSync: true)
            }
            if variant == "replacement" {
                try FileManager.default.moveItem(at: partial, to: root.appendingPathComponent("SavedPartial"))
                try Data("unrelated replacement".utf8).write(to: partial)
            }
            FileOperationJournal.finalize(writer, operationIsConsistent: false)
            let report = FileOperationJournal.recoverPendingOperations(directory: journals)
            XCTAssertEqual(try Data(contentsOf: source), bytes, variant)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), variant)
            if variant == "unrecorded" || variant == "replacement" || variant == "staged-partial" {
                XCTAssertEqual(report.unresolvedOperations, 1, variant)
                XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path), variant)
                if variant == "replacement" {
                    XCTAssertEqual(try Data(contentsOf: partial), Data("unrelated replacement".utf8))
                }
            } else {
                XCTAssertEqual(report.unresolvedOperations, 0, variant)
                XCTAssertEqual(report.removedPartialCopies, 1, variant)
                XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), variant)
                XCTAssertFalse(FileManager.default.fileExists(atPath: packetTarget.path), variant)
                XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: journals), variant)
                XCTAssertEqual(FileOperationJournal.recoverPendingOperations(directory: journals).discoveredOperations, 0)
            }
        }
    }

    func testCompletedXMPRetirementRecoversEveryCleanupLocation() throws {
        for position in ["target", "quarantine", "unlinked", "replacement", "both"] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("PHOTO.JPG")
            let sourceXMP = root.appendingPathComponent("PHOTO.xmp")
            let destination = root.appendingPathComponent("DONE.JPG")
            let destinationXMP = root.appendingPathComponent("DONE.xmp")
            let retirement = root.appendingPathComponent(".retired-xmp")
            let journals = root.appendingPathComponent("Journals")
            let media = Data("original photo".utf8)
            let oldPacket = Data("old packet".utf8)
            let merged = Data("merged packet".utf8)
            try media.write(to: source)
            try oldPacket.write(to: sourceXMP)
            let writer = try FileOperationJournal.start(kind: .exportMove, seeds: [
                .init(itemID: "family", source: source, destination: destination),
                .init(itemID: "family", source: sourceXMP, destination: destinationXMP,
                      role: .preparedXMP, expectedSourceDigest: Data(SHA256.hash(data: oldPacket)),
                      preparedContentDigest: Data(SHA256.hash(data: merged))),
                .init(itemID: "family", source: sourceXMP, destination: retirement,
                      role: .retiredXMPSource, expectedSourceDigest: Data(SHA256.hash(data: oldPacket))),
            ], directory: journals)
            try completeMove(writer, at: 0, from: source, to: destination)
            try completePacket(writer, at: 1, contents: merged, to: destinationXMP)
            try completeMove(writer, at: 2, from: sourceXMP, to: retirement)
            let quarantine = try XCTUnwrap(writer.temporaryURL(at: 2))
            if position != "target" {
                try DurableFileIO.atomicExclusiveRename(from: retirement, to: quarantine)
                try DurableFileIO.syncRenameDirectories(from: retirement, to: quarantine, fullSync: true)
            }
            if position == "unlinked" {
                try DurableFileIO.unlinkRegularFile(at: quarantine)
                try DurableFileIO.syncRemoval(of: quarantine, fullSync: true)
            } else if position == "replacement" {
                try FileManager.default.moveItem(at: quarantine, to: root.appendingPathComponent("SavedOldPacket"))
                try Data("unrelated".utf8).write(to: quarantine)
            } else if position == "both" {
                try Data("unrelated".utf8).write(to: retirement)
            }
            FileOperationJournal.finalize(writer, operationIsConsistent: false)
            let report = FileOperationJournal.recoverPendingOperations(directory: journals)
            XCTAssertEqual(try Data(contentsOf: destination), media, position)
            XCTAssertEqual(try Data(contentsOf: destinationXMP), merged, position)
            if position == "replacement" || position == "both" {
                XCTAssertEqual(report.unresolvedOperations, 1, position)
                XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.path), position)
                let unrelated = position == "both" ? retirement : quarantine
                XCTAssertEqual(try Data(contentsOf: unrelated), Data("unrelated".utf8))
            } else {
                XCTAssertEqual(report.unresolvedOperations, 0, position)
                XCTAssertFalse(FileManager.default.fileExists(atPath: quarantine.path), position)
                XCTAssertFalse(FileManager.default.fileExists(atPath: retirement.path), position)
                XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: journals), position)
                XCTAssertEqual(FileOperationJournal.recoverPendingOperations(directory: journals).discoveredOperations, 0)
            }
        }
    }

    func testJournalRejectsNonregularMediaWithoutChangingFolderIdentityCapture() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try FileOperationJournal.captureIdentity(at: root))
        XCTAssertNoThrow(try SessionPersistence.SourceFolderIdentity.capture(at: root))
        let fifo = root.appendingPathComponent("PHOTO.JPG")
        XCTAssertEqual(fifo.withUnsafeFileSystemRepresentation { Darwin.mkfifo($0!, 0o600) }, 0)
        let regular = root.appendingPathComponent("REGULAR.JPG")
        try Data("regular".utf8).write(to: regular)
        let symlink = root.appendingPathComponent("LINK.JPG")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: regular)
        for source in [fifo, root, symlink] {
            let journals = root.appendingPathComponent(UUID().uuidString)
            XCTAssertThrowsError(try FileOperationJournal.start(
                kind: .exportCopy,
                seeds: [.init(itemID: "file", source: source, destination: root.appendingPathComponent("DONE.JPG"))],
                directory: journals
            ))
            XCTAssertFalse(FileOperationJournal.hasPendingOperations(directory: journals))
        }
        XCTAssertFalse(FileOperationJournal.contentsEqual(fifo, regular))
        XCTAssertThrowsError(try DurableFileIO.syncFile(at: fifo, fullSync: true))
    }

    func testMalformedFIFOJournalReturnsUnresolvedWithoutReadingTheFIFO() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("PHOTO.JPG")
        let destination = root.appendingPathComponent("DONE.JPG")
        let journals = root.appendingPathComponent("Journals")
        try Data("original".utf8).write(to: source)
        let writer = try FileOperationJournal.start(kind: .exportCopy, seeds: [
            .init(itemID: "photo", source: source, destination: destination),
        ], directory: journals)
        try writer.mark(.started, fileAt: 0)
        let temporary = try XCTUnwrap(writer.temporaryURL(at: 0))
        try DurableFileIO.writeNewFile(Data("copy".utf8), to: temporary, fullSync: true)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(source.withUnsafeFileSystemRepresentation { Darwin.mkfifo($0!, 0o600) }, 0)
        let original = writer.plan.files[0]
        let malformed = FileOperationJournal.PlannedFile(
            itemID: original.itemID, sourcePath: original.sourcePath,
            destinationPath: original.destinationPath, temporaryPath: original.temporaryPath,
            identity: try FileOperationJournal.captureIdentity(at: source),
            sourcePathBytes: original.sourcePathBytes, destinationPathBytes: original.destinationPathBytes,
            temporaryPathBytes: original.temporaryPathBytes
        )
        let plan = FileOperationJournal.Plan(
            version: writer.plan.version, operationID: writer.plan.operationID,
            kind: writer.plan.kind, createdAt: writer.plan.createdAt, files: [malformed]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(plan).write(to: writer.token.directory.appendingPathComponent("plan.json"), options: .atomic)
        FileOperationJournal.finalize(writer, operationIsConsistent: false)
        let report = FileOperationJournal.recoverPendingOperations(directory: journals)
        XCTAssertEqual(report.unresolvedOperations, 1)
        XCTAssertEqual(try Data(contentsOf: temporary), Data("copy".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func fixture() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/louppe-file-safety-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directory(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(_ url: URL, id: String? = nil) -> PhotoItem {
        PhotoItem(id: id ?? url.lastPathComponent, primaryURL: url, pairedURL: nil,
                  captureDate: nil, cameraModel: nil, lensModel: nil, fileSize: 1)
    }

    private func verifiedItem(_ url: URL, camera: String? = nil) throws -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: url.lastPathComponent, url: url, captureDate: nil, cameraModel: camera,
            lensModel: nil, fileSize: 5, scannedIdentity: try FileOperationJournal.captureIdentity(at: url)
        ))
    }

    private func completeMove(_ writer: FileOperationJournal.Writer, at index: Int, from source: URL, to destination: URL) throws {
        try writer.mark(.started, fileAt: index)
        let temporary = try XCTUnwrap(writer.temporaryURL(at: index))
        try DurableFileIO.atomicExclusiveRename(from: source, to: temporary)
        try DurableFileIO.syncRenameDirectories(from: source, to: temporary, fullSync: true)
        let staged = try FileOperationJournal.captureIdentity(at: temporary)
        try writer.mark(.staged, fileAt: index, identityAt: temporary, expectedIdentity: staged)
        try DurableFileIO.atomicExclusiveRename(from: temporary, to: destination)
        try DurableFileIO.syncRenameDirectories(from: temporary, to: destination, fullSync: true)
        let completed = try FileOperationJournal.captureIdentity(at: destination)
        try writer.mark(.completed, fileAt: index, identityAt: destination, expectedIdentity: completed)
    }

    private func completePacket(_ writer: FileOperationJournal.Writer, at index: Int, contents: Data, to destination: URL) throws {
        try writer.mark(.started, fileAt: index)
        let temporary = try XCTUnwrap(writer.temporaryURL(at: index))
        try DurableFileIO.writeNewFile(contents, to: temporary, fullSync: true)
        let staged = try FileOperationJournal.captureIdentity(at: temporary)
        try writer.mark(.staged, fileAt: index, identityAt: temporary, expectedIdentity: staged, includeStatusChange: false)
        try DurableFileIO.atomicExclusiveRename(from: temporary, to: destination)
        try DurableFileIO.syncRenameDirectories(from: temporary, to: destination, fullSync: true)
        let completed = try FileOperationJournal.captureIdentity(at: destination)
        try writer.mark(.completed, fileAt: index, identityAt: destination, expectedIdentity: completed, includeStatusChange: false)
    }
}
