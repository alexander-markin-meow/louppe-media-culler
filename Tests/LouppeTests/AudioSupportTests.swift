import XCTest
@testable import Louppe

final class AudioSupportTests: XCTestCase {
    func testWAVScansAsPlayableAudioWithMetadata() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("RECORDING.WAV")
        try writeSilentWAV(to: url)

        let items = try FolderScanner.scan(folder) { _ in }
        let item = try XCTUnwrap(items.first)

        XCTAssertTrue(item.isAudio)
        XCTAssertTrue(item.audioIsPlayable)
        XCTAssertTrue(item.isSupported)
        XCTAssertFalse(item.hasVisualPreview)
        XCTAssertGreaterThanOrEqual(item.duration ?? 0, 1)
        XCTAssertNotNil(item.audioCodec)

        let fields = MetadataExtractor.fields(for: item)
        XCTAssertEqual(fields.first(where: { $0.label == "Duration" })?.value, "0:01")
        XCTAssertEqual(fields.first(where: { $0.label == "Codec" })?.value, item.audioCodec)
    }

    func testAudioSkipsVisualThumbnailPipeline() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("NO-THUMBNAIL.WAV")
        try writeSilentWAV(to: url)
        let item = try XCTUnwrap(
            try FolderScanner.scan(folder) { _ in }.first
        )

        let thumbnail = await ImagePipeline.shared.thumbnail(for: item)
        XCTAssertNil(thumbnail)
    }

    func testAudioLevelProcessorKeepsChannelsSeparate() throws {
        let analysis = try XCTUnwrap(
            AudioLevelProcessor.analyze(
                channels: [
                    [-0.25, 0, 0.5, .nan],
                    [0.8, -0.75, 0, 2],
                ],
                binCount: 4
            )
        )
        XCTAssertEqual(analysis.channels.count, 2)
        XCTAssertEqual(analysis.channels[0].peak, 0.5, accuracy: 0.0001)
        XCTAssertEqual(analysis.channels[1].peak, 1, accuracy: 0.0001)
        XCTAssertEqual(
            analysis.channels[0].samplePeakDecibels ?? 0,
            -6.0206,
            accuracy: 0.001
        )
        XCTAssertEqual(
            analysis.channels[0].loudnessDecibels(at: 0.5) ?? 0,
            -6.0206,
            accuracy: 0.001,
            "the live meter must read the RMS slice at playback position"
        )
        XCTAssertNil(analysis.channels[1].loudnessDecibels(at: 0.5))
        XCTAssertNil(
            AudioLevelProcessor.decibels(forSamplePeak: 0),
            "silence must not be presented as a finite dBFS value"
        )
    }

    func testAudioLevelPipelineReadsStereoWAVWithoutMixingDown() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("STEREO.WAV")
        try writeStereoWAV(to: url)
        let item = try XCTUnwrap(
            try FolderScanner.scan(folder) { _ in }.first
        )
        let bytesBefore = try Data(contentsOf: url)
        let modificationBefore = try XCTUnwrap(
            url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )

        let loaded = await AudioLevelPipeline.shared.analysis(for: item)
        let analysis = try XCTUnwrap(loaded)
        XCTAssertEqual(analysis.channels.count, 2)
        XCTAssertEqual(analysis.channels[0].peak, 0.25, accuracy: 0.03)
        XCTAssertEqual(analysis.channels[1].peak, 0.75, accuracy: 0.03)
        XCTAssertEqual(
            analysis.channels[0].envelope.first?.rootMeanSquare ?? 0,
            0.25,
            accuracy: 0.03
        )
        XCTAssertGreaterThan(
            analysis.channels[1].peak,
            analysis.channels[0].peak * 2,
            "the louder right channel must not be averaged into the left"
        )
        XCTAssertEqual(try Data(contentsOf: url), bytesBefore)
        XCTAssertEqual(
            try url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
            modificationBefore,
            "audio analysis must not modify the original recording"
        )
    }

    func testTemporalAnalysisUsesRealtimeSlicesWithinABoundedCacheSize() {
        XCTAssertEqual(AudioLevelProcessor.temporalBinCount(for: 1), 256)
        XCTAssertEqual(AudioLevelProcessor.temporalBinCount(for: 30), 600)
        XCTAssertEqual(AudioLevelProcessor.temporalBinCount(for: 10_000), 6_000)
        XCTAssertEqual(
            AudioLevelProcessor.temporalBinCount(for: nil),
            AudioLevelProcessor.defaultEnvelopeBinCount
        )
        XCTAssertEqual(
            AudioLevelPipeline.resultEnvelopeLimit,
            AudioLevelPipeline.resultCacheLimit * 2
                * AudioLevelProcessor.maximumTemporalBinCount
        )
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "louppe-audio-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
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

    private func writeStereoWAV(to url: URL) throws {
        let sampleRate: UInt32 = 8_000
        let frames: UInt32 = 8_000
        let channels: UInt16 = 2
        let bytesPerSample: UInt16 = 2
        let blockAlign = channels * bytesPerSample
        let dataByteCount = frames * UInt32(blockAlign)
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data) // PCM
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(blockAlign), to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataByteCount, to: &data)
        for _ in 0..<frames {
            appendLittleEndian(Int16(8_192), to: &data)  // left: 0.25
            appendLittleEndian(Int16(24_575), to: &data) // right: 0.75
        }
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
