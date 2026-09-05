import Darwin
import Foundation

struct SourceOrganizationProgress: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case organizing
        case restoring
    }

    let action: Action
    let done: Int
    let total: Int

    var title: String {
        action == .organizing
            ? "Organizing source folder…"
            : "Restoring previous folders…"
    }
}

struct SourceOrganizationOutcome: Equatable, Sendable {
    let movedFiles: Int
    let failedItems: Int
    let message: String?
    let wasUndo: Bool

    var succeeded: Bool { failedItems == 0 && message == nil }
}

struct SourceOrganizationPlanningSnapshot: Sendable {
    let sourceFolder: URL
    let selectedItems: [PhotoItem]
    let familyContextItems: [PhotoItem]
    let knownOriginFolderPathBytesByFileID: [String: Data]
}

final class SourceOrganizationPlanningCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

enum SourceOrganizationScope: String, CaseIterable, Hashable, Sendable {
    case all
    case filtered
    case selected

    var label: String {
        switch self {
        case .all: return "All Media"
        case .filtered: return "Filtered"
        case .selected: return "Selected"
        }
    }
}

enum SourceOrganizationLevelKind: String, CaseIterable, Codable, Hashable,
    Identifiable, Sendable {
    case existingFolder
    case decision
    case dateTaken
    case starRating
    case colorLabel
    case camera
    case lens
    case fileType
    case mediaType

    var id: Self { self }

    var label: String {
        switch self {
        case .existingFolder: return "Existing folder"
        case .decision: return "Decision"
        case .dateTaken: return "Date taken"
        case .starRating: return "Star rating"
        case .colorLabel: return "Color label"
        case .camera: return "Camera"
        case .lens: return "Lens"
        case .fileType: return "File type"
        case .mediaType: return "Media type"
        }
    }

    var isAdditionalMetadata: Bool {
        switch self {
        case .camera, .lens, .fileType, .mediaType: return true
        default: return false
        }
    }
}

struct SourceOrganizationLevel: Codable, Equatable, Hashable, Identifiable,
    Sendable {
    let kind: SourceOrganizationLevelKind
    var isEnabled: Bool
    var id: SourceOrganizationLevelKind { kind }
}

enum SourceOrganizationDateGranularity: String, CaseIterable, Codable,
    Hashable, Sendable {
    case day
    case month
    case year

    var label: String {
        switch self {
        case .day: return "Full date"
        case .month: return "Year and month"
        case .year: return "Year"
        }
    }
}

enum SourceOrganizationExistingFolderDepth: String, CaseIterable, Codable,
    Hashable, Sendable {
    case topLevel
    case fullPath

    var label: String {
        switch self {
        case .topLevel: return "Top level"
        case .fullPath: return "Full path"
        }
    }
}

struct SourceOrganizationConfiguration: Equatable, Sendable {
    var levels: [SourceOrganizationLevel]
    var dateGranularity: SourceOrganizationDateGranularity
    var existingFolderDepth: SourceOrganizationExistingFolderDepth
    var containerName: String

    static func initial(hasMultipleTopLevelFolders: Bool) -> Self {
        Self(
            levels: [
                SourceOrganizationLevel(
                    kind: .existingFolder,
                    isEnabled: hasMultipleTopLevelFolders
                ),
                SourceOrganizationLevel(kind: .decision, isEnabled: true),
                SourceOrganizationLevel(kind: .dateTaken, isEnabled: true),
                SourceOrganizationLevel(kind: .starRating, isEnabled: false),
                SourceOrganizationLevel(kind: .colorLabel, isEnabled: false),
            ],
            dateGranularity: .day,
            existingFolderDepth: .topLevel,
            containerName: "Organized"
        )
    }

    static var dateTakenOnly: Self {
        Self(
            levels: [
                SourceOrganizationLevel(
                    kind: .existingFolder,
                    isEnabled: false
                ),
                SourceOrganizationLevel(kind: .decision, isEnabled: false),
                SourceOrganizationLevel(kind: .dateTaken, isEnabled: true),
                SourceOrganizationLevel(
                    kind: .starRating,
                    isEnabled: false
                ),
                SourceOrganizationLevel(
                    kind: .colorLabel,
                    isEnabled: false
                ),
            ],
            dateGranularity: .day,
            existingFolderDepth: .topLevel,
            containerName: "Organized"
        )
    }

