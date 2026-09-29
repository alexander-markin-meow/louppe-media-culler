import Darwin
import Foundation
import XCTest
@testable import Louppe

final class XMPPublicationIdentityTests: XCTestCase {
    func testReplacementBeforePreflightIsARescanConflict() async throws {
        let folder = try fixture()
        let media = folder.appendingPathComponent("PHOTO.NEF")
        let photo = try item(media)
        let input = try input([photo], folder: folder)
        try Data("replacement".utf8).write(to: media, options: .atomic)
        let plan = try await plan(input)
        XCTAssertEqual(plan.count(.externalModificationConflict), 1)
        XCTAssertEqual(plan.publishableCount, 0)
        XCTAssertTrue(plan.entries[0].message.contains("Rescan"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("PHOTO.xmp").path))
    }

    func testReplacementAfterPreflightCannotCreateOrUpdate() async throws {
        for existing in [false, true] {
            let folder = try fixture()
            let media = folder.appendingPathComponent("PHOTO.NEF")
            let photo = try item(media)
            let sidecar = folder.appendingPathComponent("PHOTO.xmp")
            let oldPacket = try XMPFieldMapping.merge(packet: nil, metadata: .init(decision: .no, stars: .one, colorLabel: nil, profile: .universal))
            if existing { try oldPacket.write(to: sidecar) }
            let preparedPlan = try await plan(input([photo], folder: folder))
            try Data("replacement".utf8).write(to: media, options: .atomic)
            let result = await publish(preparedPlan)
            XCTAssertEqual(result.conflicts, 1)
            XCTAssertEqual(result.created + result.updated + result.alreadyCurrent, 0)
            if existing { XCTAssertEqual(try Data(contentsOf: sidecar), oldPacket) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path)) }
        }
    }

    func testSourceFolderReplacementBeforePreflightAndBeforePublication() async throws {
        for beforePreflight in [true, false] {
            let folder = try fixture()
            let photo = try item(folder.appendingPathComponent("PHOTO.NEF"))
            let input = try input([photo], folder: folder)
            var preparedPlan: XMPPublicationPlan?
            if !beforePreflight { preparedPlan = try await plan(input) }
            let archived = folder.appendingPathExtension("archived")
            try FileManager.default.moveItem(at: folder, to: archived)
            addTeardownBlock { try? FileManager.default.removeItem(at: archived) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("unrelated".utf8).write(to: folder.appendingPathComponent("PHOTO.NEF"))
            let finalPlan: XMPPublicationPlan
            if let preparedPlan { finalPlan = preparedPlan }
            else { finalPlan = try await plan(input) }
            let result = await publish(finalPlan)
            XCTAssertEqual(result.conflicts, 1)
            XCTAssertEqual(result.created + result.updated, 0)
            for directory in [folder, archived] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("PHOTO.xmp").path))
            }
        }
    }

    func testUnselectedSiblingRemovalBlocksSharedPacket() async throws {
        let folder = try fixture()
        let jpeg = folder.appendingPathComponent("PHOTO.JPG")
        try Data("jpeg".utf8).write(to: jpeg)
        let raw = try item(folder.appendingPathComponent("PHOTO.NEF"))
        let partner = try item(jpeg)
        let preparedPlan = try await plan(input([raw], context: [raw, partner], folder: folder))
        XCTAssertEqual(preparedPlan.publishableCount, 1)
        XCTAssertEqual(preparedPlan.entries[0].sourceValidation?.members.count, 2)
        try FileManager.default.removeItem(at: jpeg)
        let result = await publish(preparedPlan)
        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(result.created, 0)
    }

    func testNonregularReplacementLeavesEveryLeafUntouched() async throws {
        for replacement in ["symlink", "fifo", "directory"] {
            let folder = try fixture()
            let media = folder.appendingPathComponent("PHOTO.NEF")
            let preparedPlan = try await plan(input([try item(media)], folder: folder))
            try FileManager.default.removeItem(at: media)
            switch replacement {
            case "symlink":
                let other = folder.appendingPathComponent("OTHER.NEF")
                try Data("other".utf8).write(to: other)
                try FileManager.default.createSymbolicLink(at: media, withDestinationURL: other)
            case "fifo":
                XCTAssertEqual(media.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }, 0)
            default:
                try FileManager.default.createDirectory(at: media, withIntermediateDirectories: false)
            }
            let result = await publish(preparedPlan)
            XCTAssertEqual(result.conflicts, 1, replacement)
            XCTAssertEqual(result.created, 0, replacement)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("PHOTO.xmp").path))
        }
    }

    func testMediaReplacementAtFinalFlushBoundaryBlocksPublication() async throws {
        let folder = try fixture()
        let media = folder.appendingPathComponent("PHOTO.NEF")
        let preparedPlan = try await plan(input([try item(media)], folder: folder))
        let entry = try XCTUnwrap(preparedPlan.entries.first)
        let validation = try XCTUnwrap(entry.sourceValidation)
        let store = XMPMetadataStore()
        let prepared = try await store.prepareWrite(path: try XCTUnwrap(entry.canonicalSidecar), metadata: try XCTUnwrap(entry.metadata), sourceValidation: validation)
        do {
            _ = try await store.commit(prepared, sourceValidation: validation, testHooks: .init(beforeFinalValidation: {
                try Data("replacement after packet flush".utf8).write(to: media, options: .atomic)
            }))
            XCTFail("Replacement must stop publication")
        } catch { XCTAssertTrue(error is XMPPublicationSourceChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("PHOTO.xmp").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".louppe-write-") })
    }

    func testFolderReplacementAtFinalBoundaryKeepsCleanupInOriginalDirectory() async throws {
        let folder = try fixture()
        let preparedPlan = try await plan(input([try item(folder.appendingPathComponent("PHOTO.NEF"))], folder: folder))
        let entry = try XCTUnwrap(preparedPlan.entries.first)
        let validation = try XCTUnwrap(entry.sourceValidation)
        let store = XMPMetadataStore()
        let prepared = try await store.prepareWrite(path: try XCTUnwrap(entry.canonicalSidecar), metadata: try XCTUnwrap(entry.metadata), sourceValidation: validation)
        let archived = folder.appendingPathExtension("archived")
        addTeardownBlock { try? FileManager.default.removeItem(at: archived) }
        do {
            _ = try await store.commit(prepared, sourceValidation: validation, testHooks: .init(beforeFinalValidation: {
                try FileManager.default.moveItem(at: folder, to: archived)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                try Data("unrelated".utf8).write(to: folder.appendingPathComponent("PHOTO.NEF"))
            }))
            XCTFail("Replacement must stop publication")
        } catch { XCTAssertTrue(error is XMPPublicationSourceChanged) }
        for directory in [folder, archived] {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertFalse(names.contains("PHOTO.xmp"))
            XCTAssertTrue(names.allSatisfy { !$0.hasPrefix(".louppe-write-") })
        }
    }

    func testBoundUpdateRetainsExternalPacketCAS() async throws {
        let folder = try fixture()
        let sidecar = folder.appendingPathComponent("PHOTO.xmp")
        let oldPacket = try XMPFieldMapping.merge(packet: nil, metadata: .init(decision: .no, stars: .one, colorLabel: nil, profile: .universal))
        try oldPacket.write(to: sidecar)
        let preparedPlan = try await plan(input([try item(folder.appendingPathComponent("PHOTO.NEF"))], folder: folder))
        let entry = try XCTUnwrap(preparedPlan.entries.first)
        let validation = try XCTUnwrap(entry.sourceValidation)
        let store = XMPMetadataStore()
        let prepared = try await store.prepareWrite(path: try XCTUnwrap(entry.canonicalSidecar), metadata: try XCTUnwrap(entry.metadata), sourceValidation: validation)
        let external = try XMPFieldMapping.merge(packet: nil, metadata: .init(decision: .undecided, stars: .two, colorLabel: nil, profile: .universal))
        do {
            _ = try await store.commit(prepared, sourceValidation: validation, testHooks: .init(beforeFinalValidation: { try external.write(to: sidecar) }))
            XCTFail("External packet edit must stop publication")
        } catch {
            guard let storeError = error as? XMPMetadataStore.StoreError, case .fileChanged = storeError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: sidecar), external)
    }

    func testTemporarySubstitutionAndInPlaceEditCannotReplaceOriginalPacket() async throws {
        for replacement in [true, false] {
            let folder = try fixture()
            let sidecar = folder.appendingPathComponent("PHOTO.xmp")
            let original = try XMPFieldMapping.merge(packet: nil, metadata: .init(decision: .no, stars: .one, colorLabel: nil, profile: .universal))
            try original.write(to: sidecar)
            let preparedPlan = try await plan(input([try item(folder.appendingPathComponent("PHOTO.NEF"))], folder: folder))
            let entry = try XCTUnwrap(preparedPlan.entries.first)
            let validation = try XCTUnwrap(entry.sourceValidation)
            let store = XMPMetadataStore()
            let prepared = try await store.prepareWrite(path: try XCTUnwrap(entry.canonicalSidecar), metadata: try XCTUnwrap(entry.metadata), sourceValidation: validation)
            let unrelated = Data("external temporary contents".utf8)
            do {
                _ = try await store.commit(prepared, sourceValidation: validation, testHooks: .init(beforeFinalValidation: {
                    let temporary = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".louppe-write-") })
                    if replacement {
                        try unrelated.write(to: temporary, options: .atomic)
                    } else {
                        try unrelated.write(to: temporary)
                    }
                }))
                XCTFail("An altered temporary must never replace the existing packet")
            } catch {
                XCTAssertTrue(error is DurableFileIO.DestinationChanged)
            }
            XCTAssertEqual(try Data(contentsOf: sidecar), original)
            let leftovers = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".louppe-write-") }
            if replacement {
                XCTAssertEqual(leftovers.count, 1, "an unowned replacement is preserved")
                XCTAssertEqual(try Data(contentsOf: XCTUnwrap(leftovers.first)), unrelated)
            } else {
                XCTAssertTrue(leftovers.isEmpty, "only Louppe's owned inode may be cleaned up")
            }
        }
    }

    func testAlreadyCurrentDoesNotClaimSuccessForReplacementMedia() async throws {
        let folder = try fixture()
        let media = folder.appendingPathComponent("PHOTO.NEF")
        let photo = try item(media)
        let initialPlan = try await plan(input([photo], folder: folder))
        let initialResult = await publish(initialPlan)
        XCTAssertEqual(initialResult.created, 1)
        let currentPlan = try await plan(input([photo], folder: folder))
        XCTAssertEqual(currentPlan.count(.alreadyCurrent), 1)
        let sidecar = folder.appendingPathComponent("PHOTO.xmp")
        let packet = try Data(contentsOf: sidecar)
        try Data("replacement".utf8).write(to: media, options: .atomic)
        let result = await publish(currentPlan)
        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(result.alreadyCurrent, 0)
        XCTAssertEqual(try Data(contentsOf: sidecar), packet)
    }

    func testMissingScanIdentityOrFolderAuthorityFailsClosed() async throws {
        let folder = try fixture()
        let media = folder.appendingPathComponent("PHOTO.NEF")
        let identityless = PhotoItem(primaryFile: PhotoFile(id: "PHOTO.NEF", url: media, captureDate: nil, cameraModel: nil, lensModel: nil, fileSize: 8, rating: .yes))
        let preparedPlan = try await plan(input([identityless], folder: folder))
        XCTAssertEqual(preparedPlan.count(.externalModificationConflict), 1)
        XCTAssertThrowsError(try XMPPublicationInput(items: [try item(media)], sourceFolder: folder, profile: .universal, visibleDecisionKeywords: false))
    }

    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("louppe-xmp-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: folder.appendingPathComponent("PHOTO.NEF"))
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func item(_ media: URL) throws -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(id: media.lastPathComponent, url: media, captureDate: nil, cameraModel: nil, lensModel: nil, fileSize: 8, scannedIdentity: try FileOperationJournal.captureIdentity(at: media), rating: .yes, starRating: .five, colorLabel: .red))
    }

    private func input(_ items: [PhotoItem], context: [PhotoItem]? = nil, folder: URL) throws -> XMPPublicationInput {
        try XMPPublicationInput(items: items, familyContextItems: context, sourceFolder: folder, sourceFolderIdentity: .capture(at: folder), profile: .universal, visibleDecisionKeywords: false)
    }

    private func plan(_ input: XMPPublicationInput) async throws -> XMPPublicationPlan {
        let result = await XMPPublicationPlanner.preflight(input, isCancelled: { false }, progress: { _, _ in })
        return try XCTUnwrap(result)
    }

    private func publish(_ plan: XMPPublicationPlan) async -> XMPPublicationResult {
        await XMPPublicationWorker.publish(plan, cancelFlag: .init(), progress: { _, _ in })
    }
}
