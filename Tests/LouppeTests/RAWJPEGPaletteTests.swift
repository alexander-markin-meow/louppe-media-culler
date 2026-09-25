import AppKit
import Foundation
import XCTest
@testable import Louppe

@MainActor
final class RAWJPEGPaletteTests: XCTestCase {
    func testOneSearchableToggleChangesDirectionAfterPairing() async throws {
        let (store, folder) = try pairedStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(store.rawJPEGPairCount, 1)
        XCTAssertEqual(store.rawJPEGPairingMode, .separate)

        store.isActionPalettePresented = true
        let palette = ActionPaletteView(store: store)
        let action = try XCTUnwrap(palette.actions.first {
            $0.id == "toggle-raw-jpeg-pairing"
        })
        XCTAssertEqual(palette.actions.filter {
            $0.id == "toggle-raw-jpeg-pairing"
        }.count, 1)
        XCTAssertTrue(action.isEnabled, "The open palette itself must not block pairing")
        XCTAssertEqual(action.title, RawJPEGPairingMode.togetherControlTitle)
        for query in ["treat", "pair RAW JPEG", "separate RAW JPEG"] {
            XCTAssertEqual(
                ActionPaletteSearch.results(for: query, in: palette.actions)
                    .filter { $0.id == action.id }.count,
                1,
                "Expected one pairing action for \(query)"
            )
        }

        store.dismissActionPalette(then: action.perform)
        store.finishActionPaletteDismissal()
        XCTAssertEqual(store.rawJPEGPairingMode, .together)
        try await waitForPairingChange(store)

        let reverseAction = try XCTUnwrap(
            ActionPaletteView(store: store).actions.first { $0.id == action.id }
        )
        XCTAssertTrue(reverseAction.isEnabled)
        XCTAssertEqual(reverseAction.title, "Review RAW + JPEG Separately")
        reverseAction.perform()
        XCTAssertEqual(store.rawJPEGPairingMode, .separate)
        try await waitForPairingChange(store)
        XCTAssertEqual(store.rawJPEGPairCount, 1)
    }

    func testNoPairAndBusyReasonsMatchActualBarriers() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouppePaletteNoPair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let jpeg = folder.appendingPathComponent("ONLY.JPG")
        try Data("jpeg".utf8).write(to: jpeg)

        let store = SessionStore()
        store.items = [item("ONLY.JPG", at: jpeg)]
        store.phase = .ready
        store.rebuildDerivedDataForTesting(sourceFolder: folder)
        let palette = ActionPaletteView(store: store)
        let noPairAction = try XCTUnwrap(palette.actions.first {
            $0.id == "toggle-raw-jpeg-pairing"
        })
        XCTAssertFalse(noPairAction.isEnabled)
        XCTAssertEqual(
            palette.unavailableReason(for: noPairAction),
            "No matching RAW + JPEG pairs in this folder"
        )

        let (paired, pairFolder) = try pairedStore()
        defer { try? FileManager.default.removeItem(at: pairFolder) }
        XCTAssertTrue(paired.exportWillStart(mode: .copy))
        defer {
            paired.finishExport(
                mode: .copy,
                movedIDs: [],
                requiresRecovery: false
            )
        }
        let pairedPalette = ActionPaletteView(store: paired)
        let busyAction = try XCTUnwrap(pairedPalette.actions.first {
            $0.id == "toggle-raw-jpeg-pairing"
        })
        XCTAssertFalse(busyAction.isEnabled)
        XCTAssertEqual(
            pairedPalette.unavailableReason(for: busyAction),
            "Wait for the current file operation to finish"
        )
        busyAction.perform()
        XCTAssertEqual(paired.rawJPEGPairingMode, .separate)
    }

    private func pairedStore() throws -> (SessionStore, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouppePalettePair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let raw = folder.appendingPathComponent("PAIR.NEF")
        let jpeg = folder.appendingPathComponent("PAIR.JPG")
        try Data("raw".utf8).write(to: raw)
        try Data("jpeg".utf8).write(to: jpeg)

        let store = SessionStore()
        store.items = [item("PAIR.NEF", at: raw), item("PAIR.JPG", at: jpeg)]
        store.phase = .ready
        store.rebuildDerivedDataForTesting(sourceFolder: folder)
        return (store, folder)
    }

    private func item(_ id: String, at url: URL) -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: id,
            url: url,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 4
        ))
    }

    private func waitForPairingChange(_ store: SessionStore) async throws {
        for _ in 0..<100 {
            if !store.isChangingRawJPEGPairingMode { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Pairing projection did not finish")
    }
}