    var enabledLevels: [SourceOrganizationLevel] {
        levels.filter(\.isEnabled)
    }
}

struct SourceOrganizationCollision: Identifiable, Equatable, Sendable {
    let id: String
    let destination: URL
    let sources: [URL]
    let message: String
}

struct SourceOrganizationPreviewGroup: Identifiable, Equatable, Sendable {
    let path: String
    let itemCount: Int
    let mediaFileCount: Int
    var id: String { path }
}

struct SourceOrganizationFileMapping: Equatable, Sendable {
    let itemID: String
    let source: URL
    let destination: URL
    let isMedia: Bool
}

struct SourceOrganizationPlan: Sendable {
    let sourceFolder: URL
    let sourceFolderIdentity: SessionPersistence.SourceFolderIdentity
    let storageSafety: SourceOrganizationStorageSafety
    let configuration: SourceOrganizationConfiguration
    let sourceItems: [PhotoItem]
    let workerPlan: ExportWorker.Plan
    let destinationDirectories: [URL]
    let mappings: [SourceOrganizationFileMapping]
    let destinationItemIDBySourceItemID: [String: String]
    let originFolderPathBytesByFileID: [String: Data]
    let previewGroups: [SourceOrganizationPreviewGroup]
    let collisions: [SourceOrganizationCollision]
    let itemCount: Int
    let mediaFileCount: Int
    let movingItemCount: Int
    let movingFileCount: Int
    let alreadyOrganizedItemCount: Int
    let sidecarFileCount: Int
    let excludedACRCompanionCount: Int

    var canExecute: Bool {
        !sourceItems.isEmpty
            && !workerPlan.items.isEmpty
            && collisions.isEmpty
    }
}

enum SourceOrganizationPlanner {
    enum PlannerError: LocalizedError {
        case invalidContainerName
        case unsafeSourcePath(URL)
        case invalidExistingFolder

        var errorDescription: String? {
            switch self {
            case .invalidContainerName:
                return "Choose a single, non-empty folder name for the organized files."
            case .unsafeSourcePath(let url):
                return "Louppe could not preserve the exact source path for \(url.lastPathComponent)."
            case .invalidExistingFolder:
                return "An existing source-folder path could not be represented safely."
            }
        }
    }

