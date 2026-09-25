import SwiftUI

private enum XMPConflictResolutionOrigin {
    case standalone
    case copyOrMove
}

private struct XMPConflictResolverPresentation: Identifiable {
    let id = UUID()
    let conflicts: [XMPSameStemConflictDescriptor]
    let origin: XMPConflictResolutionOrigin
}

struct ExportView: View {
    @ObservedObject var store: SessionStore
    @StateObject private var exporter = ExportManager()
    // The sheet's content is recreated per presentation. An explicit selection
    // starts with all its items; otherwise Copy starts with keepers.
    @State private var mode: ExportMode = .copy
    /// Routing is intentionally a Copy-only subflow. Keeping it out of the
    /// toolbar and separate from Move makes the non-destructive default clear.
    @State private var isRoutingCopies = false
    @State private var routingRoutes: [MultiDestinationExportRoute] = [
        MultiDestinationExportRoute(predicate: .decision(.yes))
    ]
    @State private var routingIncludesXMP = false
    @State private var routingEvaluation = MultiDestinationExportEvaluation
        .evaluate(routes: [], items: [])
    @State private var selectedRatings: Set<Rating> = [.yes]
    @State private var selectedStars = ExportSelectionPredicate.allStarStates
    @State private var selectedColors = ExportSelectionPredicate.allColorStates
    @State private var scope: CleanUpScope = .filtered
    @State private var selectionSnapshot = ExportSelectionSnapshot.empty
    @State private var xmpProfile: XMPApplicationProfile = .universal
    @State private var universalDecisionKeywords = false
    @State private var allowExternalLabelReplacement = false
    @State private var showXMPDetails = false
    @State private var showEditingAppOptions = false
    @State private var xmpInclusionChoice = ExportXMPInclusionChoice()
    @State private var existingXMPCount = 0
    @State private var excludedACRCompanionCount = 0
    @State private var isCheckingExistingXMP = false
    @State private var xmpInspectionID = UUID()
    @State private var xmpInspectionTask: Task<Void, Never>?
    /// The detached scan itself. A detached task is not a child, so cancelling
    /// only the awaiting wrapper would leave a superseded whole-session scan
    /// running behind the newer one.
    @State private var xmpInspectionWork:
        Task<XMPExportSourceInspection?, Never>?
    @State private var conflictResolver: XMPConflictResolverPresentation?
    @State private var conflictResolutionNotice: String?

