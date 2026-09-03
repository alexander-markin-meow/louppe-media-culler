import Foundation

/// Per-app preferences for optional camera-quality cues. These live
/// in UserDefaults, deliberately separate from the folder-bound review
/// session, so changing a threshold never writes a sidecar or affects a photo.
struct CameraQualityWarningPreferences: Equatable, Sendable {
    enum Keys {
        static let isEnabled = "cameraQualityWarnings.isEnabled"
        static let highISOThreshold = "cameraQualityWarnings.highISOThreshold"
        static let slowShutterThreshold = "cameraQualityWarnings.slowShutterThreshold"
        static let clippingPercentageThreshold = "cameraQualityWarnings.clippingPercentageThreshold"
    }

    static let defaultHighISOThreshold = 6_400.0
    static let defaultSlowShutterThreshold = 1.0 / 30.0
    static let defaultClippingPercentageThreshold = 10.0

    /// The intentionally short native menus in Settings. These cover common
    /// hand-held and low-light review choices without turning Preferences into
    /// a camera-profile editor.
    static let highISOThresholdOptions: [Double] = [800, 1_600, 3_200, 6_400, 12_800, 25_600]
    static let slowShutterThresholdOptions: [Double] = [1.0 / 125.0, 1.0 / 60.0, 1.0 / 30.0, 1.0 / 15.0, 1.0 / 8.0, 1]
    static let clippingPercentageThresholdOptions: [Double] = [5, 10, 20, 30]

    var isEnabled: Bool
    var highISOThreshold: Double
    var slowShutterThreshold: Double
    var clippingPercentageThreshold: Double

    init(
        isEnabled: Bool = true,
        highISOThreshold: Double = Self.defaultHighISOThreshold,
        slowShutterThreshold: Double = Self.defaultSlowShutterThreshold,
        clippingPercentageThreshold: Double = Self.defaultClippingPercentageThreshold
    ) {
        self.isEnabled = isEnabled
        self.highISOThreshold = Self.validISOThreshold(highISOThreshold)
        self.slowShutterThreshold = Self.validSlowShutterThreshold(
            slowShutterThreshold
        )
        self.clippingPercentageThreshold = Self.validClippingThreshold(
            clippingPercentageThreshold
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            isEnabled: bool(
                for: Keys.isEnabled,
                in: defaults,
                fallback: true
            ),
            highISOThreshold: double(
                for: Keys.highISOThreshold,
                in: defaults,
                fallback: defaultHighISOThreshold
            ),
            slowShutterThreshold: double(
                for: Keys.slowShutterThreshold,
                in: defaults,
                fallback: defaultSlowShutterThreshold
            ),
            clippingPercentageThreshold: double(
                for: Keys.clippingPercentageThreshold,
                in: defaults,
                fallback: defaultClippingPercentageThreshold
            )
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(highISOThreshold, forKey: Keys.highISOThreshold)
        defaults.set(slowShutterThreshold, forKey: Keys.slowShutterThreshold)
        defaults.set(
            clippingPercentageThreshold,
            forKey: Keys.clippingPercentageThreshold
        )
    }

    private static func bool(
        for key: String,
        in defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func double(
        for key: String,
        in defaults: UserDefaults,
        fallback: Double
    ) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func validISOThreshold(_ value: Double) -> Double {
        guard let value = MediaNumeric.iso(value), (100...1_000_000).contains(value)
        else { return defaultHighISOThreshold }
        return value
    }

    private static func validSlowShutterThreshold(_ value: Double) -> Double {
        guard let value = MediaNumeric.shutterSpeed(value),
              ((1.0 / 8_000.0)...60).contains(value)
        else { return defaultSlowShutterThreshold }
        return value
    }

    private static func validClippingThreshold(_ value: Double) -> Double {
        guard value.isFinite, (0.1...100).contains(value)
        else { return defaultClippingPercentageThreshold }
        return value
    }
}

/// One non-blocking cue in the Info panel. The cue describes a review
/// condition; it never changes review metadata or makes a quality verdict.
struct CameraQualityWarning: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case highISO
        case slowShutter
        case highlightClipping
        case shadowClipping
    }

