import Foundation

/// App preferences never enter folder-bound session snapshots. UserDefaults
/// uses the current bundle's domain, keeping a separate review app isolated.
struct ReviewPreferences: Equatable, Sendable {
    enum Keys {
        static let advancesAfterDecision = "review.advancesAfterDecision"
        static let defaultSortKey = "review.defaultSortKey"
        static let defaultSortAscending = "review.defaultSortAscending"
        static let isGroupingEnabled = "review.defaultGroupingEnabled"
        static let defaultView = "review.defaultView"
    }

    var advancesAfterDecision = true
    var defaultSort = PhotoSort()
    var isGroupingEnabled = true
    var defaultView: ViewMode = .gallery

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            advancesAfterDecision: defaults.object(forKey: Keys.advancesAfterDecision) as? Bool ?? true,
            defaultSort: PhotoSort(
                key: defaults.string(forKey: Keys.defaultSortKey)
                    .flatMap(PhotoSort.Key.init(rawValue:)) ?? .captureDate,
                ascending: defaults.object(forKey: Keys.defaultSortAscending) as? Bool ?? true
            ),
            isGroupingEnabled: defaults.object(forKey: Keys.isGroupingEnabled) as? Bool ?? true,
            defaultView: defaults.string(forKey: Keys.defaultView)
                .flatMap(ViewMode.init(rawValue:)) ?? .gallery
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(advancesAfterDecision, forKey: Keys.advancesAfterDecision)
        defaults.set(defaultSort.key.rawValue, forKey: Keys.defaultSortKey)
        defaults.set(defaultSort.ascending, forKey: Keys.defaultSortAscending)
        defaults.set(isGroupingEnabled, forKey: Keys.isGroupingEnabled)
        defaults.set(defaultView.rawValue, forKey: Keys.defaultView)
    }
}

extension PhotoSort.Key {
    var preferenceTitle: String {
        switch self {
        case .captureDate: return "Date taken"
        case .name: return "Name"
        case .subfolder: return "Subfolder"
        case .folderHierarchy: return "Folder hierarchy"
        case .fileType: return "File type"
        case .mediaKind: return "Media type"
        case .camera: return "Camera"
        case .lens: return "Lens"
        case .aperture: return "Aperture"
        case .shutterSpeed: return "Shutter speed"
        case .iso: return "ISO"
        case .duration: return "Media duration"
        case .videoResolution: return "Video resolution"
        case .videoFrameRate: return "Video frame rate"
        case .videoCodec: return "Video codec"
        case .decision: return "Decision"
        case .starRating: return "Star rating"
        case .colorLabel: return "Color label"
        }
    }
}
