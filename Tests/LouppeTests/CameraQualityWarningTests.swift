import XCTest
@testable import Louppe

final class CameraQualityWarningTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CameraQualityWarningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testDefaultPreferencesAreSensibleAndEnabled() {
        let preferences = CameraQualityWarningPreferences.load(from: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(
            preferences.highISOThreshold,
            CameraQualityWarningPreferences.defaultHighISOThreshold
        )
        XCTAssertEqual(
            preferences.slowShutterThreshold,
            1.0 / 30.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            preferences.clippingPercentageThreshold,
            10
        )
    }

    func testCustomPreferencesPersistIndependently() {
        let saved = CameraQualityWarningPreferences(
            isEnabled: false,
            highISOThreshold: 3_200,
            slowShutterThreshold: 1.0 / 60.0,
            clippingPercentageThreshold: 5
        )

        saved.save(to: defaults)

        XCTAssertEqual(CameraQualityWarningPreferences.load(from: defaults), saved)
    }

    func testInvalidStoredThresholdsSafelyUseDefaults() {
        defaults.set(-1, forKey: CameraQualityWarningPreferences.Keys.highISOThreshold)
        defaults.set(0, forKey: CameraQualityWarningPreferences.Keys.slowShutterThreshold)
        defaults.set(101, forKey: CameraQualityWarningPreferences.Keys.clippingPercentageThreshold)

        let preferences = CameraQualityWarningPreferences.load(from: defaults)

        XCTAssertEqual(
            preferences.highISOThreshold,
            CameraQualityWarningPreferences.defaultHighISOThreshold
        )
        XCTAssertEqual(
            preferences.slowShutterThreshold,
            CameraQualityWarningPreferences.defaultSlowShutterThreshold,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            preferences.clippingPercentageThreshold,
            CameraQualityWarningPreferences.defaultClippingPercentageThreshold
        )
    }

    func testThresholdBoundariesProduceClearWarnings() {
        let item = photo(iso: 6_400, shutter: 1.0 / 30.0)
        let warnings = CameraQualityWarning.warnings(
            for: item,
            analysis: analysis(shadows: 10, highlights: 10),
            preferences: CameraQualityWarningPreferences()
        )

        XCTAssertEqual(
            warnings.map(\.kind),
            [.highISO, .slowShutter, .highlightClipping, .shadowClipping]
        )
        XCTAssertEqual(
            warnings[0].detail,
            "ISO 6400 (warning at ISO 6400 or above)"
        )
        XCTAssertEqual(
            warnings[1].detail,
            "1/30s (warning at 1/30s or slower)"
        )
        XCTAssertEqual(
            warnings[2].detail,
            "10% near white (warning at 10% or more)"
        )
        XCTAssertTrue(
            warnings[2].accessibilityLabel.contains("Rendered image estimate")
        )
        XCTAssertEqual(
            warnings[2].source,
            .histogram(.renderedPreview)
        )
    }

    func testCustomThresholdsAndMissingOrInvalidMetadataAreHandledSafely() {
        let preferences = CameraQualityWarningPreferences(
            highISOThreshold: 3_200,
            slowShutterThreshold: 1.0 / 60.0,
            clippingPercentageThreshold: 5
        )
        let belowThreshold = photo(iso: 3_199, shutter: 1.0 / 125.0)
        XCTAssertEqual(
            CameraQualityWarning.warnings(
                for: belowThreshold,
                analysis: analysis(shadows: 4, highlights: 5),
                preferences: preferences
            ).map(\.kind),
            [.highlightClipping]
        )

        let invalid = photo(iso: .nan, shutter: 0)
        XCTAssertTrue(
            CameraQualityWarning.warnings(
                for: invalid,
                analysis: nil,
                preferences: preferences
            ).isEmpty
        )
    }

    func testGroupedRawJPEGUsesDisplayedPrimaryPhoto() {
        let paired = PhotoItem(
            id: "capture.NEF",
            primaryURL: URL(fileURLWithPath: "/tmp/capture.NEF"),
            pairedURL: URL(fileURLWithPath: "/tmp/capture.JPG"),
            captureDate: nil,
            cameraModel: "Camera",
            lensModel: nil,
            shutterSpeed: 1.0 / 125.0,
            iso: 12_800,
            fileSize: 1,
            pairedFileSize: 1
        )

        let warnings = CameraQualityWarning.warnings(
            for: paired,
            analysis: analysis(shadows: 0, highlights: 0),
            preferences: CameraQualityWarningPreferences()
        )

        XCTAssertEqual(paired.fileTypeLabel, "RAW + JPEG")
        XCTAssertEqual(warnings.map(\.kind), [.highISO])
        XCTAssertEqual(warnings.first?.measuredValue, 12_800)
    }

    func testRawClippingUsesRawSourceWithoutDuplicateRenderedWarnings() {
        let warnings = CameraQualityWarning.warnings(
            for: photo(iso: nil, shutter: nil),
            analysis: analysis(shadows: 12, highlights: 15),
            analysisSource: .rawDecode,
            preferences: CameraQualityWarningPreferences()
        )

        XCTAssertEqual(
            warnings.map(\.kind),
            [.highlightClipping, .shadowClipping]
        )
        XCTAssertEqual(
            warnings.map(\.source),
            [.histogram(.rawDecode), .histogram(.rawDecode)]
        )
        XCTAssertTrue(
            warnings[0].accessibilityLabel.contains("scaled Core Image decode")
        )
    }

    func testVideoAndDisabledCuesStayNonBlocking() {
        let video = PhotoItem(
            id: "clip.MOV",
            primaryURL: URL(fileURLWithPath: "/tmp/clip.MOV"),
            pairedURL: nil,
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            shutterSpeed: 1,
            iso: 25_600,
            mediaKind: .video,
            duration: 1,
            videoIsPlayable: true,
            fileSize: 1
        )

        XCTAssertTrue(
            CameraQualityWarning.warnings(
                for: video,
                analysis: analysis(shadows: 100, highlights: 100),
                preferences: CameraQualityWarningPreferences()
            ).isEmpty
        )
        XCTAssertTrue(
            CameraQualityWarning.warnings(
                for: photo(iso: 25_600, shutter: 1),
                analysis: analysis(shadows: 100, highlights: 100),
                preferences: CameraQualityWarningPreferences(isEnabled: false)
            ).isEmpty
        )
    }

    private func photo(iso: Double?, shutter: Double?) -> PhotoItem {
        PhotoItem(
            id: "photo.JPG",
            primaryURL: URL(fileURLWithPath: "/tmp/photo.JPG"),
            pairedURL: nil,
            captureDate: nil,
            cameraModel: "Camera",
            lensModel: nil,
            shutterSpeed: shutter,
            iso: iso,
            fileSize: 1
        )
    }

    private func analysis(shadows: Int, highlights: Int) -> HistogramAnalysis {
        HistogramAnalysis(
            bins: Array(repeating: 0, count: 256),
            sampleCount: 100,
            shadowCount: shadows,
            highlightCount: highlights
        )
    }
}
