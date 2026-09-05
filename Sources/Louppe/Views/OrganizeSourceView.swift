import SwiftUI
import UniformTypeIdentifiers

struct OrganizeSourceView: View {
    @ObservedObject var store: SessionStore

    @State private var scope: SourceOrganizationScope = .all
    @State private var configuration: SourceOrganizationConfiguration
    @State private var plan: SourceOrganizationPlan?
    @State private var planningError: String?
    @State private var isPlanning = false
    @State private var isReviewingMove = false
    @State private var planningTask: Task<Void, Never>?
    @State private var planningCancelFlag:
        SourceOrganizationPlanningCancelFlag?
    @State private var draggedKind: SourceOrganizationLevelKind?

    init(store: SessionStore) {
        self.store = store
        _configuration = State(initialValue:
            store.sourceOrganizationLaunchConfiguration
                ?? .initial(
                    hasMultipleTopLevelFolders:
                        store.hasMultipleOrganizationTopLevelFolders
                )
        )
    }

    var body: some View {
        Group {
            if let progress = store.organizationProgress {
                progressView(progress)
            } else if let outcome = store.organizationOutcome {
                outcomeView(outcome)
            } else if isReviewingMove, let plan {
                confirmationView(plan)
            } else {
                setupView
            }
        }
        .frame(width: 680, height: 650)
        .background(Color.appBackground)
        .tint(Color.louppeAccent)
        .interactiveDismissDisabled(store.isFileOperationRunning)
        .onAppear { refreshPlan() }
        .onDisappear {
            planningCancelFlag?.cancel()
            planningCancelFlag = nil
            planningTask?.cancel()
            planningTask = nil
        }
        .onChange(of: scope) { refreshPlan() }
        .onChange(of: configuration) { refreshPlan() }
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            sheetHeader(
                title: "Organize Source Folder",
                subtitle: "Move media into folders built from review and capture metadata."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Apply to") {
                        Picker("Apply to", selection: $scope) {
                            ForEach(SourceOrganizationScope.allCases, id: \.self) {
                                value in
                                Text("\(value.label) (\(store.organizationScopeCount(for: value)))")
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Divider()

                    section("Folder order") {
                        Text("Choose the folder levels, then drag enabled rows into priority order. The top row comes first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 0) {
                            ForEach(configuration.levels) { level in
                                levelRow(level)
                                if level.id != configuration.levels.last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    Color(nsColor: .separatorColor),
                                    lineWidth: 1
                                )
                        }

                        additionalMetadataMenu

                        if !levelBinding(.existingFolder).wrappedValue {
                            Label(
                                "Existing folder is off, so files are flattened into the new levels. Previous folders remain in place, even when empty.",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()

                    section("Place inside source folder") {
                        TextField("Folder name", text: $configuration.containerName)
                            .textFieldStyle(.roundedBorder)
                        Text("Louppe leaves previous folders and unrelated files untouched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    previewSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()

            HStack {
                if isPlanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking paths and sidecars…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    store.isOrganizePresented = false
                }
                Button(reviewButtonTitle) {
                    isReviewingMove = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.louppeAccent)
                .disabled(!canReviewMove)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private func levelRow(
        _ level: SourceOrganizationLevel
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(level.isEnabled ? .secondary : .tertiary)
                .frame(width: 14)
                .accessibilityHidden(true)

            Toggle(
                level.kind.label,
                isOn: levelBinding(level.kind)
            )
            .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            if level.isEnabled, level.kind == .existingFolder {
                Picker(
                    "Existing folder depth",
                    selection: $configuration.existingFolderDepth
                ) {
                    ForEach(
                        SourceOrganizationExistingFolderDepth.allCases,
                        id: \.self
                    ) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            if level.isEnabled, level.kind == .dateTaken {
                Picker(
                    "Date grouping",
                    selection: $configuration.dateGranularity
                ) {
                    ForEach(
                        SourceOrganizationDateGranularity.allCases,
                        id: \.self
                    ) { value in
                        Text(dateGranularityLabel(value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            if level.kind.isAdditionalMetadata {
                Button {
                    configuration.levels.removeAll { $0.kind == level.kind }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(level.kind.label)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onDrag {
            guard level.isEnabled else { return NSItemProvider() }
            draggedKind = level.kind
            return NSItemProvider(object: level.kind.rawValue as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: OrganizationLevelDropDelegate(
                destination: level.kind,
                dragged: $draggedKind,
                levels: $configuration.levels
            )
        )
        .opacity(level.isEnabled ? 1 : 0.62)
        .accessibilityElement(children: .contain)
        .accessibilityHint(
            level.isEnabled
                ? "Drag to change folder priority"
                : "Enable this level before reordering it"
        )
    }

    private var additionalMetadataMenu: some View {
        Menu("Add metadata field…") {
            ForEach(
                SourceOrganizationLevelKind.allCases.filter {
                    $0.isAdditionalMetadata
                        && !configuration.levels.map(\.kind).contains($0)
                }
            ) { kind in
                Button(kind.label) {
                    configuration.levels.append(SourceOrganizationLevel(
                        kind: kind,
                        isEnabled: true
                    ))
                }
            }
        }
        .disabled(
            SourceOrganizationLevelKind.allCases
                .filter(\.isAdditionalMetadata)
                .allSatisfy { configuration.levels.map(\.kind).contains($0) }
        )
    }

    @ViewBuilder
    private var previewSection: some View {
        section("Preview") {
            if let planningError {
                Label(planningError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if let plan {
                if let example = plan.previewGroups.first {
                    Text(example.path)
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(example.path)
                }
                HStack(spacing: 10) {
                    summaryValue("\(plan.previewGroups.count) folders")
                    summaryValue("\(plan.itemCount) items")
                    summaryValue("\(plan.mediaFileCount) media files")
                    if plan.sidecarFileCount > 0 {
                        summaryValue("\(plan.sidecarFileCount) XMP")
                    }
                }

                if plan.previewGroups.count > 1 {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(plan.previewGroups.prefix(6)) { group in
                            HStack {
                                Text(group.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(group.itemCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        if plan.previewGroups.count > 6 {
                            Text("…and \(plan.previewGroups.count - 6) more")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !plan.collisions.isEmpty {
                    Label(
                        "\(plan.collisions.count) filename or sidecar conflict\(plan.collisions.count == 1 ? "" : "s") must be resolved before moving.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    ForEach(plan.collisions.prefix(2)) { conflict in
                        Text(conflict.destination.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .help(conflict.message)
                    }
                    Text("Keep Existing folder, add another level, narrow the scope, or rename the conflicting source file outside Louppe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if plan.itemCount == 0 {
                    Label("No items are included in this scope.", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                } else if plan.alreadyOrganizedItemCount == plan.itemCount {
                    Label("Everything in this scope is already organized.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    let oldFolderCount = Set(
                        plan.sourceItems.compactMap(\.subfolder)
                    ).count
                    Text("\(plan.movingItemCount) items will move out of \(oldFolderCount) existing folder\(oldFolderCount == 1 ? "" : "s"). Recognized XMP sidecars and grouped RAW+JPEG files follow their media. Nothing is overwritten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if plan.excludedACRCompanionCount > 0 {
                    Text("\(plan.excludedACRCompanionCount) Lightroom .acr companion\(plan.excludedACRCompanionCount == 1 ? "" : "s") will remain in place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Choose at least one folder level.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confirmationView(
        _ plan: SourceOrganizationPlan
    ) -> some View {
        VStack(spacing: 0) {
            sheetHeader(
                title: "Move \(plan.movingFileCount) files?",
                subtitle: "Review the exact source-folder change before Louppe moves anything."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        confirmationRow("Items", "\(plan.movingItemCount)")
                        confirmationRow("Media files", "\(plan.movingFileCount - plan.sidecarFileCount)")
                        confirmationRow("XMP sidecars", "\(plan.sidecarFileCount)")
                        confirmationRow("Destination folders", "\(plan.previewGroups.count)")
                        confirmationRow("Already organized", "\(plan.alreadyOrganizedItemCount)")
                    }

                    Divider()

                    Text("Louppe will move these files inside “\(plan.configuration.containerName)” without changing their contents or filenames. Existing files are never overwritten. Previous folders and unrelated files remain. You can undo this organization with ⌘Z during this open session.")
                        .fixedSize(horizontal: false, vertical: true)

                    if plan.storageSafety.usesReducedDirectoryDurability {
                        Divider()
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ExFAT card — reduced crash protection")
                                    .font(.headline)
                                Text("macOS cannot make folder changes on ExFAT as crash-resistant as on APFS. Louppe will first test that collision-safe moves work, will never overwrite an existing file, and will keep its recovery record. Do not eject the card, close the Mac, or remove power until the move finishes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Back") { isReviewingMove = false }
                Spacer()
                Button("Cancel", role: .cancel) {
                    store.isOrganizePresented = false
                }
                Button(plan.storageSafety.usesReducedDirectoryDurability
                    ? "Move Files Anyway"
                    : "Move Files") {
                    store.startSourceOrganization(plan)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.louppeAccent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private func progressView(
        _ progress: SourceOrganizationProgress
    ) -> some View {
        VStack(spacing: 16) {
            ProgressView(
                value: Double(progress.done),
                total: Double(max(progress.total, 1))
            )
            .frame(width: 360)
            Text(progress.title)
                .font(.headline)
            Text("\(progress.done) of \(progress.total) files")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("Keep Louppe open until the current file operation finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }

    private func outcomeView(
        _ outcome: SourceOrganizationOutcome
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: outcome.succeeded
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(outcome.succeeded
                    ? Color.louppeAccent
                    : Color.secondary)
            Text(outcome.wasUndo
                ? "Previous folders restored"
                : (outcome.succeeded
                    ? "Source folder organized"
                    : "Organization finished with problems"))
                .font(.title2.weight(.semibold))
            Text("\(outcome.movedFiles) files moved")
                .foregroundStyle(.secondary)
            if let message = store.organizationError ?? outcome.message {
                Text(message)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            } else if !outcome.wasUndo {
                Text("Use ⌘Z during this open session to restore the previous folder layout.")
                    .foregroundStyle(.secondary)
            }
            if case .scanning = store.phase {
                ProgressView("Refreshing the session…")
                    .padding(.top, 8)
            }
            Button("Done") {
                store.isOrganizePresented = false
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(store.isFileOperationRunning)
        }
        .padding(30)
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func summaryValue(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func confirmationRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func levelBinding(
        _ kind: SourceOrganizationLevelKind
    ) -> Binding<Bool> {
        Binding(
            get: {
                configuration.levels.first(where: { $0.kind == kind })?
                    .isEnabled ?? false
            },
            set: { value in
                guard let index = configuration.levels.firstIndex(where: {
                    $0.kind == kind
                }) else { return }
                configuration.levels[index].isEnabled = value
            }
        )
    }

    private func dateGranularityLabel(
        _ value: SourceOrganizationDateGranularity
    ) -> String {
        let date = plan?.sourceItems.compactMap(\.captureDate).first ?? Date()
        let example = SourceOrganizationPlanner.dateFolderLabel(
            date,
            granularity: value
        )
        return "\(value.label) — \(example)"
    }

    private var canReviewMove: Bool {
        !isPlanning && plan?.canExecute == true
    }

    private var reviewButtonTitle: String {
        if let plan, plan.alreadyOrganizedItemCount == plan.itemCount {
            return "Already Organized"
        }
        return "Review Move…"
    }

    private func refreshPlan() {
        planningCancelFlag?.cancel()
        planningCancelFlag = nil
        planningTask?.cancel()
        isReviewingMove = false
        planningError = nil
        guard !configuration.enabledLevels.isEmpty else {
            plan = nil
            isPlanning = false
            return
        }
        guard let snapshot = store.sourceOrganizationPlanningSnapshot(
            scope: scope
        ) else {
            plan = nil
            isPlanning = false
            return
        }
        let requestedConfiguration = configuration
        let cancelFlag = SourceOrganizationPlanningCancelFlag()
        planningCancelFlag = cancelFlag
        isPlanning = true
        planningTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try SourceOrganizationPlanner.makePlan(
                        sourceFolder: snapshot.sourceFolder,
                        selectedItems: snapshot.selectedItems,
                        familyContextItems: snapshot.familyContextItems,
                        configuration: requestedConfiguration,
                        knownOriginFolderPathBytesByFileID:
                            snapshot.knownOriginFolderPathBytesByFileID,
                        isCancelled: { cancelFlag.isCancelled }
                    )
                }
            }.value
            guard !Task.isCancelled,
                  !cancelFlag.isCancelled,
                  configuration == requestedConfiguration else { return }
            planningCancelFlag = nil
            isPlanning = false
            switch result {
            case .success(let prepared):
                plan = prepared
                planningError = nil
            case .failure(let error):
                plan = nil
                planningError = error.localizedDescription
            }
        }
    }
}

private struct OrganizationLevelDropDelegate: DropDelegate {
    let destination: SourceOrganizationLevelKind
    @Binding var dragged: SourceOrganizationLevelKind?
    @Binding var levels: [SourceOrganizationLevel]

    func dropEntered(info: DropInfo) {
        guard let dragged,
              dragged != destination,
              let from = levels.firstIndex(where: { $0.kind == dragged }),
              let to = levels.firstIndex(where: { $0.kind == destination }),
              levels[from].isEnabled,
              levels[to].isEnabled else { return }
        withAnimation {
            levels.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