    static let renderedClippingSourceDescription =
        "Rendered image estimate — measured from the displayed preview."
    static let rawClippingSourceDescription =
        "RAW decode — measured from a scaled Core Image decode of RAW sensor data, not a camera-maker per-photosite histogram."
    static let clippingSettingsDescription =
        "Clipping cues use a scaled Core Image RAW decode when supported, with a rendered image estimate as the fallback. The RAW result is not a camera-maker per-photosite histogram."

    let kind: Kind
    let measuredValue: Double
    let threshold: Double
    let source: Source

    enum Source: Equatable, Sendable {
        case cameraMetadata
        case histogram(HistogramAnalysisSource)

        var label: String {
            switch self {
            case .cameraMetadata: return "Camera metadata"
            case .histogram(let source): return source.detailLabel
            }
        }

        var description: String {
            switch self {
            case .cameraMetadata:
                return "Camera metadata"
            case .histogram(.renderedPreview):
                return CameraQualityWarning.renderedClippingSourceDescription
            case .histogram(.rawDecode):
                return CameraQualityWarning.rawClippingSourceDescription
            }
        }
    }

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .highISO: return "High ISO"
        case .slowShutter: return "Slow shutter"
        case .highlightClipping: return "Highlight clipping"
        case .shadowClipping: return "Shadow clipping"
        }
    }

    var detail: String {
        switch kind {
        case .highISO:
            return "ISO \(Self.iso(measuredValue)) (warning at ISO \(Self.iso(threshold)) or above)"
        case .slowShutter:
            return "\(Self.shutter(measuredValue)) (warning at \(Self.shutter(threshold)) or slower)"
        case .highlightClipping:
            return "\(Self.percentage(measuredValue)) near white (warning at \(Self.percentage(threshold)) or more)"
        case .shadowClipping:
            return "\(Self.percentage(measuredValue)) near black (warning at \(Self.percentage(threshold)) or more)"
        }
    }

    var accessibilityLabel: String {
        "\(title). \(detail). Source: \(source.description). Review cue only."
    }

    static func warnings(
        for item: PhotoItem,
        analysis: HistogramAnalysis?,
        analysisSource: HistogramAnalysisSource = .renderedPreview,
        preferences: CameraQualityWarningPreferences
    ) -> [Self] {
        guard preferences.isEnabled, item.mediaKind == .photo else { return [] }
        var warnings: [Self] = []

        // A paired projection has one displayed primary file (the RAW when an
        // unambiguous RAW+JPEG match is grouped). Its metadata and its
        // content-keyed luminance analysis are the only correct source here.
        if let iso = MediaNumeric.iso(item.iso), iso >= preferences.highISOThreshold {
            warnings.append(
                Self(
                    kind: .highISO,
                    measuredValue: iso,
                    threshold: preferences.highISOThreshold,
                    source: .cameraMetadata
                )
            )
        }
        if let shutter = MediaNumeric.shutterSpeed(item.shutterSpeed),
           shutter >= preferences.slowShutterThreshold {
            warnings.append(
                Self(
                    kind: .slowShutter,
                    measuredValue: shutter,
                    threshold: preferences.slowShutterThreshold,
                    source: .cameraMetadata
                )
            )
        }
        if let analysis {
            if analysis.highlightPercentage >= preferences.clippingPercentageThreshold {
                warnings.append(
                    Self(
                        kind: .highlightClipping,
                        measuredValue: analysis.highlightPercentage,
                        threshold: preferences.clippingPercentageThreshold,
                        source: .histogram(analysisSource)
                    )
                )
            }
            if analysis.shadowPercentage >= preferences.clippingPercentageThreshold {
                warnings.append(
                    Self(
                        kind: .shadowClipping,
                        measuredValue: analysis.shadowPercentage,
                        threshold: preferences.clippingPercentageThreshold,
                        source: .histogram(analysisSource)
                    )
                )
            }
        }
        return warnings
    }

    private static func iso(_ value: Double) -> String {
        MetadataFormat.iso(value)
    }

    private static func shutter(_ value: Double) -> String {
        let formatted = MetadataFormat.shutter(value)
        return formatted.hasSuffix("s") ? formatted : "\(formatted)s"
    }

    private static func percentage(_ value: Double) -> String {
        if value == 0 { return "0%" }
        if value < 0.1 { return "<0.1%" }
        if value < 10 { return String(format: "%.1f%%", value) }
        return String(format: "%.0f%%", value)
    }
}
