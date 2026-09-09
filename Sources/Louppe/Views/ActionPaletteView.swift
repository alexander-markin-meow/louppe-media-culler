import SwiftUI

/// A searchable, keyboard-first route to Louppe's less-frequent actions.
/// Fast culling deliberately stays on its one-key shortcuts; this panel makes
/// newer metadata, folder, and presentation tools easy to discover without
/// crowding the review surface.
struct ActionPaletteView: View {
    @ObservedObject var store: SessionStore

    @State private var query = ""
    @State private var selectedActionID: String?
    @State private var selectionRevealGeneration = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            actionList
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .background(Color.appBackground)
        .onAppear {
            chooseFirstEnabledAction()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: query) {
            chooseFirstEnabledAction()
            revealKeyboardSelection()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search actions", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit { runSelectedAction() }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    store.dismissActionPalette()
                    return .handled
                }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    query = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear action search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var actionList: some View {
        let visibleActions = filteredActions
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(visibleActions.enumerated()), id: \.element.id) {
                        index, action in
                        if index == 0
                            || visibleActions[index - 1].category != action.category {
                            Text(action.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, index == 0 ? 10 : 16)
                                .padding(.horizontal, 18)
                        }
                        actionRow(action)
                            .id(action.id)
                    }
                    if visibleActions.isEmpty {
                        ContentUnavailableView(
                            "No matching actions",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search term.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                    }
                }
                .padding(.bottom, 10)
            }
            .accessibilityLabel("Command Palette actions")
            .onChange(of: selectionRevealGeneration) {
                guard let selectedActionID else { return }
                proxy.scrollTo(selectedActionID, anchor: .center)
            }
        }
    }

    private func actionRow(_ action: ActionPaletteAction) -> some View {
        Button {
            run(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .frame(width: 20)
                    .foregroundStyle(action.isEnabled ? Color.louppeAccent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .foregroundStyle(.primary)
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                if selectedActionID == action.id {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.louppeAccent.opacity(0.14))
                        .padding(.horizontal, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.42)
        .onHover { isHovering in
            if isHovering, action.isEnabled {
                selectedActionID = action.id
            }
        }
        .accessibilityLabel(action.title)
        .accessibilityHint(action.detail)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("⌘K")
                .font(.caption.monospaced())
            Text("to open")
            Spacer()
            Text("↑↓")
                .font(.caption.monospaced())
            Text("choose")
            Text("↵")
                .font(.caption.monospaced())
            Text("run")
            Text("Esc")
                .font(.caption.monospaced())
            Text("close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 38)
    }

    private var filteredActions: [ActionPaletteAction] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return actions }
        return actions.filter { action in
            let searchable = action.searchText
            return terms.allSatisfy { searchable.contains($0) }
        }
    }

    var actions: [ActionPaletteAction] {
        [
            ActionPaletteAction(
                id: "export",
                category: "Files",
                title: "Export…",
                detail: "Copy, move, or write Metadata (XMP)",
                symbol: "square.and.arrow.up",
                shortcut: "E",
                keywords: ["copy", "move", "xmp", "metadata"],
                isEnabled: store.canExport,
                perform: { store.presentExport() }
            ),
            ActionPaletteAction(
                id: "rename-files-from-metadata",
                category: "Files",
                title: "Rename Files from Metadata…",
                detail: "Preview names built from date, time, camera, lens, and sequence",
                symbol: "textformat",
                keywords: [
                    "rename", "filename", "batch", "bulk", "metadata",
                    "date", "time", "camera", "lens", "sequence",
                ],
                isEnabled: store.canRenameSource,
                perform: { store.presentMetadataFileRenaming() }
            ),
            ActionPaletteAction(
                id: "organize",
                category: "Files",
                title: "Organize Source Folder…",
                detail: "Preview a metadata-based folder layout",
                symbol: "folder.badge.gearshape",
                keywords: ["move", "folders", "date", "camera", "source"],
                isEnabled: store.canOrganizeSource,
                perform: { store.presentSourceOrganization() }
            ),
            ActionPaletteAction(
                id: "organize-date-taken-only",
                category: "Files",
                title: "Organize by Date Taken Only…",
                detail: "Open the organizer with Full date as the only folder level",
                symbol: "calendar.badge.clock",
                keywords: [
                    "organize", "source", "folder", "date", "taken",
                    "capture", "chronological",
                ],
                isEnabled: store.canOrganizeSource,
                perform: {
                    store.presentSourceOrganization(
                        configuration: .dateTakenOnly
                    )
                }
            ),
            ActionPaletteAction(
                id: "open-folder",
                category: "Files",
                title: "Open Different Folder…",
                detail: "Save this session, then choose another photo folder",
                symbol: "folder",
                shortcut: "⌘O",
                keywords: ["recent", "session", "open"],
                isEnabled: !store.isFileOperationRunning,
                perform: { store.promptForSourceFolder() }
            ),
            ActionPaletteAction(
                id: "rescan",
                category: "Files",
                title: "Rescan Folder",
                detail: "Find new or changed media in this folder",
                symbol: "arrow.triangle.2.circlepath",
                shortcut: "⌘R",
                keywords: ["refresh", "scan"],
                isEnabled: !store.isFileOperationRunning,
                perform: { store.rescan() }
            ),
        ]
        + recentFolderActions()
        + [
            ActionPaletteAction(
                id: "filter",
                category: "Find and arrange",
                title: "Filter Media…",
                detail: "Filter by metadata, date, type, camera, lens, or video details",
                symbol: "line.3.horizontal.decrease.circle",
                keywords: ["search", "date", "camera", "lens", "color", "stars", "video", "codec", "resolution", "frame rate"],
                isEnabled: !store.isFileOperationRunning,
                perform: { store.isFilterPresented = true }
            ),
            ActionPaletteAction(
                id: "show-videos-only",
                category: "Find and arrange",
                title: "Show Videos Only",
                detail: "Keep the current criteria and limit the folder to videos",
                symbol: "film",
                keywords: ["video", "clip", "movie", "filter", "media"],
                isEnabled: store.availableMediaKinds.contains(.video)
                    && !store.isFileOperationRunning,
                perform: { store.showVideosOnly() }
            ),
            ActionPaletteAction(
                id: "reset-filter",
                category: "Find and arrange",
                title: "Reset Filters",
                detail: "Show the full folder again",
                symbol: "line.3.horizontal.decrease.circle.fill",
                keywords: ["clear", "show all", "search"],
                isEnabled: store.filterCanReset && !store.isFileOperationRunning,
                perform: { store.resetFilter() }
            ),
            ActionPaletteAction(
                id: "sort",
                category: "Find and arrange",
                title: "Sort Media…",
                detail: "Choose date, stars, color, camera, video details, and more",
                symbol: "arrow.up.arrow.down",
                keywords: ["group", "order", "metadata", "video", "codec", "resolution", "frame rate"],
                isEnabled: !store.isFileOperationRunning,
                perform: { store.isSortPresented = true }
            ),
            ActionPaletteAction(
                id: "sort-by-video-resolution",
                category: "Find and arrange",
                title: "Sort by Video Resolution",
                detail: "Order videos by their scan-cached pixel dimensions",
                symbol: "rectangle.on.rectangle",
                keywords: ["video", "resolution", "dimensions", "sort", "4k", "hd"],
                isEnabled: store.availableVideoResolutions.count > 1
                    && !store.isFileOperationRunning,
                perform: { store.sort.key = .videoResolution }
            ),
            ActionPaletteAction(
                id: "sort-by-video-frame-rate",
                category: "Find and arrange",
                title: "Sort by Video Frame Rate",
                detail: "Order videos by their scan-cached frames per second",
                symbol: "speedometer",
                keywords: ["video", "frame rate", "fps", "sort", "slow motion"],
                isEnabled: store.videoFrameRateRange != nil
                    && !store.isFileOperationRunning,
                perform: { store.sort.key = .videoFrameRate }
            ),
            ActionPaletteAction(
                id: "sort-by-video-codec",
                category: "Find and arrange",
                title: "Sort by Video Codec",
                detail: "Order videos by their scan-cached codec",
                symbol: "film.stack",
                keywords: ["video", "codec", "h.264", "hevc", "prores", "sort"],
                isEnabled: store.availableVideoCodecs.count > 1
                    && !store.isFileOperationRunning,
                perform: { store.sort.key = .videoCodec }
            ),
            ActionPaletteAction(
                id: "analyze-duplicate-burst-groups",
                category: "Find and arrange",
                title: "Analyze Duplicate + Burst Groups",
                detail: "Read this folder locally; it never changes files or ratings",
                symbol: "rectangle.3.group",
                keywords: ["duplicates", "similar", "burst", "local", "review"],
                isEnabled: !store.items.isEmpty
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.analyzeDuplicateAndBurstGroups() }
            ),
            ActionPaletteAction(
                id: "review-exact-duplicates",
                category: "Find and arrange",
                title: "Review Exact Duplicates",
                detail: "Show verified byte-identical files as groups",
                symbol: "doc.on.doc",
                keywords: ["duplicates", "same", "byte", "groups", "review"],
                isEnabled: !store.items.isEmpty
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.enterGroupedReview(.exactDuplicates) }
            ),
            ActionPaletteAction(
                id: "review-likely-similar-photos",
                category: "Find and arrange",
                title: "Review Likely Similar Photos",
                detail: "Group local preview matches; inspect before deciding",
                symbol: "photo.on.rectangle.angled",
                keywords: ["duplicates", "similarity", "near", "groups", "review"],
                isEnabled: !store.items.isEmpty
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.enterGroupedReview(.likelySimilarPhotos) }
            ),
            ActionPaletteAction(
                id: "review-capture-bursts",
                category: "Find and arrange",
                title: "Review Capture Bursts",
                detail: "Group photos taken close together in time",
                symbol: "rectangle.stack",
                keywords: ["burst", "capture", "time", "groups", "review"],
                isEnabled: !store.items.isEmpty
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.enterGroupedReview(.captureBursts) }
            ),
            ActionPaletteAction(
                id: "return-normal-review",
                category: "Find and arrange",
                title: "Return to Normal Review",
                detail: "Leave grouped review and restore the normal filtered order",
                symbol: "arrow.uturn.backward.circle",
                keywords: ["exit", "groups", "normal", "review", "show all"],
                isEnabled: store.isGroupedReviewActive && !store.isFileOperationRunning,
                perform: { store.exitGroupedReview() }
            ),
            ActionPaletteAction(
                id: "pair-raw-jpeg",
                category: "Find and arrange",
                title: "Review Matching RAW + JPEG Together",
                detail: "Rate and act on matching files as one photo",
                symbol: "link",
                keywords: ["pair", "pairing", "raw", "jpeg"],
                isEnabled: store.rawJPEGPairingMode != .together
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.setRawJPEGPairingMode(.together) }
            ),
            ActionPaletteAction(
                id: "separate-raw-jpeg",
                category: "Find and arrange",
                title: "Review RAW and JPEG Separately",
                detail: "Show matching files as independent review items",
                symbol: "link.badge.plus",
                keywords: ["pair", "pairing", "raw", "jpeg"],
                isEnabled: store.rawJPEGPairingMode != .separate
                    && !store.isFileOperationRunning
                    && !store.isXMPPublicationRunning,
                perform: { store.setRawJPEGPairingMode(.separate) }
            ),
            ActionPaletteAction(
                id: "mark-yes",
                category: "Review metadata",
                title: "Mark Yes",
                detail: "Apply Yes to the current photo or selection",
                symbol: "checkmark.circle",
                shortcut: "F",
                keywords: ["keep", "accept", "decision"],
                isEnabled: store.canRate,
                perform: { store.rate(.yes) }
            ),
            ActionPaletteAction(
                id: "mark-no",
                category: "Review metadata",
                title: "Mark No",
                detail: "Apply No to the current photo or selection",
                symbol: "xmark.circle",
                shortcut: "D",
                keywords: ["reject", "decision"],
                isEnabled: store.canRate,
                perform: { store.rate(.no) }
            ),
            ActionPaletteAction(
                id: "clear-stars",
                category: "Review metadata",
                title: "Clear Stars",
                detail: "Remove the star rating from the current photo or selection",
                symbol: "star.slash",
                shortcut: "0",
                keywords: ["unrated", "rating", "metadata"],
                isEnabled: store.canRate,
                perform: { store.setStarRating(nil) }
            ),
        ]
        + starActions()
        + [
            ActionPaletteAction(
                id: "clear-color-label",
                category: "Review metadata",
                title: "Clear Color Label",
                detail: "Remove the color label from the current photo or selection",
                symbol: "tag.slash",
                keywords: ["none", "metadata", "xmp"],
                isEnabled: store.canRate,
                perform: { store.setColorLabel(nil) }
            ),
        ]
        + colorLabelActions()
        + [
            ActionPaletteAction(
                id: "select-previous-item",
                category: "Navigate and play",
                title: "Select Previous Item",
                detail: "Choose the previous visible item, including when reviewing a video",
                symbol: "chevron.left",
                shortcut: "J",
                keywords: ["previous", "back", "left", "navigate", "video", "clip"],
                isEnabled: !store.visibleIndices.isEmpty && !store.isFileOperationRunning,
                perform: { store.goPrevious() }
            ),
            ActionPaletteAction(
                id: "select-next-item",
                category: "Navigate and play",
                title: "Select Next Item",
                detail: "Choose the next visible item, including when reviewing a video",
                symbol: "chevron.right",
                shortcut: "L",
                keywords: ["next", "forward", "right", "navigate", "video", "clip"],
                isEnabled: !store.visibleIndices.isEmpty && !store.isFileOperationRunning,
                perform: { store.goNext() }
            ),
            ActionPaletteAction(
                id: "decrease-playback-rate",
                category: "Navigate and play",
                title: "Choose Slower Playback Speed",
                detail: "Step down through the available video or audio playback speeds",
                symbol: "backward.end",
                shortcut: "⌘←",
                keywords: ["video", "audio", "playback", "speed", "slower"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: {
                    _ = store.adjustCurrentPlayableMediaPlaybackRate(
                        forward: false
                    )
                }
            ),
            ActionPaletteAction(
                id: "increase-playback-rate",
                category: "Navigate and play",
                title: "Choose Faster Playback Speed",
                detail: "Step up through the available video or audio playback speeds",
                symbol: "forward.end",
                shortcut: "⌘→",
                keywords: ["video", "audio", "playback", "speed", "faster"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: {
                    _ = store.adjustCurrentPlayableMediaPlaybackRate(
                        forward: true
                    )
                }
            ),
            ActionPaletteAction(
                id: "seek-video-backward",
                category: "Navigate and play",
                title: "Seek Video Backward 0.5 Seconds",
                detail: "Inspect the current Gallery video half a second earlier",
                symbol: "gobackward",
                shortcut: "←",
                keywords: ["video", "clip", "scrub", "rewind", "back", "left"],
                isEnabled: store.canSeekCurrentVideo,
                perform: { store.seekCurrentVideo(by: -0.5) }
            ),
            ActionPaletteAction(
                id: "seek-video-forward",
                category: "Navigate and play",
                title: "Seek Video Forward 0.5 Seconds",
                detail: "Inspect the current Gallery video half a second later",
                symbol: "goforward",
                shortcut: "→",
                keywords: ["video", "clip", "scrub", "forward", "right"],
                isEnabled: store.canSeekCurrentVideo,
                perform: { store.seekCurrentVideo(by: 0.5) }
            ),
            ActionPaletteAction(
                id: "seek-video-backward-large",
                category: "Navigate and play",
                title: "Seek Video Backward 5 Seconds",
                detail: "Jump five seconds earlier in the current Gallery video",
                symbol: "gobackward.5",
                shortcut: "⇧←",
                keywords: ["video", "clip", "scrub", "rewind", "back", "left", "jump"],
                isEnabled: store.canSeekCurrentVideo,
                perform: { store.seekCurrentVideo(by: -5) }
            ),
            ActionPaletteAction(
                id: "seek-video-forward-large",
                category: "Navigate and play",
                title: "Seek Video Forward 5 Seconds",
                detail: "Jump five seconds later in the current Gallery video",
                symbol: "goforward.5",
                shortcut: "⇧→",
                keywords: ["video", "clip", "scrub", "forward", "right", "jump"],
                isEnabled: store.canSeekCurrentVideo,
                perform: { store.seekCurrentVideo(by: 5) }
            ),
            ActionPaletteAction(
                id: "toggle-current-media",
                category: "Navigate and play",
                title: "Play or Pause Current Media",
                detail: "Play or pause the current video or audio recording",
                symbol: "playpause",
                shortcut: "Space or K",
                keywords: ["video", "audio", "clip", "recording", "play", "pause", "transport", "k"],
                isEnabled: store.canToggleCurrentPlayableMedia,
                perform: { _ = store.toggleCurrentPlayableMedia() }
            ),
            ActionPaletteAction(
                id: "set-playback-rate-1x",
                category: "Navigate and play",
                title: "Set Playback Speed to 1×",
                detail: "Review the current video or audio recording at normal speed",
                symbol: "1.circle",
                shortcut: nil,
                keywords: ["video", "audio", "clip", "recording", "playback", "speed", "normal", "1x"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: { store.setCurrentPlayableMediaPlaybackRate(1) }
            ),
            ActionPaletteAction(
                id: "set-playback-rate-1-5x",
                category: "Navigate and play",
                title: "Set Playback Speed to 1.5×",
                detail: "Review the current video or audio recording at one and a half speed",
                symbol: "1.circle",
                shortcut: nil,
                keywords: ["video", "audio", "clip", "recording", "playback", "speed", "1.5x"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: { store.setCurrentPlayableMediaPlaybackRate(1.5) }
            ),
            ActionPaletteAction(
                id: "set-playback-rate-2x",
                category: "Navigate and play",
                title: "Set Playback Speed to 2×",
                detail: "Review the current video or audio recording at double speed",
                symbol: "2.circle",
                shortcut: nil,
                keywords: ["video", "audio", "clip", "recording", "playback", "speed", "double", "2x"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: { store.setCurrentPlayableMediaPlaybackRate(2) }
            ),
            ActionPaletteAction(
                id: "set-playback-rate-2-5x",
                category: "Navigate and play",
                title: "Set Playback Speed to 2.5×",
                detail: "Review the current video or audio recording at two and a half speed",
                symbol: "2.circle",
                shortcut: nil,
                keywords: ["video", "audio", "clip", "recording", "playback", "speed", "2.5x"],
                isEnabled: store.canSetCurrentPlayableMediaPlaybackRate,
                perform: { store.setCurrentPlayableMediaPlaybackRate(2.5) }
            ),
            ActionPaletteAction(
                id: "select-all",
                category: "Selection and clean up",
                title: "Select All Visible Media",
                detail: "Select every item that passes the current filter",
                symbol: "checklist",
                shortcut: "⌘A",
                keywords: ["selection", "filter"],
                isEnabled: !store.visibleIndices.isEmpty && !store.isFileOperationRunning,
                perform: { store.selectAllVisible() }
            ),
            ActionPaletteAction(
                id: "clear-selection",
                category: "Selection and clean up",
                title: "Clear Selection",
                detail: "Return to reviewing the current photo",
                symbol: "xmark.rectangle",
                shortcut: "Esc",
                keywords: ["deselect", "selection"],
                isEnabled: !store.selectedIndices.isEmpty && !store.isFileOperationRunning,
                perform: { store.clearSelection() }
            ),
            ActionPaletteAction(
                id: "trash-selection",
                category: "Selection and clean up",
                title: store.selectionCleanUpTitle,
                detail: "Ask for confirmation before moving selected media to Trash",
                symbol: "trash",
                shortcut: "⌘⌫",
                keywords: ["clean up", "delete", "remove"],
                isEnabled: store.canCleanUp && store.hasCleanUpTargets(for: .selection),
                perform: { store.requestCleanUp(.selection) }
            ),
            ActionPaletteAction(
                id: "trash-no",
                category: "Selection and clean up",
                title: "Move “No” to Trash…",
                detail: "Use the current Clean Up scope and ask for confirmation",
                symbol: "trash",
                keywords: ["clean up", "reject", "delete"],
                isEnabled: store.canCleanUp && store.hasCleanUpTargets(for: .trashNo),
                perform: { store.requestCleanUp(.trashNo) }
            ),
            ActionPaletteAction(
                id: "keep-only-yes",
                category: "Selection and clean up",
                title: "Keep Only “Yes”…",
                detail: "Use the current Clean Up scope and ask for confirmation",
                symbol: "trash",
                keywords: ["clean up", "delete", "reject"],
                isEnabled: store.canCleanUp && store.hasCleanUpTargets(for: .keepOnlyYes),
                perform: { store.requestCleanUp(.keepOnlyYes) }
            ),
            ActionPaletteAction(
                id: "trash-paired-jpegs",
                category: "Selection and clean up",
                title: "Move Paired JPEGs to Trash…",
                detail: "Keep the RAW file from each matching RAW + JPEG pair",
                symbol: "photo.badge.minus",
                keywords: ["clean up", "archive", "pair", "raw", "jpeg", "jpg", "keep raw", "delete", "remove"],
                isEnabled: store.canCleanUp && store.hasCleanUpTargets(for: .pairedJPEGs),
                perform: { store.requestCleanUp(.pairedJPEGs) }
            ),
            ActionPaletteAction(
                id: "trash-paired-raws",
                category: "Selection and clean up",
                title: "Move Paired RAWs to Trash…",
                detail: "Keep the JPEG file from each matching RAW + JPEG pair",
                symbol: "photo.badge.minus",
                keywords: ["clean up", "archive", "pair", "raw", "jpeg", "jpg", "keep jpeg", "delete", "remove"],
                isEnabled: store.canCleanUp && store.hasCleanUpTargets(for: .pairedRAWs),
                perform: { store.requestCleanUp(.pairedRAWs) }
            ),
            ActionPaletteAction(
                id: "undo",
                category: "Selection and clean up",
                title: "Undo Louppe Action",
                detail: "Restore the latest review, metadata, Trash, or organization action",
                symbol: "arrow.uturn.backward",
                shortcut: "Z",
                keywords: ["restore", "revert"],
                isEnabled: store.canUndo,
                perform: { store.undo() }
            ),
            ActionPaletteAction(
                id: "clear-decisions",
                category: "Selection and clean up",
                title: "Clear All Decisions",
                detail: "Remove Yes and No decisions while keeping stars and color labels",
                symbol: "eraser",
                shortcut: "R",
                keywords: ["reset", "ratings", "review"],
                isEnabled: store.ratedCount > 0 && !store.isFileOperationRunning,
                perform: { store.requestClearAllRatings() }
            ),
            ActionPaletteAction(
                id: "gallery",
                category: "View",
                title: "Switch to Gallery",
                detail: "Review one photo, video, or audio file at a time",
                symbol: "photo",
                shortcut: "G",
                keywords: ["view", "single"],
                isEnabled: store.viewMode != .gallery,
                perform: { store.toggleViewMode() }
            ),
            ActionPaletteAction(
                id: "grid",
                category: "View",
                title: "Switch to Grid",
                detail: "Review a visual overview of the folder",
                symbol: "square.grid.3x3",
                shortcut: "G",
                keywords: ["view", "thumbnails"],
                isEnabled: store.viewMode != .grid,
                perform: { store.toggleViewMode() }
            ),
            ActionPaletteAction(
                id: "browser",
                category: "View",
                title: store.showBrowser ? "Hide Browser" : "Show Browser",
                detail: "Toggle the thumbnail browser in Gallery",
                symbol: "sidebar.left",
                shortcut: "Q",
                keywords: ["thumbnails", "sidebar"],
                isEnabled: store.viewMode == .gallery,
                perform: { store.toggleBrowser() }
            ),
            ActionPaletteAction(
                id: "info",
                category: "View",
                title: store.showMetadataPanel ? "Hide Media Information" : "Show Media Information",
                detail: "Toggle the camera, histogram, and metadata panel",
                symbol: "info.circle",
                shortcut: "W",
                keywords: ["metadata", "histogram", "camera"],
                isEnabled: true,
                perform: { store.showMetadataPanel.toggle() }
            ),
            ActionPaletteAction(
                id: "clipping",
                category: "View",
                title: store.showClippingWarnings ? "Hide Preview Clipping Overlay" : "Show Preview Clipping Overlay",
                detail: "Mark clipping estimated from the displayed preview",
                symbol: "exclamationmark.triangle",
                shortcut: "X",
                keywords: ["preview", "histogram", "exposure", "highlights", "shadows"],
                isEnabled: store.canToggleClippingWarnings,
                perform: { _ = store.toggleClippingWarnings() }
            ),
        ]
    }

    private func chooseFirstEnabledAction() {
        selectedActionID = filteredActions.first(where: \.isEnabled)?.id
    }

    private func moveSelection(by offset: Int) {
        let enabled = filteredActions.filter(\.isEnabled)
        guard !enabled.isEmpty else {
            selectedActionID = nil
            return
        }
        guard let currentID = selectedActionID,
              let index = enabled.firstIndex(where: { $0.id == currentID })
        else {
            self.selectedActionID = enabled[0].id
            revealKeyboardSelection()
            return
        }
        let next = (index + offset + enabled.count) % enabled.count
        selectedActionID = enabled[next].id
        revealKeyboardSelection()
    }

    private func revealKeyboardSelection() {
        selectionRevealGeneration &+= 1
    }

    private func runSelectedAction() {
        guard let action = filteredActions.first(where: { $0.id == selectedActionID }) else { return }
        run(action)
    }

    private func run(_ action: ActionPaletteAction) {
        guard action.isEnabled else { return }
        store.dismissActionPalette(then: action.perform)
    }

    private func starActions() -> [ActionPaletteAction] {
        StarRating.allCases.map { rating in
            let title = rating == .one
                ? "Set 1 Star"
                : "Set \(rating.count) Stars"
            return ActionPaletteAction(
                id: "stars-\(rating.count)",
                category: "Review metadata",
                title: title,
                detail: "Apply a portable star rating to the current photo or selection",
                symbol: "star",
                shortcut: "\(rating.count)",
                keywords: ["rating", "metadata", "xmp"],
                isEnabled: store.canRate,
                perform: { store.setStarRating(rating) }
            )
        }
    }

    private func colorLabelActions() -> [ActionPaletteAction] {
        PhotoColorLabel.allCases.map { label in
            let title = "Set " + label.displayName + " Color Label"
            return ActionPaletteAction(
                id: "color-label-\(label.rawValue)",
                category: "Review metadata",
                title: title,
                detail: "Apply a portable color label to the current photo or selection",
                symbol: "tag",
                keywords: ["color", "label", "metadata", "xmp", label.rawValue],
                isEnabled: store.canRate,
                perform: { store.setColorLabel(label) }
            )
        }
    }

    private func recentFolderActions() -> [ActionPaletteAction] {
        store.recentFolders.map { folder in
            let name = folder.lastPathComponent.isEmpty
                ? folder.path
                : folder.lastPathComponent
            return ActionPaletteAction(
                id: "recent-folder-\(folder.path)",
                category: "Files",
                title: "Open Recent Folder “\(name)”",
                detail: folder.path,
                symbol: "clock.arrow.circlepath",
                keywords: ["recent", "open", "folder"],
                isEnabled: !store.isFileOperationRunning,
                perform: { store.openFolder(folder) }
            )
        }
    }
}

struct ActionPaletteAction: Identifiable {
    let id: String
    let category: String
    let title: String
    let detail: String
    let symbol: String
    let shortcut: String?
    let keywords: [String]
    let isEnabled: Bool
    let perform: @MainActor () -> Void

    init(
        id: String,
        category: String,
        title: String,
        detail: String,
        symbol: String,
        shortcut: String? = nil,
        keywords: [String],
        isEnabled: Bool,
        perform: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.shortcut = shortcut
        self.keywords = keywords
        self.isEnabled = isEnabled
        self.perform = perform
    }

    var searchText: String {
        ([title, detail, category] + keywords).joined(separator: " ").lowercased()
    }
}