    static func makePlan(
        sourceFolder: URL,
        selectedItems: [PhotoItem],
        familyContextItems: [PhotoItem],
        configuration: SourceOrganizationConfiguration,
        knownOriginFolderPathBytesByFileID: [String: Data],
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> SourceOrganizationPlan {
        if isCancelled() { throw CancellationError() }
        guard isValidContainerName(configuration.containerName),
              !configuration.enabledLevels.isEmpty else {
            throw PlannerError.invalidContainerName
        }
        let rootPath = try XMPExactFileSystemPath(url: sourceFolder)
        let sourceFolderIdentity = try SessionPersistence.SourceFolderIdentity
            .capture(at: sourceFolder)
        let storageSafety = SourceOrganizationStorageSafety.detect(
            at: sourceFolder
        )
        let volumeValues = try? sourceFolder.resourceValues(forKeys: [
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        let volumeUsesCaseSensitiveNames =
            volumeValues?.volumeSupportsCaseSensitiveNames ?? false
        let containerComponent = Data(configuration.containerName.utf8)
        let destinationRoot = try rootPath.appending(
            componentBytes: containerComponent
        )

        var origins = knownOriginFolderPathBytesByFileID
        for file in familyContextItems.flatMap(\.individualFiles) {
            if isCancelled() { throw CancellationError() }
            if origins[file.id] == nil {
                origins[file.id] = try relativeParentBytes(
                    of: file.url,
                    under: sourceFolder
                )
            }
        }

        var plannedFilesByItem = [[ExportWorker.PlannedFile]](
            repeating: [],
            count: selectedItems.count
        )
        var mappings: [SourceOrganizationFileMapping] = []
        var targetDirectoryByMediaPath:
            [XMPExactFileSystemPath: XMPExactFileSystemPath] = [:]
        var selectedItemIndexByMediaPath: [XMPExactFileSystemPath: Int] = [:]
        var destinationItemIDs: [String: String] = [:]
        var previewCounts:
            [String: (items: Int, mediaFiles: Int)] = [:]
        var alreadyOrganizedItems = 0
        var movingItems = 0
        var movingMediaFiles = 0
        var destinationDirectories = Set<XMPExactFileSystemPath>()
        var collisions: [SourceOrganizationCollision] = []
        var reservedTargets: [String: (source: URL, target: URL)] = [:]
        var mediaAlreadyCorrectByItem = [Bool](
            repeating: true,
            count: selectedItems.count
        )

        func reserve(
            source: URL,
            target: URL,
            isMedia: Bool,
            itemIndex: Int
        ) -> Bool {
            let sourceExact = try? XMPExactFileSystemPath(url: source)
            let targetExact = try? XMPExactFileSystemPath(url: target)
            guard let sourceExact, let targetExact else {
                collisions.append(SourceOrganizationCollision(
                    id: "unsafe:\(target.path)",
                    destination: target,
                    sources: [source],
                    message: "The exact source or destination path could not be preserved."
                ))
                return false
            }
            if sourceExact == targetExact {
                return false
            }
            if targetExact.entryExists,
               pathsReferToSameFile(source, target) {
                return false
            }
            let key = collisionKey(
                targetExact.bytes,
                caseSensitive: volumeUsesCaseSensitiveNames
            )
            if let existing = reservedTargets[key] {
                collisions.append(SourceOrganizationCollision(
                    id: "planned:\(key)",
                    destination: target,
                    sources: [existing.source, source],
                    message: "Two source files would have the same destination."
                ))
                return false
            }
            if targetExact.entryExists {
                collisions.append(SourceOrganizationCollision(
                    id: "existing:\(key)",
                    destination: target,
                    sources: [source, target],
                    message: "A different file or folder already exists at the destination."
                ))
                return false
            }
            reservedTargets[key] = (source, target)
            if isMedia {
                mediaAlreadyCorrectByItem[itemIndex] = false
                movingMediaFiles += 1
            }
            return true
        }

        for (itemIndex, item) in selectedItems.enumerated() {
            if isCancelled() { throw CancellationError() }
            let metadata = item.metadataState
            var targetDirectory = destinationRoot
            for level in configuration.enabledLevels {
                switch level.kind {
                case .existingFolder:
                    let origin = origins[item.primaryFile.id] ?? Data()
                    let components = try existingFolderComponents(
                        origin,
                        depth: configuration.existingFolderDepth
                    )
                    for component in components {
                        targetDirectory = try targetDirectory.appending(
                            componentBytes: component
                        )
                    }
                default:
                    let label = folderLabel(
                        for: level.kind,
                        item: item,
                        metadata: metadata,
                        dateGranularity: configuration.dateGranularity
                    )
                    targetDirectory = try targetDirectory.appending(
                        componentBytes: Data(safeFolderComponent(label).utf8)
                    )
                }
            }
            destinationDirectories.insert(targetDirectory)
            if let unsafe = unsafeExistingDirectory(
                onPathTo: targetDirectory,
                under: rootPath
            ) {
                collisions.append(SourceOrganizationCollision(
                    id: "unsafe-directory:\(unsafe.bytes.base64EncodedString())",
                    destination: unsafe.url,
                    sources: item.allURLs,
                    message: "A destination component already exists but is not a normal folder."
                ))
            }
            let previewPath = displayRelativePath(
                targetDirectory.bytes,
                under: rootPath.bytes
            )
            previewCounts[previewPath, default: (0, 0)].items += 1
            previewCounts[previewPath, default: (0, 0)].mediaFiles +=
                item.individualFiles.count

            for file in item.individualFiles {
                let sourcePath = try XMPExactFileSystemPath(url: file.url)
                let targetPath = try targetDirectory.appending(
                    componentBytes: sourcePath.lastComponentBytes
                )
                targetDirectoryByMediaPath[sourcePath] = targetDirectory
                selectedItemIndexByMediaPath[sourcePath] = itemIndex
                mappings.append(SourceOrganizationFileMapping(
                    itemID: item.id,
                    source: file.url,
                    destination: targetPath.url,
                    isMedia: true
                ))
                if reserve(
                    source: file.url,
                    target: targetPath.url,
                    isMedia: true,
                    itemIndex: itemIndex
                ) {
                    plannedFilesByItem[itemIndex].append(
                        ExportWorker.PlannedFile(
                            source: file.url,
                            target: targetPath.url,
                            scannedIdentity: file.scannedIdentity
                        )
                    )
                }
            }
            if let primaryMapping = mappings.last(where: {
                $0.itemID == item.id && $0.source == item.primaryURL
            }) {
                destinationItemIDs[item.id] = FolderScanner.relativeFileIdentity(
                    of: primaryMapping.destination,
                    under: sourceFolder
                )
            }
        }

        // Existing XMP packets are moved unchanged. A shared canonical packet
        // is allowed only when every family member is in scope and resolves to
        // one target directory; otherwise the preview blocks rather than
        // silently separating media from its metadata.
        var parentGroups:
            [XMPExactFileSystemPath: [XMPStemFamilyMember]] = [:]
        for file in familyContextItems.flatMap(\.individualFiles) {
            if isCancelled() { throw CancellationError() }
            let member = try XMPStemFamilyMember(
                mediaURL: file.url,
                mediaKind: file.mediaKind,
                metadata: XMPPublicationMetadata(
                    snapshot: file.metadataSnapshot,
                    profile: .universal
                ),
                sessionFileID: file.id,
                sessionMetadata: file.metadataSnapshot,
                scannedIdentity: file.scannedIdentity
            )
            parentGroups[member.mediaPath.parent, default: []].append(member)
        }

        var disjointSet = DisjointSet(count: selectedItems.count)
        var sidecarFiles = 0
        var excludedACR = Set<XMPExactFileSystemPath>()
        for members in parentGroups.values {
            if isCancelled() { throw CancellationError() }
            for family in try XMPSidecarResolver.resolve(members: members) {
                if isCancelled() { throw CancellationError() }
                let selectedMembers = family.members.filter {
                    targetDirectoryByMediaPath[$0.mediaPath] != nil
                }
                guard !selectedMembers.isEmpty else { continue }
                if family.disposition == .unsupportedMedia { continue }
                if family.disposition == .filenameCollision {
                    collisions.append(SourceOrganizationCollision(
                        id: "xmp-filename:\(selectedMembers[0].mediaPath.bytes.base64EncodedString())",
                        destination: selectedMembers[0].mediaPath.parent.url,
                        sources: selectedMembers.map(\.mediaPath.url),
                        message: "This media family has ambiguous XMP filenames."
                    ))
                    continue
                }
                for acr in family.excludedACRCompanions {
                    excludedACR.insert(acr)
                }

                if let canonical = family.canonicalSidecar,
                   canonical.entryExists {
                    let everyMemberSelected = selectedMembers.count
                        == family.members.count
                    let targetDirectories = Set(selectedMembers.compactMap {
                        targetDirectoryByMediaPath[$0.mediaPath]
                    })
                    guard everyMemberSelected, targetDirectories.count == 1,
                          let targetDirectory = targetDirectories.first else {
                        collisions.append(SourceOrganizationCollision(
                            id: "shared-xmp:\(canonical.bytes.base64EncodedString())",
                            destination: canonical.url,
                            sources: selectedMembers.map(\.mediaPath.url),
                            message: "A shared XMP sidecar would be separated from part of its media family."
                        ))
                        continue
                    }
                    let itemIndices = selectedMembers.compactMap {
                        selectedItemIndexByMediaPath[$0.mediaPath]
                    }
                    if let first = itemIndices.first {
                        for index in itemIndices.dropFirst() {
                            disjointSet.union(first, index)
                        }
                        let target = try targetDirectory.appending(
                            componentBytes: canonical.lastComponentBytes
                        )
                        mappings.append(SourceOrganizationFileMapping(
                            itemID: selectedItems[first].id,
                            source: canonical.url,
                            destination: target.url,
                            isMedia: false
                        ))
                        if reserve(
                            source: canonical.url,
                            target: target.url,
                            isMedia: false,
                            itemIndex: first
                        ) {
                            plannedFilesByItem[first].append(
                                ExportWorker.PlannedFile(
                                    source: canonical.url,
                                    target: target.url,
                                    scannedIdentity: try FileOperationJournal
                                        .captureIdentity(at: canonical.url),
                                    role: .applicationXMP
                                )
                            )
                            sidecarFiles += 1
                            destinationDirectories.insert(targetDirectory)
                        }
                    }
                }

                for packet in family.extensionQualifiedSidecars {
                    let owners = family.members.filter {
                        extensionPacket(packet, belongsTo: $0.mediaPath)
                    }
                    guard owners.count == 1 else {
                        collisions.append(SourceOrganizationCollision(
                            id: "ambiguous-xmp:\(packet.bytes.base64EncodedString())",
                            destination: packet.url,
                            sources: owners.map(\.mediaPath.url),
                            message: "An application XMP sidecar could not be associated with exactly one media file."
                        ))
                        continue
                    }
                    let owner = owners[0]
                    guard let targetDirectory = targetDirectoryByMediaPath[
                              owner.mediaPath
                          ],
                          let itemIndex = selectedItemIndexByMediaPath[
                              owner.mediaPath
                          ] else { continue }
                    let target = try targetDirectory.appending(
                        componentBytes: packet.lastComponentBytes
                    )
                    mappings.append(SourceOrganizationFileMapping(
                        itemID: selectedItems[itemIndex].id,
                        source: packet.url,
                        destination: target.url,
                        isMedia: false
                    ))
                    if reserve(
                        source: packet.url,
                        target: target.url,
                        isMedia: false,
                        itemIndex: itemIndex
                    ) {
                        plannedFilesByItem[itemIndex].append(
                            ExportWorker.PlannedFile(
                                source: packet.url,
                                target: target.url,
                                scannedIdentity: try FileOperationJournal
                                    .captureIdentity(at: packet.url),
                                role: .applicationXMP
                            )
                        )
                        sidecarFiles += 1
                        destinationDirectories.insert(targetDirectory)
                    }
                }
            }
        }

        var groupedFiles: [Int: [ExportWorker.PlannedFile]] = [:]
        var groupedItemIDs: [Int: [String]] = [:]
        for itemIndex in selectedItems.indices {
            if isCancelled() { throw CancellationError() }
            let root = disjointSet.find(itemIndex)
            groupedFiles[root, default: []].append(
                contentsOf: plannedFilesByItem[itemIndex]
            )
            if !plannedFilesByItem[itemIndex].isEmpty {
                groupedItemIDs[root, default: []].append(
                    selectedItems[itemIndex].id
                )
            }
        }
        let plannedItems = groupedFiles.keys.sorted().compactMap { root ->
            ExportWorker.PlannedItem? in
            guard let files = groupedFiles[root], !files.isEmpty else {
                return nil
            }
            let ids = groupedItemIDs[root] ?? []
            return ExportWorker.PlannedItem(
                itemID: "organize:\(root):\(ids.first ?? "item")",
                movedItemIDs: ids,
                files: files
            )
        }

        for index in selectedItems.indices {
            if isCancelled() { throw CancellationError() }
            if mediaAlreadyCorrectByItem[index] {
                alreadyOrganizedItems += 1
            } else {
                movingItems += 1
            }
        }

        let preview = previewCounts.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { path in
            let count = previewCounts[path]!
            return SourceOrganizationPreviewGroup(
                path: path,
                itemCount: count.items,
                mediaFileCount: count.mediaFiles
            )
        }
        let uniqueCollisions = Dictionary(
            grouping: collisions,
            by: \.id
        ).values.compactMap(\.first).sorted {
            $0.destination.path.localizedStandardCompare(
                $1.destination.path
            ) == .orderedAscending
        }
        return SourceOrganizationPlan(
            sourceFolder: sourceFolder,
            sourceFolderIdentity: sourceFolderIdentity,
            storageSafety: storageSafety,
            configuration: configuration,
            sourceItems: selectedItems,
            workerPlan: ExportWorker.Plan(items: plannedItems),
            destinationDirectories: destinationDirectories.map(\.url),
            mappings: mappings,
            destinationItemIDBySourceItemID: destinationItemIDs,
            originFolderPathBytesByFileID: origins,
            previewGroups: preview,
            collisions: uniqueCollisions,
            itemCount: selectedItems.count,
            mediaFileCount: selectedItems.reduce(0) {
                $0 + $1.individualFiles.count
            },
            movingItemCount: movingItems,
            movingFileCount: movingMediaFiles + sidecarFiles,
            alreadyOrganizedItemCount: alreadyOrganizedItems,
            sidecarFileCount: sidecarFiles,
            excludedACRCompanionCount: excludedACR.count
        )
    }

    static func relativeParentBytes(
        of file: URL,
        under root: URL
    ) throws -> Data {
        let rootBytes = try XMPExactFileSystemPath(url: root).bytes
        let parentBytes = try XMPExactFileSystemPath(url: file).parent.bytes
        if let relative = relativePathBytes(
            parent: parentBytes,
            root: rootBytes
        ) {
            return relative
        }

        // Foundation may enumerate `/var` through its `/private/var` alias.
        // Resolve only after the byte-exact prefix attempt, and only when the
        // resolved root is still the same physical directory. The returned
        // suffix remains the actual directory-entry bytes below that root.
        let resolvedRoot = root.resolvingSymlinksInPath()
        guard ExportDestinationValidator.directoriesReferToSameEntry(
                root,
                resolvedRoot
              ) else {
            throw PlannerError.unsafeSourcePath(file)
        }
        let resolvedRootBytes = try XMPExactFileSystemPath(
            url: resolvedRoot
        ).bytes
        let resolvedParentBytes = try XMPExactFileSystemPath(
            url: file.deletingLastPathComponent().resolvingSymlinksInPath()
        ).bytes
        guard let relative = relativePathBytes(
            parent: resolvedParentBytes,
            root: resolvedRootBytes
        ) else {
            throw PlannerError.unsafeSourcePath(file)
        }
        return relative
    }

    private static func relativePathBytes(
        parent: Data,
        root: Data
    ) -> Data? {
        if parent == root { return Data() }
        var prefix = root
        if prefix.last != UInt8(ascii: "/") {
            prefix.append(UInt8(ascii: "/"))
        }
        guard parent.starts(with: prefix) else { return nil }
        return parent.dropFirst(prefix.count)
    }

    static func dateFolderLabel(
        _ date: Date,
        granularity: SourceOrganizationDateGranularity
    ) -> String {
        let label: String
        switch granularity {
        case .day: label = AppDateFormat.day(date)
        case .month: label = AppDateFormat.yearAndMonth(date)
        case .year: label = AppDateFormat.year(date)
        }
        return safeFolderComponent(label)
    }

    private static func isValidContainerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed != "."
            && trimmed != ".."
            && trimmed.utf8.count <= 180
            && !trimmed.contains("/")
            && !trimmed.contains(":")
            && !trimmed.contains("\0")
    }

    private static func existingFolderComponents(
        _ relativeParent: Data,
        depth: SourceOrganizationExistingFolderDepth
    ) throws -> [Data] {
        let components = [UInt8](relativeParent)
            .split(separator: UInt8(ascii: "/"))
            .map { Data($0) }
        guard components.allSatisfy({
            !$0.isEmpty && $0 != Data(".".utf8) && $0 != Data("..".utf8)
        }) else { throw PlannerError.invalidExistingFolder }
        guard !components.isEmpty else {
            return [Data("Source Root".utf8)]
        }
        switch depth {
        case .topLevel: return [components[0]]
        case .fullPath: return components
        }
    }

    private static func folderLabel(
        for kind: SourceOrganizationLevelKind,
        item: PhotoItem,
        metadata: PhotoItemMetadataState,
        dateGranularity: SourceOrganizationDateGranularity
    ) -> String {
        switch kind {
        case .existingFolder:
            return "Source Root"
        case .decision:
            switch metadata.decision {
            case .yes: return "Yes"
            case .no: return "No"
            case .undecided: return "Undecided"
            case .mixed: return "Mixed"
            }
        case .dateTaken:
            guard let date = item.captureDate else { return "Unknown Date" }
            return dateFolderLabel(date, granularity: dateGranularity)
        case .starRating:
            switch metadata.stars {
            case .unrated: return "Unrated"
            case .stars(let rating):
                return rating == .one ? "1 Star" : "\(rating.count) Stars"
            case .mixed: return "Mixed"
            }
        case .colorLabel:
            switch metadata.color {
            case .none: return "No Color"
            case .label(let label): return label.displayName
            case .mixed: return "Mixed"
            }
        case .camera:
            return item.cameraModel ?? "Unknown Camera"
        case .lens:
            return item.lensModel ?? "Unknown Lens"
        case .fileType:
            return item.fileTypeLabel
        case .mediaType:
            return item.mediaKind.label
        }
    }

    private static func safeFolderComponent(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "∕")
            .replacingOccurrences(of: ":", with: "꞉")
        if result.isEmpty { result = "Unknown" }
        if result == "." || result == ".." { result = "_\(result)" }
        if result.utf8.count > 180 {
            var truncated = ""
            var byteCount = 0
            for character in result {
                let characterBytes = String(character).utf8.count
                guard byteCount + characterBytes <= 180 else { break }
                truncated.append(character)
                byteCount += characterBytes
            }
            result = truncated.isEmpty ? "Unknown" : truncated
        }
        return result
    }

    private static func collisionKey(
        _ bytes: Data,
        caseSensitive: Bool
    ) -> String {
        if caseSensitive { return bytes.base64EncodedString() }
        return String(decoding: bytes, as: UTF8.self)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func pathsReferToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = try? FileOperationJournal.captureIdentity(at: lhs),
              let right = try? FileOperationJournal.captureIdentity(at: rhs)
        else { return false }
        return FileOperationJournal.identitiesMatch(
            expected: left,
            actual: right,
            includeStatusChange: true
        )
    }

    private static func displayRelativePath(
        _ bytes: Data,
        under root: Data
    ) -> String {
        var prefix = root
        if prefix.last != UInt8(ascii: "/") {
            prefix.append(UInt8(ascii: "/"))
        }
        let relative = bytes.starts(with: prefix)
            ? bytes.dropFirst(prefix.count)
            : bytes[bytes.startIndex...]
        return String(decoding: relative, as: UTF8.self)
    }

    private static func extensionPacket(
        _ packet: XMPExactFileSystemPath,
        belongsTo media: XMPExactFileSystemPath
    ) -> Bool {
        let packetName = String(
            decoding: packet.lastComponentBytes,
            as: UTF8.self
        ).precomposedStringWithCanonicalMapping.lowercased()
        let mediaName = String(
            decoding: media.lastComponentBytes,
            as: UTF8.self
        ).precomposedStringWithCanonicalMapping.lowercased()
        return packetName == mediaName + ".xmp"
    }

    private static func unsafeExistingDirectory(
        onPathTo directory: XMPExactFileSystemPath,
        under root: XMPExactFileSystemPath
    ) -> XMPExactFileSystemPath? {
        var prefix = root.bytes
        if prefix.last != UInt8(ascii: "/") {
            prefix.append(UInt8(ascii: "/"))
        }
        guard directory.bytes.starts(with: prefix) else { return directory }
        let relative = directory.bytes.dropFirst(prefix.count)
        let components = [UInt8](relative)
            .split(separator: UInt8(ascii: "/"))
        var current = root
        for component in components {
            guard let next = try? current.appending(
                componentBytes: Data(component)
            ) else { return current }
            var status = Darwin.stat()
            let result = next.withFileSystemRepresentation {
                Darwin.lstat($0, &status)
            }
            if result == 0,
               (status.st_mode & mode_t(S_IFMT)) != mode_t(S_IFDIR) {
                return next
            }
            current = next
        }
        return nil
    }

    private struct DisjointSet {
        var parents: [Int]

        init(count: Int) {
            parents = Array(0..<count)
        }

        mutating func find(_ value: Int) -> Int {
            if parents[value] != value {
                parents[value] = find(parents[value])
            }
            return parents[value]
        }

        mutating func union(_ lhs: Int, _ rhs: Int) {
            let left = find(lhs)
            let right = find(rhs)
            if left != right { parents[right] = left }
        }
    }
}
