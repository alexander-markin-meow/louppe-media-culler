import AVKit
import XCTest
@testable import Louppe

@MainActor
final class VideoPlayerViewTests: XCTestCase {
    func testGalleryVideoSurfaceUsesFittedPlayerLayerAboveClearBackground() {
        let view = GalleryVideoSurfaceView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 800)
        )
        let player = AVPlayer()

        view.configure(
            player: player,
            presentationSize: CGSize(width: 16, height: 9)
        )
        view.layout()

        XCTAssertTrue(view.playerLayer.player === player)
        XCTAssertTrue(view.wantsLayer)
        XCTAssertTrue(view.layer?.masksToBounds == true)
        XCTAssertEqual(
            view.layer?.backgroundColor,
            NSColor.clear.cgColor
        )
        XCTAssertEqual(view.presentationSize, CGSize(width: 16, height: 9))
        XCTAssertEqual(view.playerLayer.frame, CGRect(x: 0, y: 175, width: 800, height: 450))
        XCTAssertEqual(view.playerLayer.videoGravity, .resizeAspectFill)
    }

    func testNativeAudioPlayerKeepsStableInlineControls() {
        let view = AVPlayerView()
        let player = AVPlayer()

        NativeVideoPlayer.configure(view, player: player, controls: .audio)
        XCTAssertTrue(view.player === player)
        XCTAssertEqual(view.controlsStyle, .inline)
        XCTAssertFalse(view.showsFullScreenToggleButton)
        XCTAssertFalse(view.showsFrameSteppingButtons)
        XCTAssertFalse(view.allowsPictureInPicturePlayback)

        NativeVideoPlayer.configure(view, player: player, controls: .audio)
        XCTAssertTrue(view.player === player)
        XCTAssertEqual(view.controlsStyle, .inline)
    }

    func testGalleryVideoAspectFitLeavesLetterboxAreaForAppBackground() {
        XCTAssertEqual(
            GalleryVideoSurfaceView.aspectFitRect(
                CGSize(width: 16, height: 9),
                in: CGRect(x: 0, y: 0, width: 800, height: 800)
            ),
            CGRect(x: 0, y: 175, width: 800, height: 450)
        )
        XCTAssertEqual(
            GalleryVideoSurfaceView.aspectFitRect(
                CGSize(width: 9, height: 16),
                in: CGRect(x: 0, y: 0, width: 800, height: 450)
            ),
            CGRect(x: 273.4375, y: 0, width: 253.125, height: 450)
        )
    }

    func testSeekTargetUsesHalfSecondStepsAndClampsToVideoBounds() {
        XCTAssertEqual(
            VideoPlaybackController.seekTarget(
                from: 1.25,
                by: 0.5,
                duration: 2
            ),
            1.75,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            VideoPlaybackController.seekTarget(
                from: 0.2,
                by: -0.5,
                duration: 2
            ),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            VideoPlaybackController.seekTarget(
                from: 1.9,
                by: 0.5,
                duration: 2
            ),
            2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            VideoPlaybackController.seekTarget(
                from: .infinity,
                by: 0.5,
                duration: nil
            ),
            0.5,
            accuracy: 0.000_001
        )
    }

    func testGalleryScrubberSeeksToAbsoluteClampedTime() {
        let item = makeVideoItem(
            at: URL(fileURLWithPath: "/tmp/SCRUB.MOV"),
            modificationDate: Date(timeIntervalSince1970: 1),
            duration: 8
        )
        let controller = VideoPlaybackController()

        XCTAssertTrue(controller.seek(item, to: 3.25))
        XCTAssertEqual(controller.currentTimeSeconds, 3.25, accuracy: 0.000_001)
        XCTAssertEqual(controller.rememberedPosition(for: item), 3.25)

        XCTAssertTrue(controller.seek(item, to: 20))
        XCTAssertEqual(controller.currentTimeSeconds, 8, accuracy: 0.000_001)
        XCTAssertNil(controller.rememberedPosition(for: item))
    }

    func testResumePositionIsStableAcrossItemNavigationAndClearsPerFolder() {
        let first = makeVideoItem(
            at: URL(fileURLWithPath: "/tmp/RESUME-A.MOV"),
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        let second = makeVideoItem(
            at: URL(fileURLWithPath: "/tmp/RESUME-B.MOV"),
            modificationDate: Date(timeIntervalSince1970: 2)
        )
        let controller = VideoPlaybackController()

        XCTAssertTrue(controller.seek(first, by: 5))
        XCTAssertEqual(
            controller.rememberedPosition(for: first),
            5
        )
        controller.prepare(second)
        XCTAssertEqual(
            controller.rememberedPosition(for: first),
            5,
            "changing item must not discard the position just sought"
        )
        controller.resetRememberedPositions()
        XCTAssertNil(
            controller.rememberedPosition(for: first),
            "a new folder starts a fresh review session"
        )
    }

    func testPlaybackRateUsesOnlyTheSupportedMediaChoices() {
        let controller = VideoPlaybackController()
        controller.setPlaybackRate(2.5)
        XCTAssertEqual(controller.playbackRate, 2.5)
        controller.setPlaybackRate(1.25)
        XCTAssertEqual(
            controller.playbackRate,
            2.5,
            "an unsupported playback rate must not leave the documented choices"
        )

        controller.synchronizePlaybackRate(with: 2)
        XCTAssertEqual(
            controller.playbackRate,
            2,
            "native AVPlayerView speed changes must update the Info selection"
        )
        XCTAssertTrue(controller.adjustPlaybackRate(forward: false))
        XCTAssertEqual(controller.playbackRate, 1.5)
    }

    func testPlaybackRateStaysSharedAcrossVideoAndAudio() {
        let controller = VideoPlaybackController()
        let video = makeVideoItem(
            at: URL(fileURLWithPath: "/tmp/SPEED.MOV"),
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        let audio = makeAudioItem(
            at: URL(fileURLWithPath: "/tmp/SPEED.WAV"),
            modificationDate: Date(timeIntervalSince1970: 2)
        )

        controller.setPlaybackRate(2.5)
        controller.prepare(video)
        XCTAssertEqual(controller.player.defaultRate, 2.5)

        controller.prepare(audio)
        XCTAssertEqual(
            controller.player.defaultRate,
            2.5,
            "AVKit's native Play button must use the shared playback speed"
        )

        controller.setPlaybackRate(2)
        XCTAssertEqual(controller.playbackRate, 2)
        XCTAssertEqual(
            controller.player.defaultRate,
            2,
            "changing the shared preference must update active audio"
        )

        controller.prepare(video)
        XCTAssertEqual(
            controller.player.defaultRate,
            2,
            "returning to video must retain the shared playback speed"
        )
    }

    func testCurrentAudioFailurePublishesItsPlaybackError() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "louppe-audio-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("AUDIO.wav")
        try writeSilentWAV(to: url)
        let item = makeAudioItem(
            at: url,
            modificationDate: try XCTUnwrap(
                url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            )
        )
        let controller = VideoPlaybackController()
        controller.prepare(item)
        let playerItem = try XCTUnwrap(controller.player.currentItem)

        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            userInfo: [
                AVPlayerItemFailedToPlayToEndTimeErrorKey:
                    NSError(
                        domain: "LouppeTests.AudioPlayback",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Audio failed"]
                    ),
            ]
        )
        await Task.yield()

        XCTAssertEqual(controller.errorMessage, "Audio failed")
        XCTAssertTrue(controller.represents(item))
    }

    func testControllerReplacesSameIDPhysicalVideoReplacement() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "louppe-video-replacement-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("SAME.MOV")
        let fixedDate = Date(timeIntervalSince1970: 1_650_000_000)
        try Data("first".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: url.path
        )
        let first = makeVideoItem(at: url, modificationDate: fixedDate)
        let controller = VideoPlaybackController()
        controller.prepare(first)
        let firstPlayerItem = try XCTUnwrap(controller.player.currentItem)

        try Data("other".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: url.path
        )
        let replacement = makeVideoItem(
            at: url,
            modificationDate: fixedDate
        )
        XCTAssertEqual(first.id, replacement.id)
        XCTAssertNotEqual(first.contentRevision, replacement.contentRevision)

        controller.prepare(replacement)
        let replacementPlayerItem = try XCTUnwrap(
            controller.player.currentItem
        )
        XCTAssertFalse(firstPlayerItem === replacementPlayerItem)
        XCTAssertFalse(controller.represents(first))
        XCTAssertTrue(controller.represents(replacement))
        controller.stop()
    }

    func testDelayedFirstAFailureCannotPoisonReplacementA() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "louppe-video-aba-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let aURL = folder.appendingPathComponent("A.wav")
        let bURL = folder.appendingPathComponent("B.wav")
        try writeSilentWAV(to: aURL)
        try writeSilentWAV(to: bURL)
        let a = makeVideoItem(
            at: aURL,
            modificationDate: try XCTUnwrap(
                aURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
            )
        )
        let b = makeVideoItem(
            at: bURL,
            modificationDate: try XCTUnwrap(
                bURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
            )
        )
        let controller = VideoPlaybackController()
        controller.prepare(a)
        let firstAPlayerItem = try XCTUnwrap(controller.player.currentItem)

        // Posting on the main queue invokes the observer now, but its
        // main-actor Task cannot run until this test yields. Recreate the same
        // A revision before that happens to exercise the A → B → A hazard.
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: firstAPlayerItem,
            userInfo: [
                AVPlayerItemFailedToPlayToEndTimeErrorKey:
                    NSError(
                        domain: "LouppeTests.StalePlayer",
                        code: 1
                    ),
            ]
        )
        controller.prepare(b)
        controller.prepare(a)
        XCTAssertNil(controller.errorMessage)

        await Task.yield()

        XCTAssertNil(
            controller.errorMessage,
            "a queued failure from the first A must not poison the new A item"
        )
        controller.stop()
    }

    func testStartingFileOperationStopsActivePlayback() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "louppe-video-operation-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ACTIVE.wav")
        try writeSilentWAV(to: url)
        let item = makeVideoItem(
            at: url,
            modificationDate: try XCTUnwrap(
                url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
            )
        )
        let store = SessionStore()
        store.items = [item]
        store.phase = .ready
        store.videoPlayback.prepare(item)
        XCTAssertNotNil(store.videoPlayback.player.currentItem)

        XCTAssertTrue(store.exportWillStart(mode: .copy))

        XCTAssertNil(store.videoPlayback.player.currentItem)
        XCTAssertNil(store.videoPlayback.itemID)
        store.finishExport(
            mode: .copy,
            movedIDs: [],
            requiresRecovery: false
        )
    }

    private func makeVideoItem(
        at url: URL,
        modificationDate: Date,
        duration: TimeInterval? = nil
    ) -> PhotoItem {
        PhotoItem(
            id: url.lastPathComponent,
            primaryURL: url,
            pairedURL: nil,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            mediaKind: .video,
            duration: duration,
            videoIsPlayable: true,
            primaryModificationDate: modificationDate,
            fileSize: 5
        )
    }

    private func makeAudioItem(
        at url: URL,
        modificationDate: Date
    ) -> PhotoItem {
        PhotoItem(
            id: url.lastPathComponent,
            primaryURL: url,
            pairedURL: nil,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            mediaKind: .audio,
            audioIsPlayable: true,
            primaryModificationDate: modificationDate,
            fileSize: 5
        )
    }

    private func writeSilentWAV(to url: URL) throws {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 8_000
        let bytesPerSample: UInt16 = 2
        let dataByteCount = sampleCount * UInt32(bytesPerSample)
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data) // PCM
        appendLittleEndian(UInt16(1), to: &data) // mono
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(bytesPerSample), to: &data)
        appendLittleEndian(bytesPerSample, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataByteCount, to: &data)
        data.append(Data(count: Int(dataByteCount)))
        try data.write(to: url, options: .atomic)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
