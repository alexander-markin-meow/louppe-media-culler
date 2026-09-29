import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Louppe

final class MediaRevisionTests: XCTestCase {
    func testColdMediaReadsRejectSamePathReplacementAndRescanLoadsCurrentPixels() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("photo.png")
        try writePNG(gray: 0, to: url)
        let original = try item(at: url)
        let replacement = folder.appendingPathComponent("replacement.png")
        try writePNG(gray: 255, to: replacement)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        XCTAssertFalse(MediaSourceRevision(original).matchesCurrentFile())
        let pipeline = ImagePipeline(testingDiskCacheRoot: folder.appendingPathComponent("cache"))
        let oldThumbnail = await pipeline.thumbnail(for: original)
        let oldFull = await pipeline.fullImage(for: original)
        let oldHistogram = await HistogramPipeline.shared.analysis(for: original)
        let oldSource = await HighResolutionImagePipeline.shared.source(for: original)
        XCTAssertNil(oldThumbnail)
        XCTAssertNil(oldFull)
        XCTAssertNil(oldHistogram)
        XCTAssertNil(oldSource)
        XCTAssertNil(pipeline.cachedThumbnail(for: original))
        XCTAssertEqual(MetadataExtractor.fields(for: original).last?.label, "File changed")
        await pipeline.waitForPendingDiskWrites()
        let disk = folder.appendingPathComponent("cache").appendingPathComponent(
            ImagePipeline.diskFileName(for: ImagePipeline.cacheKey(for: original)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.path))

