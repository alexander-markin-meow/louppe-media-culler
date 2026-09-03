import Foundation

/// Holds a sandbox extension for one user-selected folder. `NSOpenPanel` and
/// Finder drops grant short-lived access; keeping this token alive lets the
/// scanner, media readers, and journalled file operations finish safely.
@MainActor
final class SecurityScopedFolderAccess {
    let url: URL
    private var didStartAccess = false

    init(url: URL) {
        self.url = url.standardizedFileURL
        didStartAccess = self.url.startAccessingSecurityScopedResource()
    }

    func stop() {
        guard didStartAccess else { return }
        url.stopAccessingSecurityScopedResource()
        didStartAccess = false
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

/// Persists only the folders the photographer explicitly selected. The
/// fallback path preserves existing non-sandboxed recents and lets a person
/// select an older location again if macOS revokes a stale bookmark.
enum SecurityScopedFolderBookmarks {
    private static let recentsKey = "recentFolderBookmarks"
    private static let legacyPathsKey = "recentFolders"
    private static let recoveryDestinationsKey = "recoveryExportDestinations"

    private struct Entry: Codable {
        let path: String
        let bookmark: Data?
    }

    static func load(from defaults: UserDefaults = .standard) -> [URL] {
        let entries = storedEntries(forKey: recentsKey, from: defaults)
            ?? (defaults.stringArray(forKey: legacyPathsKey) ?? []).map {
                Entry(path: $0, bookmark: nil)
            }

        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let url = resolvedURL(for: entry),
                  seen.insert(url.path).inserted,
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return url
        }
    }

    static func save(_ urls: [URL], to defaults: UserDefaults = .standard) {
        store(entries(for: urls), forKey: recentsKey, to: defaults)
        // Keep the former key for a one-way, benign migration path in older
        // builds. Sandboxed builds use the bookmark representation above.
        defaults.set(urls.map(\.standardizedFileURL.path), forKey: legacyPathsKey)
    }

    /// The destination is retained only while a file-operation journal could
    /// need it after an interruption. A recovered or completed operation
    /// removes it immediately; this is not a general destination history.
    static func recordRecoveryDestination(
        _ url: URL,
        in defaults: UserDefaults = .standard
    ) {
        var urls = (storedEntries(forKey: recoveryDestinationsKey, from: defaults) ?? [])
            .compactMap(resolvedURL(for:))
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url.standardizedFileURL, at: 0)
        store(entries(for: urls), forKey: recoveryDestinationsKey, to: defaults)
    }

    @MainActor
    static func beginRecoveryDestinationAccesses(
        from defaults: UserDefaults = .standard
    ) -> [SecurityScopedFolderAccess] {
        (storedEntries(forKey: recoveryDestinationsKey, from: defaults) ?? [])
            .compactMap(resolvedURL(for:))
            .map(SecurityScopedFolderAccess.init(url:))
    }

    static func clearRecoveryDestinations(
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: recoveryDestinationsKey)
    }

    private static func entries(for urls: [URL]) -> [Entry] {
        var seen = Set<String>()
        return urls.compactMap { original -> Entry? in
            let url = original.standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return Entry(path: url.path, bookmark: bookmark)
        }
    }

    private static func storedEntries(
        forKey key: String,
        from defaults: UserDefaults
    ) -> [Entry]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([Entry].self, from: data)
    }

    private static func store(
        _ entries: [Entry],
        forKey key: String,
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func resolvedURL(for entry: Entry) -> URL? {
        let resolved: URL?
        if let bookmark = entry.bookmark {
            var isStale = false
            resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } else {
            resolved = URL(fileURLWithPath: entry.path)
        }
        return resolved?.standardizedFileURL
    }
}