    var body: some View {
        VStack(spacing: 16) {
            if mode == .metadataXMP {
                xmpContent
            } else {
                switch exporter.state {
                case .summary:
                    summaryView
                case .preparingXMP(let mode):
                    xmpExportPreparationView(mode: mode)
                case .awaitingXMPConfirmation(let confirmation):
                    xmpExportPreflightView(confirmation)
                case .preparingMultiDestination:
                    multiDestinationPreparationView
                case .awaitingMultiDestinationConfirmation(let plan):
                    multiDestinationConfirmationView(plan)
                case .working(let mode, let completedBytes, let totalBytes):
                    workingView(
                        mode: mode,
                        completedBytes: completedBytes,
                        totalBytes: totalBytes
                    )
                case .finished(let outcome):
                    finishedView(outcome: outcome)
                case .failed(let message):
                    failedView(message: message)
                }
            }
        }
        .padding(usesFormLayout ? 0 : 24)
        .frame(width: 640, height: 620)
        .background(Color.appBackground)
        .tint(Color.louppeAccent)
        .interactiveDismissDisabled(isWorking)
        .confirmationDialog(
            "Stop copying?",
            isPresented: Binding(
                get: { exporter.isCopyStopConfirmationPresented },
                set: { isPresented in
                    if !isPresented {
                        exporter.dismissCopyStopConfirmation()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop Copying") { exporter.confirmCopyStop() }
            Button("Keep Copying", role: .cancel) {
                exporter.dismissCopyStopConfirmation()
            }
        } message: {
            Text("Completed media stays at the destination. Louppe will safely roll back only the file currently being copied.")
        }
        .onAppear {
            xmpInclusionChoice = ExportXMPInclusionChoice()
            routingIncludesXMP = false
            existingXMPCount = 0
            excludedACRCompanionCount = 0
            applyConfiguration(
                .initial(
                    hasExplicitSelection: !store.selectedIndices.isEmpty,
                    keepersOnly: store.exportKeepersRequested
                )
            )
            refreshSelectionSnapshot()
            refreshRoutingEvaluation()
        }
        .onDisappear {
            cancelXMPInspection()
            exporter.reset()
            store.resetXMPPublication()
        }
        .onChange(of: mode) {
            showXMPDetails = false
            showEditingAppOptions = false
            if mode != .copy { isRoutingCopies = false }
            store.resetXMPPublication()
            refreshSelectionSnapshot()
        }
        .onChange(of: isRoutingCopies) { refreshRoutingEvaluation() }
        .onChange(of: routingRoutes) { refreshRoutingEvaluation() }
        .onChange(of: selectedRatings) { refreshSelectionSnapshot() }
        .onChange(of: selectedStars) { refreshSelectionSnapshot() }
        .onChange(of: selectedColors) { refreshSelectionSnapshot() }
        .onChange(of: scope) {
            refreshSelectionSnapshot()
            refreshRoutingEvaluation()
        }
        .onChange(of: store.items.count) {
            refreshSelectionSnapshot()
            refreshRoutingEvaluation()
        }
        .onChange(of: store.selectedIndices) {
            refreshSelectionSnapshot()
            refreshRoutingEvaluation()
        }
        .sheet(item: $conflictResolver) { presentation in
            XMPConflictResolverView(
                conflicts: presentation.conflicts,
                onCancel: { conflictResolver = nil },
                onApply: { requests in
                    applyConflictResolutions(
                        requests,
                        origin: presentation.origin
                    )
                }
            )
        }
    }

    private var usesFormLayout: Bool {
        if mode == .metadataXMP {
            switch store.xmpPublicationState {
            case .idle, .awaitingConfirmation: return true
            default: return false
            }
        }
        switch exporter.state {
        case .summary, .awaitingXMPConfirmation, .awaitingMultiDestinationConfirmation:
            return true
        default: return false
        }
    }

    private var isWorking: Bool {
        if store.isXMPPublicationRunning { return true }
        if case .preparingXMP = exporter.state { return true }
        if case .preparingMultiDestination = exporter.state { return true }
        if case .working = exporter.state { return true }
        return false
    }

    @ViewBuilder
    private var summaryView: some View {
        if isRoutingCopies && mode == .copy {
            routingSummaryView
        } else {
        SheetForm(title: "Export") {
            Picker("Mode", selection: $mode) {
                Text("Copy").tag(ExportMode.copy)
                Text("Move").tag(ExportMode.move)
                Text("Metadata (XMP)").tag(ExportMode.metadataXMP)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .copy {
                Toggle("Route copies to multiple folders", isOn: $isRoutingCopies)
                    .accessibilityHint("Create explicit Copy-only routes with a separately chosen folder for each one")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Media to include")
                    .font(.subheadline.weight(.semibold))

                quickPickRow

                exportScopeRow

                Text("Yes/No/Undecided and stars are separate. An item must match both choices below, plus any color choice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ratingTile(.yes, count: scopeRatingCount(.yes), label: "Yes", color: .green)
                    ratingTile(.no, count: scopeRatingCount(.no), label: "No", color: .red)
                    ratingTile(.undecided, count: scopeRatingCount(.undecided), label: "Undecided", color: .secondary)
                }

                exportMenuRow("Stars") {
                    Menu(starSelectionSummary) {
                        Toggle(
                            "Unrated",
                            isOn: membershipBinding(
                                .unrated,
                                in: $selectedStars
                            )
                        )
                        ForEach(StarRating.allCases, id: \.self) { rating in
                            Toggle(
                                rating == .one
                                    ? "1 star"
                                    : "\(rating.count) stars",
                                isOn: membershipBinding(
                                    .stars(rating),
                                    in: $selectedStars
                                )
                            )
                        }
                        Toggle(
                            "Mixed",
                            isOn: membershipBinding(.mixed, in: $selectedStars)
                        )
                    }
                    .accessibilityLabel("Star ratings")
                    .accessibilityValue(starSelectionSummary)
                }

                exportMenuRow("Color") {
                    Menu(colorSelectionSummary) {
                        Toggle(
                            "None",
                            isOn: membershipBinding(
                                .none,
                                in: $selectedColors
                            )
                        )
                        ForEach(PhotoColorLabel.allCases, id: \.self) { label in
                            Toggle(
                                isOn: membershipBinding(
                                    .label(label),
                                    in: $selectedColors
                                )
                            ) {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(label.swatchColor)
                                        .frame(width: 10, height: 10)
                                    Text(label.displayName)
                                }
                            }
                        }
                        Toggle(
                            "Mixed",
                            isOn: membershipBinding(.mixed, in: $selectedColors)
                        )
                    }
                    .accessibilityLabel("Color labels")
                    .accessibilityValue(colorSelectionSummary)
                }

                exportPreview
            }

            if mode == .metadataXMP {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Write Louppe decisions, stars, and colors to XMP sidecars for editing apps. Original photos stay unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    editingAppOptions
                }
            } else {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Include XMP sidecars for editing apps",
                        isOn: includeXMPBinding
                    )

                    Text(copyMoveXMPExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if excludedACRCompanionCount > 0 {
                        Text("\(excludedACRCompanionCount) Lightroom .acr companion\(excludedACRCompanionCount == 1 ? "" : "s") will not be included and will remain in the source folder.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if xmpInclusionChoice.isIncluded {
                        editingAppOptions
                    }
                }
            }

            if mode == .move {
                Text("Move works only to another folder on the same drive. For another drive or card, choose Copy. Moved items leave this session and can't be undone in Louppe.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            if selectionSnapshot.mixedDecisionCount > 0 {
                Text("\(selectionSnapshot.mixedDecisionCount) included RAW+JPEG pair\(selectionSnapshot.mixedDecisionCount == 1 ? " has" : "s have") different file decisions and \(selectionSnapshot.mixedDecisionCount == 1 ? "is" : "are") treated as undecided.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            if scopeMixedStarCount > 0 || scopeMixedColorCount > 0 {
                Text(mixedMetadataNote)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            if scopeRatingCount(.undecided) > 0 && !selectedRatings.contains(.undecided) {
                let count = scopeRatingCount(.undecided)
                Text("\(count) item\(count == 1 ? "" : "s") still undecided in this scope — they won't be exported.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        } actions: {
            HStack {
                Spacer()
                Button("Cancel") { store.isExportPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .metadataXMP ? "Review Sidecars…" : "Choose Destination…") {
                    if mode == .metadataXMP {
                        store.prepareXMPPublication(
                            selected: selectionSnapshot.selectedItems(from: store.items),
                            profile: xmpProfile,
                            visibleDecisionKeywords: effectiveVisibleDecisionKeywords,
                            allowExternalLabelReplacement: allowExternalLabelReplacement
                        )
                    } else {
                        exporter.promptDestinationAndExport(
                            sourceFolder: store.sourceFolder,
                            selected: selectionSnapshot.selectedItems(from: store.items),
                            familyContextItems: store.items,
                            sessionGeneration:
                                store.xmpConflictSessionGeneration,
                            mode: mode,
                            includeXMP: xmpInclusionChoice.isIncluded,
                            xmpProfile: xmpProfile,
                            visibleDecisionKeywords: effectiveVisibleDecisionKeywords,
                            allowExternalLabelReplacement: allowExternalLabelReplacement,
                            onOperationWillStart: { store.exportWillStart(mode: $0) },
                            onOperationDidFinish: {
                                store.finishExport(
                                    mode: $0,
                                    movedIDs: $1,
                                    requiresRecovery: $2,
                                    interruptionMessage: $3
                                )
                            }
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    selectionSnapshot.itemCount == 0
                        || (mode != .metadataXMP && isCheckingExistingXMP)
                )
            }
        }
        }
    }

    private var selectionPredicate: ExportSelectionPredicate {
        ExportSelectionPredicate(
            decisions: selectedRatings,
            starStates: selectedStars,
            colorStates: selectedColors
        )
    }

    private var currentConfiguration: ExportSelectionConfiguration {
        ExportSelectionConfiguration(
            scope: scope,
            predicate: selectionPredicate
        )
    }

    private var activeQuickPick: ExportQuickPick? {
        if !store.selectedIndices.isEmpty,
           currentConfiguration == .preset(.allSelected) {
            return .allSelected
        }
        if currentConfiguration == .preset(
            .keepers,
            keeperScope: store.exportKeepersRequested ? .all : .filtered
        ) {
            return .keepers
        }
        if currentConfiguration == .preset(.fourFiveStars) {
            return .fourFiveStars
        }
        return nil
    }

    private var quickPickRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick picks")
                    .font(.caption.weight(.semibold))
                if activeQuickPick == nil {
                    Text("Custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                quickPickButton("Keepers (Yes)", pick: .keepers)
                    .help(store.exportKeepersRequested
                        ? "Yes decisions, with any stars or colors, from the whole folder"
                        : "Yes decisions, with any stars or colors, from the current filter")
                quickPickButton("4–5 Stars", pick: .fourFiveStars)
                    .help("4 or 5 stars with any decision or color, from the current filter")
                quickPickButton("All Selected", pick: .allSelected)
                    .help("Every explicitly selected item, regardless of decision, stars, or color")
                    .disabled(store.selectedIndices.isEmpty)
            }
        }
    }

    private func quickPickButton(
        _ title: String,
        pick: ExportQuickPick
    ) -> some View {
        let isActive = activeQuickPick == pick
        return Button {
            applyQuickPick(pick)
        } label: {
            HStack(spacing: 4) {
                if isActive { Image(systemName: "checkmark") }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func applyQuickPick(_ pick: ExportQuickPick) {
        if pick == .allSelected && store.selectedIndices.isEmpty { return }
        applyConfiguration(.preset(
            pick,
            keeperScope: store.exportKeepersRequested ? .all : .filtered
        ))
    }

    private func applyConfiguration(_ configuration: ExportSelectionConfiguration) {
        scope = configuration.scope
        selectedRatings = configuration.predicate.decisions
        selectedStars = configuration.predicate.starStates
        selectedColors = configuration.predicate.colorStates
    }

    private var exportPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exportDescription)
                .font(.callout.weight(.semibold))
            Text(exclusionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var exclusionDescription: String {
        let excludedByChoices = max(0, scopeIndices.count - selectionSnapshot.itemCount)
        let outsideScope = max(0, store.items.count - scopeIndices.count)
        var parts: [String] = []
        if excludedByChoices > 0 {
            parts.append("\(excludedByChoices) excluded by decision, stars, or color")
        }
        if outsideScope > 0 {
            parts.append("\(outsideScope) outside this scope")
        }
        return parts.isEmpty ? "Nothing excluded." : parts.joined(separator: " · ") + "."
    }

    private var editingAppOptions: some View {
        DisclosureGroup("Editing app options", isExpanded: $showEditingAppOptions) {
            VStack(alignment: .leading, spacing: 9) {
                exportMenuRow("Application") {
                    Picker("Application", selection: $xmpProfile) {
                        ForEach(XMPApplicationProfile.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
                if xmpProfile == .universal {
                    Toggle(
                        "Make decisions visible as keywords",
                        isOn: $universalDecisionKeywords
                    )
                }
                Toggle(
                    "Allow replacing or removing external color labels",
                    isOn: $allowExternalLabelReplacement
                )
                if allowExternalLabelReplacement {
                    Text("Confirmed: an external xmp:Label may be replaced or removed when it conflicts with the selected Louppe color.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
    }

    // MARK: - Multi-destination Copy

    private var routingSummaryView: some View {
        SheetForm(title: "Route Copies") {
            Picker("Mode", selection: $mode) {
                Text("Copy").tag(ExportMode.copy)
                Text("Move").tag(ExportMode.move)
                Text("Metadata (XMP)").tag(ExportMode.metadataXMP)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Route copies to multiple folders", isOn: $isRoutingCopies)
                .accessibilityHint("Turn off to return to normal one-folder Copy")

            exportScopeRow

            Text("Choose which media to copy into each folder. Items that match no route stay in the source folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            Group {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($routingRoutes) { $route in
                        routingRouteEditor($route)
                    }
                }
                .padding(.horizontal, 1)
            }

            HStack {
                Button("Add Route") {
                    routingRoutes.append(MultiDestinationExportRoute(
                        predicate: .decision(.no)
                    ))
                }
                .disabled(routingRoutes.count >= 12)
                Spacer()
                Text(routingMatchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = routingValidationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .accessibilityLabel("Routing issue: \(message)")
            }

            if !routingEvaluation.unmatchedItemIndices.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Unmatched — will stay in the source folder")
                        .font(.caption.weight(.semibold))
                    Text(routingItemList(routingEvaluation.unmatchedItemIndices))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            Toggle("Include XMP sidecars (off by default)", isOn: $routingIncludesXMP)
            Text("Sidecars follow their media. Files that share an XMP sidecar must go to the same folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

        } actions: {
            HStack {
                Spacer()
                Button("Cancel") { store.isExportPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Review Copy Plan…") {
                    exporter.prepareMultiDestinationExport(
                        routes: routingRoutes,
                        items: scopedItems,
                        sourceFolder: store.sourceFolder,
                        includeXMP: routingIncludesXMP,
                        familyContextItems: store.items,
                        sessionGeneration: store.xmpConflictSessionGeneration,
                        xmpProfile: xmpProfile,
                        visibleDecisionKeywords: effectiveVisibleDecisionKeywords,
                        allowExternalLabelReplacement:
                            allowExternalLabelReplacement,
                        onOperationWillStart: { store.exportWillStart(mode: $0) },
                        onOperationDidFinish: {
                            store.finishExport(
                                mode: $0,
                                movedIDs: $1,
                                requiresRecovery: $2,
                                interruptionMessage: $3
                            )
                        }
                    )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!routingCanReview)
            }
        }
    }

    private func routingRouteEditor(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> some View {
        let routeID = route.wrappedValue.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(route.wrappedValue.predicate.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Remove") {
                    routingRoutes.removeAll { $0.id == routeID }
                }
                .disabled(routingRoutes.count == 1)
            }

            HStack {
                Picker("Match", selection: routingDimensionBinding(route)) {
                    ForEach(MultiDestinationRoutePredicate.Dimension.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 145)

                routingValuePicker(route)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Text("Destination")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(route.wrappedValue.destination?.lastPathComponent ?? "Choose Folder…") {
                    chooseRoutingDestination(routeID)
                }
                .accessibilityLabel(
                    route.wrappedValue.destination == nil
                        ? "Choose destination for \(route.wrappedValue.predicate.displayName)"
                        : "Change destination for \(route.wrappedValue.predicate.displayName)"
                )
            }
            if let destination = route.wrappedValue.destination {
                Text(destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        }
    }

    @ViewBuilder
    private func routingValuePicker(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> some View {
        switch route.wrappedValue.predicate.dimension {
        case .decision:
            Picker("Decision", selection: routingDecisionBinding(route)) {
                ForEach([Rating.yes, .no, .undecided], id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .labelsHidden()
        case .stars:
            Picker("Stars", selection: routingStarsBinding(route)) {
                ForEach(routingStarStates, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .labelsHidden()
        case .color:
            Picker("Color", selection: routingColorBinding(route)) {
                ForEach(routingColorStates, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .labelsHidden()
        case .fileType:
            Picker("File type", selection: routingFileTypeBinding(route)) {
                ForEach(store.availableTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .labelsHidden()
            .disabled(store.availableTypes.isEmpty)
        case .mediaKind:
            Picker("Media type", selection: routingMediaKindBinding(route)) {
                Text(MediaKind.photo.label).tag(MediaKind.photo)
                Text(MediaKind.video.label).tag(MediaKind.video)
                Text(MediaKind.audio.label).tag(MediaKind.audio)
            }
            .labelsHidden()
        }
    }

    private var routingStarStates: [PhotoItemStarRatingState] {
        [.unrated] + StarRating.allCases.map(PhotoItemStarRatingState.stars) + [.mixed]
    }

    private var routingColorStates: [PhotoItemColorLabelState] {
        [.none] + PhotoColorLabel.allCases.map(PhotoItemColorLabelState.label) + [.mixed]
    }

    private func routingDimensionBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<MultiDestinationRoutePredicate.Dimension> {
        Binding {
            route.wrappedValue.predicate.dimension
        } set: { dimension in
            switch dimension {
            case .decision: route.wrappedValue.predicate = .decision(.yes)
            case .stars: route.wrappedValue.predicate = .stars(.unrated)
            case .color: route.wrappedValue.predicate = .color(.none)
            case .fileType:
                route.wrappedValue.predicate = .fileType(
                    store.availableTypes.first ?? "Unknown"
                )
            case .mediaKind: route.wrappedValue.predicate = .mediaKind(.photo)
            }
        }
    }

    private func routingDecisionBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<Rating> {
        Binding {
            if case .decision(let value) = route.wrappedValue.predicate {
                return value
            }
            return .yes
        } set: { route.wrappedValue.predicate = .decision($0) }
    }

    private func routingStarsBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<PhotoItemStarRatingState> {
        Binding {
            if case .stars(let value) = route.wrappedValue.predicate {
                return value
            }
            return .unrated
        } set: { route.wrappedValue.predicate = .stars($0) }
    }

    private func routingColorBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<PhotoItemColorLabelState> {
        Binding {
            if case .color(let value) = route.wrappedValue.predicate {
                return value
            }
            return .none
        } set: { route.wrappedValue.predicate = .color($0) }
    }

    private func routingFileTypeBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<String> {
        Binding {
            if case .fileType(let value) = route.wrappedValue.predicate {
                return value
            }
            return store.availableTypes.first ?? "Unknown"
        } set: { route.wrappedValue.predicate = .fileType($0) }
    }

    private func routingMediaKindBinding(
        _ route: Binding<MultiDestinationExportRoute>
    ) -> Binding<MediaKind> {
        Binding {
            if case .mediaKind(let value) = route.wrappedValue.predicate {
                return value
            }
            return .photo
        } set: { route.wrappedValue.predicate = .mediaKind($0) }
    }

    private var routingCanReview: Bool {
        !routingRoutes.isEmpty
            && routingRoutes.allSatisfy { $0.destination != nil }
            && routingEvaluation.overlappingItemIndices.isEmpty
            && routingEvaluation.emptyRouteIDs.isEmpty
    }

    private var routingMatchSummary: String {
        let routed = scopedItems.count
            - routingEvaluation.unmatchedItemIndices.count
            - routingEvaluation.overlappingItemIndices.count
        return "\(max(routed, 0)) routed · \(routingEvaluation.unmatchedItemIndices.count) unmatched"
    }

    private var routingValidationMessage: String? {
        if routingRoutes.isEmpty { return "Add at least one route." }
        if routingRoutes.contains(where: { $0.destination == nil }) {
            return "Choose a destination folder for every route."
        }
        if !routingEvaluation.overlappingItemIndices.isEmpty {
            return "\(routingEvaluation.overlappingItemIndices.count) item\(routingEvaluation.overlappingItemIndices.count == 1 ? "" : "s") match more than one route: \(routingItemList(routingEvaluation.overlappingItemIndices))."
        }
        if !routingEvaluation.emptyRouteIDs.isEmpty {
            return "Every route must match at least one item before it can be reviewed."
        }
        return nil
    }

    private func routingItemList(_ indices: [Int], limit: Int = 8) -> String {
        let names = indices.prefix(limit).compactMap { index in
            scopedItems.indices.contains(index) ? scopedItems[index].displayName : nil
        }
        let remainder = max(0, indices.count - names.count)
        return names.joined(separator: ", ")
            + (remainder > 0 ? " and \(remainder) more" : "")
    }

    private func refreshRoutingEvaluation() {
        routingEvaluation = MultiDestinationExportEvaluation.evaluate(
            routes: routingRoutes,
            items: scopedItems
        )
    }

    private func chooseRoutingDestination(_ routeID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where this route will copy its matching media."
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let destination = panel.url,
              let index = routingRoutes.firstIndex(where: { $0.id == routeID }) else {
            return
        }
        exporter.retainRoutingDestinationAccess(destination, for: routeID)
        routingRoutes[index].destination = destination
    }

    private var multiDestinationPreparationView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking routing copy plan…")
                .font(.headline)
            Text("Louppe is validating every destination, reserving collision-safe names, and preparing one recovery record before any file can change.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel") { exporter.cancelMultiDestinationPreparation() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func multiDestinationConfirmationView(
        _ plan: MultiDestinationExportPlan
    ) -> some View {
        SheetForm(title: "Review Copy Plan") {
            Text("\(plan.totalFiles) file\(plan.totalFiles == 1 ? "" : "s") will be copied. Originals stay where they are.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            Group {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(plan.routes) { route in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(route.route.predicate.displayName) → \(route.destination.path)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(route.itemCount) item\(route.itemCount == 1 ? "" : "s") · \(route.mediaFileCount) media file\(route.mediaFileCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(route.files) { file in
                                Text(filePreviewText(file))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(file.role == .media ? .primary : .secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Unmatched — not copied")
                            .font(.subheadline.weight(.semibold))
                        if plan.unmatchedNames.isEmpty {
                            Text("Every current item is routed exactly once.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.unmatchedNames, id: \.self) { name in
                                Text(name)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if let xmp = plan.xmpPlan {
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("XMP sidecars")
                                .font(.subheadline.weight(.semibold))
                            Text("\(xmp.existingRecognizedPacketCount) existing · \(xmp.count(.create)) to create · \(xmp.count(.update)) to update · \(xmp.applicationPacketCount) application packet\(xmp.applicationPacketCount == 1 ? "" : "s") copied unchanged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !xmp.issueFamilies.isEmpty {
                                Text("\(xmp.issueFamilies.count) sidecar \(xmp.issueFamilies.count == 1 ? "family is" : "families are") skipped because it could not be prepared safely; listed media files still copy.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            Text("If copying is interrupted, completed copies remain in their destination folders. Originals stay unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

        } actions: {
            HStack {
                Button("Back") { exporter.backFromMultiDestinationConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start Copy") { exporter.confirmMultiDestinationExport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func filePreviewText(
        _ file: MultiDestinationExportPlan.RoutePreview.FilePreview
    ) -> String {
        let copy = file.sourcePath == file.destinationPath
            ? file.sourcePath
            : "\(file.sourcePath) → \(file.destinationPath)"
        switch file.role {
        case .media: return copy
        case .applicationXMP: return "\(copy) (XMP application packet)"
        case .preparedXMP: return "\(copy) (prepared XMP sidecar)"
        case .retiredXMPSource: return "\(copy) (XMP safety record)"
        }
    }

    private func refreshSelectionSnapshot() {
        selectionSnapshot = currentConfiguration.snapshot(
            items: store.items,
            filtered: store.visibleIndices,
            selected: store.selectedIndices
        )
        scheduleXMPInspection()
    }

    private func applyConflictResolutions(
        _ requests: [XMPConflictResolutionRequest],
        origin: XMPConflictResolutionOrigin
    ) {
        let outcome = store.applyXMPConflictResolutions(requests)
        conflictResolver = nil
        conflictResolutionNotice = resolutionNotice(outcome)

        // Resolution may change the active Export predicate. Rebuild it from
        // the authoritative session before either planner captures new input.
        refreshSelectionSnapshot()
        let selected = selectionSnapshot.selectedItems(from: store.items)
        switch origin {
        case .standalone:
            store.resetXMPPublication()
            guard !selected.isEmpty else { return }
            store.prepareXMPPublication(
                selected: selected,
                profile: xmpProfile,
                visibleDecisionKeywords: effectiveVisibleDecisionKeywords,
                allowExternalLabelReplacement:
                    allowExternalLabelReplacement
            )
        case .copyOrMove:
            exporter.reprepareXMPExportAfterResolution(
                selected: selected,
                familyContextItems: store.items,
                sessionGeneration: store.xmpConflictSessionGeneration
            )
        }
    }

    private func resolutionNotice(
        _ outcome: XMPConflictResolutionOutcome
    ) -> String? {
        var parts: [String] = []
        if outcome.appliedCount > 0 {
            parts.append(
                "Unified \(outcome.appliedCount) RAW+JPEG conflict\(outcome.appliedCount == 1 ? "" : "s") in Louppe. Review the new plan before continuing."
            )
        }
        let stale = outcome.staleConflictIDs.count
        if stale > 0 {
            parts.append(
                "\(stale) conflict\(stale == 1 ? " changed while the resolver was open and was" : "s changed while the resolver was open and were") not overwritten. The refreshed plan shows the current values."
            )
        }
        let ineligible = outcome.ineligibleConflictIDs.count
        if ineligible > 0 {
            parts.append(
                "\(ineligible) conflict choice\(ineligible == 1 ? " was" : "s were") rejected because the files no longer formed one safe RAW+JPEG pair."
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var includeXMPBinding: Binding<Bool> {
        Binding {
            xmpInclusionChoice.isIncluded
        } set: { value in
            xmpInclusionChoice.setManually(value)
        }
    }

    private func scheduleXMPInspection() {
        cancelXMPInspection()
        guard mode != .metadataXMP else {
            isCheckingExistingXMP = false
            excludedACRCompanionCount = 0
            return
        }
        let requestID = UUID()
        xmpInspectionID = requestID
        isCheckingExistingXMP = true
        let selected = selectionSnapshot.selectedItems(from: store.items)
        let context = store.items
        let work = Task.detached(priority: .utility) {
            try? XMPExportPlanner.inspectSources(
                selected: selected,
                familyContextItems: context
            )
        }
        xmpInspectionWork = work
        xmpInspectionTask = Task {
            let inspection = await work.value
            guard !Task.isCancelled, xmpInspectionID == requestID else {
                return
            }
            existingXMPCount = inspection?.recognizedPacketCount ?? 0
            excludedACRCompanionCount =
                inspection?.excludedACRCompanionCount ?? 0
            isCheckingExistingXMP = false
            xmpInclusionChoice.applyRecognizedPacketCount(existingXMPCount)
        }
    }

    private func cancelXMPInspection() {
        xmpInspectionWork?.cancel()
        xmpInspectionWork = nil
        xmpInspectionTask?.cancel()
        xmpInspectionTask = nil
    }

    private var copyMoveXMPExplanation: String {
        if isCheckingExistingXMP {
            return "Checking the selected photos for existing XMP sidecars…"
        }
        if xmpInclusionChoice.isIncluded {
            return "XMP carries Louppe decisions, stars, and colors to editing apps. Existing sidecars are included; missing ones are created."
        }
        if existingXMPCount > 0 {
            return mode == .move
                ? "Existing XMP sidecars will remain in the source folder."
                : "Existing sidecars will stay at the source and will not be copied."
        }
        return "No existing XMP sidecars found. Turn on to create editing-app ratings beside the exported media."
    }

    private var exportDescription: String {
        if selectedRatings.isEmpty {
            return "Select at least one decision tile above to export."
        }
        if selectedStars.isEmpty {
            return "Select at least one star rating to export."
        }
        if selectedColors.isEmpty {
            return "Select at least one color label to export."
        }
        if selectionSnapshot.itemCount == 0 {
            return selectedRatings == [.yes]
                && selectedStars == ExportSelectionPredicate.allStarStates
                && selectedColors == ExportSelectionPredicate.allColorStates
                ? "Mark some items Yes (press F) before exporting."
                : "No items match all selected metadata."
        }
        let verb: String
        switch mode {
        case .copy: verb = "copied"
        case .move: verb = "moved"
        case .metadataXMP: verb = "prepared for XMP publication"
        }
        var text = "\(selectionSnapshot.itemCount) item\(selectionSnapshot.itemCount == 1 ? "" : "s") will be \(verb)"
        if selectionSnapshot.physicalFileCount != selectionSnapshot.itemCount {
            text += " (\(selectionSnapshot.physicalFileCount) files, including RAW+JPEG pairs)"
        }
        text += mode == .copy || mode == .metadataXMP
            ? ". Originals are never touched."
            : "."
        return text
    }

    private var effectiveVisibleDecisionKeywords: Bool {
        xmpProfile == .universal
            ? universalDecisionKeywords
            : xmpProfile.usesVisibleDecisionKeywordsByDefault
    }

    private var mixedMetadataNote: String {
        var parts: [String] = []
        var total = 0
        if scopeMixedStarCount > 0 {
            parts.append("\(scopeMixedStarCount) mixed-star pair\(scopeMixedStarCount == 1 ? "" : "s")")
            total += scopeMixedStarCount
        }
        if scopeMixedColorCount > 0 {
            parts.append("\(scopeMixedColorCount) mixed-color pair\(scopeMixedColorCount == 1 ? "" : "s")")
            total += scopeMixedColorCount
        }
        return parts.joined(separator: " and ")
            + (total == 1 ? " matches" : " match")
            + " only when Mixed is selected in the corresponding menu."
    }

    private var scopeIndices: [Int] {
        currentConfiguration.candidateIndices(
            all: store.items.indices,
            filtered: store.visibleIndices,
            selected: store.selectedIndices
        )
    }

    private var scopedItems: [PhotoItem] {
        scopeIndices.compactMap {
            store.items.indices.contains($0) ? store.items[$0] : nil
        }
    }

    private func scopeRatingCount(_ rating: Rating) -> Int {
        scopedItems.count { $0.ratingState.effectiveRating == rating }
    }

    private var scopeMixedStarCount: Int {
        scopedItems.count { $0.starRatingState == .mixed }
    }

    private var scopeMixedColorCount: Int {
        scopedItems.count { $0.colorLabelState == .mixed }
    }

    private var exportScopeRow: some View {
        exportMenuRow("Scope") {
            Picker("Scope", selection: $scope) {
                exportScopeLabel("All Media", scope: .all)
                    .tag(CleanUpScope.all)
                exportScopeLabel("Filtered", scope: .filtered)
                    .tag(CleanUpScope.filtered)
                exportScopeLabel("Selected", scope: .selected)
                    .tag(CleanUpScope.selected)
                    .disabled(store.selectedIndices.isEmpty)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Media to consider")
        }
    }

    private func exportScopeLabel(_ title: String, scope: CleanUpScope) -> Text {
        let count = scope.candidateIndices(
            all: store.items.indices,
            filtered: store.visibleIndices,
            selected: store.selectedIndices
        ).count
        return Text("\(title) (\(count))")
    }

    private var starSelectionSummary: String {
        selectionSummary(
            selectedStars,
            all: ExportSelectionPredicate.allStarStates,
            label: starStateLabel
        )
    }

    private var colorSelectionSummary: String {
        selectionSummary(
            selectedColors,
            all: ExportSelectionPredicate.allColorStates,
            label: colorStateLabel
        )
    }

    private func selectionSummary<Value: Hashable>(
        _ selected: Set<Value>,
        all: Set<Value>,
        label: (Value) -> String
    ) -> String {
        if selected == all { return "All selected" }
        if selected.isEmpty { return "None selected" }
        if selected.count == 1, let only = selected.first {
            return label(only)
        }
        return "\(selected.count) selected"
    }

    private func starStateLabel(_ state: PhotoItemStarRatingState) -> String {
        switch state {
        case .unrated: return "Unrated"
        case .stars(let rating):
            return rating == .one ? "1 star" : "\(rating.count) stars"
        case .mixed: return "Mixed"
        }
    }

    private func colorStateLabel(_ state: PhotoItemColorLabelState) -> String {
        switch state {
        case .none: return "None"
        case .label(let label): return label.displayName
        case .mixed: return "Mixed"
        }
    }

    private func membershipBinding<Value: Hashable>(
        _ value: Value,
        in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding {
            selection.wrappedValue.contains(value)
        } set: { isSelected in
            if isSelected {
                selection.wrappedValue.insert(value)
            } else {
                selection.wrappedValue.remove(value)
            }
        }
    }

    private func exportMenuRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            content()
                .labelsHidden()
                .frame(width: 170)
        }
    }

    private func ratingTile(_ rating: Rating, count: Int, label: String, color: Color) -> some View {
        let isSelected = selectedRatings.contains(rating)
        return Button {
            if isSelected {
                selectedRatings.remove(rating)
            } else {
                selectedRatings.insert(rating)
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.title.bold())
                    .foregroundStyle(isSelected ? color : Color.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 70, maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected
                        ? color.opacity(0.4)
                        : Color(nsColor: .separatorColor))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Click to leave \(label) items out" : "Click to include \(label) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var xmpContent: some View {
        switch store.xmpPublicationState {
        case .idle:
            summaryView
        case .preflighting(let done, let total):
            xmpProgressView(
                title: "Checking sidecars…",
                done: done,
                total: total,
                stopTitle: "Stop Checking"
            )
        case .awaitingConfirmation(let plan):
            xmpPreflightView(plan)
        case .publishing(let done, let total):
            xmpProgressView(
                title: "Writing Metadata (XMP)…",
                done: done,
                total: total,
                stopTitle: "Stop Writing"
            )
        case .cancelling:
            VStack(spacing: 12) {
                ProgressView()
                Text("Stopping at a safe boundary…")
                    .font(.headline)
                Text("An atomic sidecar replacement already in progress will finish safely first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .finished(let result):
            xmpFinishedView(result)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("OK") { store.resetXMPPublication() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func xmpProgressView(
        title: String,
        done: Int,
        total: Int,
        stopTitle: String
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            ProgressView(
                value: Double(done),
                total: Double(max(total, 1))
            )
            Text("\(done) of \(total) sidecar families")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(stopTitle) { store.cancelXMPPublication() }
        }
    }

    private func xmpPreflightView(_ plan: XMPPublicationPlan) -> some View {
        let issues = plan.entries.filter { !$0.category.canPublish }
        let changes = plan.changeCounts
        return SheetForm(title: "Metadata (XMP)") {
            Text("Ready to write with \(plan.profile.displayName)")
                .font(.headline)

            VStack(spacing: 6) {
                xmpCountRow("Selected Louppe items", plan.selectedItemCount)
                xmpCountRow("Physical photo files", plan.physicalFileCount)
                xmpCountRow("Sidecars to create", plan.count(.create))
                xmpCountRow("Sidecars to update", plan.count(.update))
                xmpCountRow("Already current", plan.count(.alreadyCurrent))
                xmpCountRow(
                    "Existing recognized sidecars",
                    plan.existingRecognizedSidecarCount
                )
                ForEach(
                    XMPPublicationCategory.allCases.filter {
                        !$0.canPublish
                            && $0 != .copyUnchangedApplicationPacket
                            && plan.count($0) > 0
                    },
                    id: \.rawValue
                ) { category in
                    xmpCountRow(category.label, plan.count(category))
                }
            }

            Text(xmpApplicationNote(plan.profile))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            if !plan.bestEffortFilenames.isEmpty {
                warningText("This application may ignore sidecars for JPEG, TIFF, DNG, HEIC, or PNG because it normally expects embedded metadata. Louppe will not modify the original. Affected: \(fileList(plan.bestEffortFilenames))")
            }
            if changes.stars + changes.colors + changes.flags + changes.keywords > 0 {
                warningText(
                    "Existing non-empty values will change — stars: \(changes.stars), colors: \(changes.colors), flags: \(changes.flags), reserved decision keywords: \(changes.keywords)."
                )
            }
            if plan.applicationPacketCount > 0 {
                Text("\(plan.applicationPacketCount) extension-qualified application packet\(plan.applicationPacketCount == 1 ? "" : "s") will remain unchanged beside the originals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            if plan.excludedACRCompanionCount > 0 {
                warningText("\(plan.excludedACRCompanionCount) Lightroom .acr companion\(plan.excludedACRCompanionCount == 1 ? "" : "s") will remain untouched beside the originals. Louppe does not read or modify Lightroom heavy-edit data.")
            }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("These files will be skipped")
                        .font(.caption.weight(.semibold))
                    ForEach(issues.prefix(6)) { issue in
                        Text("\(issue.filenames.joined(separator: ", ")) — \(issue.category.label)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if issues.count > 6 {
                        Text("…and \(issues.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let conflictResolutionNotice {
                warningText(conflictResolutionNotice)
            }

        } actions: {
            HStack {
                Button("Back") { store.resetXMPPublication() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !plan.resolvableSameStemConflicts.isEmpty {
                    Button("Resolve RAW + JPEG Conflicts…") {
                        conflictResolutionNotice = nil
                        conflictResolver = XMPConflictResolverPresentation(
                            conflicts: plan.resolvableSameStemConflicts,
                            origin: .standalone
                        )
                    }
                }
                Button("Write Sidecars") {
                    store.startXMPPublication(planID: plan.id)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(plan.publishableCount == 0)
            }
        }
    }

    private func xmpFinishedView(_ result: XMPPublicationResult) -> some View {
        let hasDetails = !result.details.isEmpty
        return VStack(spacing: 14) {
            Image(systemName: result.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(result.isClean ? Color.louppeAccent : Color.secondary)
            Text(result.cancelled
                ? "Metadata writing stopped"
                : result.isClean
                    ? "Metadata (XMP) complete"
                    : "Metadata (XMP) finished with problems")
                .font(.title3.bold())

            VStack(spacing: 6) {
                xmpCountRow("Created", result.created)
                xmpCountRow("Updated", result.updated)
                xmpCountRow("Already current", result.alreadyCurrent)
                xmpCountRow("Skipped", result.skipped)
                xmpCountRow("Conflicts", result.conflicts)
                xmpCountRow("Failed", result.failed)
            }

            if result.cancelled {
                Text("Completed sidecars remain safely written. No partially replaced packet was left behind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if showXMPDetails, hasDetails {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.details) { detail in
                            Text("\(detail.filenames.joined(separator: ", ")) — \(detail.category.label): \(detail.message)")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            HStack {
                if hasDetails {
                    Button(showXMPDetails ? "Hide Details" : "Show Details") {
                        showXMPDetails.toggle()
                    }
                }
                Button("Done") {
                    store.resetXMPPublication()
                    store.isExportPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func xmpCountRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.callout)
    }

    private func warningText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
    }

    private func fileList(_ names: [String]) -> String {
        if names.count <= 4 { return names.joined(separator: ", ") }
        return names.prefix(4).joined(separator: ", ")
            + ", and \(names.count - 4) more"
    }

    private func xmpApplicationNote(_ profile: XMPApplicationProfile) -> String {
        switch profile {
        case .lightroomClassic:
            return "After publication, use Lightroom Classic’s Read Metadata from Files command so its catalog sees the sidecars."
        case .captureOne:
            return "Capture One may need XMP Auto Sync enabled or a manual metadata reload."
        case .darktable:
            return "darktable reads the portable stem sidecar on import; its processing-history packet remains unchanged."
        case .bridge:
            return "Bridge reads stars, colors, and Louppe’s visible decision keywords from the sidecars."
        case .universal:
            return "Universal XMP keeps stars, colors, and the lossless Louppe decision in portable fields."
        }
    }

    private func workingView(
        mode: ExportMode,
        completedBytes: Int64,
        totalBytes: Int64
    ) -> some View {
        let verb = mode == .copy ? "copied" : "moved"
        let completed = ByteCountFormatter.string(
            fromByteCount: max(0, completedBytes),
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: max(0, totalBytes),
            countStyle: .file
        )
        return VStack(spacing: 12) {
            Text(mode == .copy ? "Copying media…" : "Moving media…")
                .font(.headline)
            ProgressView(
                value: Double(max(0, completedBytes)),
                total: Double(max(totalBytes, 1))
            )
            Text("\(completed) of \(total) \(verb)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if mode == .copy {
                Button(exporter.isCancellingCopy ? "Stopping…" : "Stop Copying…") {
                    exporter.requestCopyStopConfirmation()
                }
                .disabled(exporter.isCancellingCopy)
            }
        }
    }

    private func xmpExportPreparationView(mode: ExportMode) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking XMP sidecars…")
                .font(.headline)
            Text("Checking the selected files and sidecars before \(mode == .copy ? "copying" : "moving") anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Stop Checking") {
                exporter.cancelXMPPreparation()
            }
        }
    }

    private func xmpExportPreflightView(
        _ confirmation: ExportManager.XMPConfirmation
    ) -> some View {
        let plan = confirmation.plan
        let changes = plan.changeCounts
        return SheetForm(title: confirmation.mode == .copy ? "Copy with XMP" : "Move with XMP") {
            Text("Ready for \(confirmation.destination.lastPathComponent)")
                .font(.headline)

            VStack(spacing: 6) {
                xmpCountRow("Selected Louppe items", plan.selectedItemCount)
                xmpCountRow("Physical media files", plan.physicalFileCount)
                xmpCountRow(
                    "Existing recognized sidecars",
                    plan.existingRecognizedPacketCount
                )
                xmpCountRow("Sidecars to create", plan.count(.create))
                xmpCountRow("Sidecars to update", plan.count(.update))
                xmpCountRow(
                    "Already current",
                    plan.count(.alreadyCurrent)
                )
                if plan.applicationPacketCount > 0 {
                    xmpCountRow(
                        "Application packets copied unchanged",
                        plan.applicationPacketCount
                    )
                }
                ForEach(
                    XMPPublicationCategory.allCases.filter {
                        !$0.canPublish
                            && $0 != .copyUnchangedApplicationPacket
                            && plan.count($0) > 0
                    },
                    id: \.rawValue
                ) { category in
                    xmpCountRow(category.label, plan.count(category))
                }
                if plan.excludedACRCompanionCount > 0 {
                    xmpCountRow(
                        "Lightroom .acr companions excluded",
                        plan.excludedACRCompanionCount
                    )
                }
            }

            if changes.stars + changes.colors + changes.flags
                + changes.keywords > 0 {
                Text("Existing values to update: \(changes.stars) star, \(changes.colors) color, \(changes.flags) decision flag, \(changes.keywords) keyword set.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            if !plan.bestEffortFilenames.isEmpty {
                Text("Some applications may ignore sidecars for: \(plan.bestEffortFilenames.joined(separator: ", ")). Original media will not be modified.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            if !plan.issueFamilies.isEmpty {
                Group {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.issueFamilies, id: \.id) { family in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(family.filenames.joined(separator: ", "))
                                    .font(.caption.weight(.semibold))
                                Text(family.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let conflictResolutionNotice {
                Text(conflictResolutionNotice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
            }

            Text("Included XMP sidecars follow their media to the destination.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

        } actions: {
            HStack {
                Button("Back") { exporter.backFromXMPConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !plan.resolvableSameStemConflicts.isEmpty {
                    Button("Resolve RAW + JPEG Conflicts…") {
                        conflictResolutionNotice = nil
                        conflictResolver = XMPConflictResolverPresentation(
                            conflicts: plan.resolvableSameStemConflicts,
                            origin: .copyOrMove
                        )
                    }
                }
                Button(confirmation.mode == .copy ? "Start Copy" : "Start Move") {
                    exporter.confirmXMPExport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func finishedView(outcome: ExportManager.Outcome) -> some View {
        VStack(spacing: 14) {
            Image(systemName: outcome.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(outcome.isClean ? Color.louppeAccent : Color.secondary)
            Text(finishedTitle(for: outcome))
                .font(.title3.bold())
            Text(finishedMessage(for: outcome))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let xmp = outcome.xmpSummary {
                VStack(spacing: 6) {
                    xmpCountRow("Media \(outcome.mode == .copy ? "copied" : "moved")", xmp.mediaFiles)
                    xmpCountRow("Sidecars created", xmp.created)
                    xmpCountRow("Sidecars updated", xmp.updated)
                    xmpCountRow("Sidecars already current", xmp.alreadyCurrent)
                    xmpCountRow(
                        "Application packets copied unchanged",
                        xmp.copiedUnchanged
                    )
                    if xmp.unsupported > 0 {
                        xmpCountRow("Unsupported media", xmp.unsupported)
                    }
                    if xmp.skipped > 0 {
                        xmpCountRow("Skipped", xmp.skipped)
                    }
                    if xmp.conflicts > 0 {
                        xmpCountRow("Conflicts", xmp.conflicts)
                    }
                    if xmp.failed > 0 {
                        xmpCountRow("XMP failures", xmp.failed)
                    }
                }
            }
            HStack {
                Button(outcome.destinations.count > 1 ? "Show First Folder" : "Show in Finder") {
                    exporter.revealInFinder(outcome.destination)
                }
                Button("Done") {
                    store.isExportPresented = false
                    exporter.reset()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func finishedTitle(for outcome: ExportManager.Outcome) -> String {
        if outcome.recoveryRequired {
            return outcome.mode == .copy
                ? "Securing copied files"
                : "Securing moved files"
        }
        if outcome.cancelled { return "Copy stopped" }
        return outcome.isClean ? "Export complete" : "Export finished with problems"
    }

    private func finishedMessage(for outcome: ExportManager.Outcome) -> String {
        if outcome.recoveryRequired {
            let cause = outcome.failureMessage.map {
                $0.hasSuffix(".") ? "\($0) " : "\($0). "
            } ?? ""
            if outcome.mode == .copy {
                return cause
                    + "Louppe kept a durable record of the interrupted copy and is preserving every verified completed file while checking the unfinished transfer. Wait for the recovery notice before starting another file operation."
            }
            return cause
                + "Louppe kept a durable record of the interrupted move. Completed groups stay at the destination; incomplete groups return to their safe source state. Wait for the recovery notice before starting another file operation."
        }
        let verb = outcome.mode == .copy ? "copied" : "moved"
        let destinationText: String
        if outcome.destinations.count > 1 {
            destinationText = "across \(outcome.destinations.count) folders"
        } else {
            destinationText = "to \(outcome.destination.lastPathComponent)"
        }
        var text = "\(outcome.files) file\(outcome.files == 1 ? "" : "s") \(verb) \(destinationText)"
        switch outcome.mode {
        case .copy:
            if outcome.cancelled {
                text += ". Completed photos remain at the destination; the photo in progress was rolled back."
                if let reason = outcome.cancellationReason {
                    text += " \(reason.userMessage)"
                } else {
                    text += " Louppe did not record why this copy stopped; please send its diagnostic log with this report."
                }
            } else if outcome.failedPhotos > 0 {
                let agreement = outcome.failedPhotos == 1 ? "was" : "were"
                text += " — \(outcome.failedPhotos) item\(outcome.failedPhotos == 1 ? "" : "s") couldn't be copied and \(agreement) rolled back."
            } else {
                text += "."
            }
            if outcome.inconsistentPhotos > 0 {
                text += " For \(outcome.inconsistentPhotos), rollback also failed; check the destination for a partial pair."
            }
        case .move:
            if outcome.failedPhotos > 0 {
                text += " — \(outcome.failedPhotos) item\(outcome.failedPhotos == 1 ? "" : "s") couldn't be moved and stayed in the session."
            } else {
                text += "."
            }
            if outcome.inconsistentPhotos > 0 {
                text += " For \(outcome.inconsistentPhotos), rollback also failed; check both the source folder and the destination."
            }
        case .metadataXMP:
            break
        }
        if outcome.journalFailure {
            text += " Louppe's file-safety checks stopped the operation before another file was started; affected originals remain at their last verified location."
        }
        if let failure = outcome.failureMessage {
            text += failure.hasSuffix(".") ? " \(failure)" : " \(failure)."
        }
        return text
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
            Button("OK") {
                exporter.reset()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }
}