        let current = try item(at: url)
        XCTAssertNotEqual(original.contentRevision, current.contentRevision)
        let newThumbnail = await pipeline.thumbnail(for: current)
        let newFull = await pipeline.fullImage(for: current)
        let newHistogram = await HistogramPipeline.shared.analysis(for: current)
        XCTAssertNotNil(newThumbnail)
        XCTAssertNotNil(newFull)
        XCTAssertEqual(newHistogram?.highlightPercentage, 100)
        await pipeline.waitForPendingDiskWrites()
    }

    func testAlreadyValidatedMemoryCacheHitsSurviveSourceRemoval() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("warm.png")
        try writePNG(gray: 0, to: url)
        let original = try item(at: url)
        let pipeline = ImagePipeline(testingDiskCacheRoot: folder.appendingPathComponent("cache"))
        let thumbnail = await pipeline.thumbnail(for: original)
        let full = await pipeline.fullImage(for: original)
        let histogram = await HistogramPipeline.shared.analysis(for: original)
        XCTAssertNotNil(thumbnail)
        XCTAssertNotNil(full)
        XCTAssertNotNil(histogram)
        try FileManager.default.removeItem(at: url)
        let cachedThumbnail = await pipeline.thumbnail(for: original)
        let cachedFull = await pipeline.fullImage(for: original)
        let cachedHistogram = await HistogramPipeline.shared.analysis(for: original)
        XCTAssertTrue(cachedThumbnail === thumbnail)
        XCTAssertTrue(cachedFull === full)
        XCTAssertEqual(cachedHistogram?.shadowCount, histogram?.shadowCount)
        await pipeline.waitForPendingDiskWrites()
    }

    func testCachedLazyZoomRecipeRejectsNewTileAfterReplacement() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("lazy.png")
        try writePNG(gray: 0, to: url)
        let original = try item(at: url)
        let loaded = await HighResolutionImagePipeline.shared.source(for: original)
        let source = try XCTUnwrap(loaded)
        let replacement = folder.appendingPathComponent("replacement.png")
        try writePNG(gray: 255, to: replacement)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        let tile = await HighResolutionImagePipeline.shared.tile(
            for: source, coordinate: ZoomTileCoordinate(column: 0, row: 0))
        XCTAssertNil(tile, "lazy rendering must not cache replacement pixels under the old recipe")
    }

    func testSourceRevisionRejectsSymlinkAndInPlaceEditAndChecksAfterRead() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("photo.png")
        let target = folder.appendingPathComponent("target.png")
        try writePNG(gray: 0, to: url)
        try writePNG(gray: 255, to: target)
        let original = try item(at: url)
        let revision = MediaSourceRevision(original)
        XCTAssertTrue(revision.matchesCurrentFile())
        let result: Int? = revision.read {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            return 7
        }
        XCTAssertNil(result, "identity must be checked again before publishing a read result")
        XCTAssertFalse(revision.matchesCurrentFile())
        try FileManager.default.removeItem(at: url)
        try writePNG(gray: 0, to: url)
        let rewritten = MediaSourceRevision(try item(at: url))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        XCTAssertFalse(rewritten.matchesCurrentFile(), "same inode edits also change content revision")
    }

    func testRawAndAudioDecodersRejectReplacementBeforeRunningAndAfterRead() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rawURL = folder.appendingPathComponent("photo.NEF")
        try Data("original".utf8).write(to: rawURL)
        let raw = try item(at: rawURL)
        let replacement = folder.appendingPathComponent("other")
        try Data("replaced".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: rawURL)
        try FileManager.default.moveItem(at: replacement, to: rawURL)
        let rawCalls = LockedCount()
        let rawPipeline = RawHistogramPipeline(delayNanoseconds: 0) { _ in
            rawCalls.increment()
            return HistogramAnalysis(bins: Array(repeating: 0, count: 256),
                                     sampleCount: 1, shadowCount: 0, highlightCount: 0)
        }
        let staleRaw = await rawPipeline.analysis(for: raw)
        XCTAssertNil(staleRaw)
        XCTAssertEqual(rawCalls.value, 0)

        let audioURL = folder.appendingPathComponent("audio.wav")
        try Data("original".utf8).write(to: audioURL)
        let audio = try item(at: audioURL, kind: .audio)
        let audioCalls = LockedCount()
        let audioPipeline = AudioLevelPipeline { url, _, _ in
            audioCalls.increment()
            try? Data("replacement bytes".utf8).write(to: url, options: .atomic)
            return AudioLevelProcessor.analyze(channels: [[0.5]], binCount: 1)
        }
        let changedAudio = await audioPipeline.analysis(for: audio)
        XCTAssertNil(changedAudio)
        let secondAudio = await audioPipeline.analysis(for: audio)
        XCTAssertNil(secondAudio)
        XCTAssertEqual(audioCalls.value, 1, "a stale result must not be cached, nor decoded again")
    }

    @MainActor
    func testPlayerPreparationRejectsReplacementAndSymlinkButAcceptsMatchingIdentity() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clip.mov")
        try Data("original".utf8).write(to: url)
        let original = try item(at: url, kind: .video)
        let controller = VideoPlaybackController()
        controller.prepare(original)
        XCTAssertNotNil(controller.player.currentItem)
        controller.stop()
        let replacement = folder.appendingPathComponent("replacement.mov")
        try Data("replaced".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        controller.prepare(original)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(controller.errorMessage, MediaSourceRevision.changedMessage)
        let fresh = try item(at: url, kind: .video)
        controller.prepare(fresh)
        XCTAssertNotNil(controller.player.currentItem)
        controller.stop()
        let moved = folder.appendingPathComponent("moved.mov")
        try FileManager.default.moveItem(at: url, to: moved)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: moved)
        controller.prepare(fresh)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(controller.errorMessage, MediaSourceRevision.changedMessage)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("louppe-media-revision-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(at url: URL, kind: MediaKind = .photo) throws -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: url.lastPathComponent, url: url, captureDate: nil, cameraModel: nil,
            lensModel: nil, mediaKind: kind, duration: kind == .audio ? 1 : nil,
            videoIsPlayable: kind == .video, audioIsPlayable: kind == .audio,
            fileSize: 8, scannedIdentity: try FileOperationJournal.captureIdentity(at: url)))
    }

    private func writePNG(gray: UInt8, to url: URL) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data([gray, gray, gray, 255]) as CFData))
        let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
