import Foundation
import AppKit
import OSLog

/// Runs the Export dialog's file operation: prompts for a destination,
/// receives one prepared metadata-selection snapshot and hands the file loop
/// to ExportWorker off the main actor. Copy never touches originals; Move
/// (owner-sanctioned 2026-07-21) transfers files and reports which photos
/// fully left so SessionStore can drop them from the session.
@MainActor
final class ExportManager: ObservableObject {
    struct Outcome: Equatable {
        let mode: ExportMode
        /// Files that reached the destination.
        let files: Int
        /// Photos whose pair-level copy or move was rolled back.
        let failedPhotos: Int
        /// Photos whose rollback also failed (destination may retain a
        /// partial copy, or a moved pair may be split).
        let inconsistentPhotos: Int
        /// Copy only: the photographer stopped the operation. Completed photos
        /// remain copied; the in-progress photo was rolled back.
        let cancelled: Bool
        /// Copy only: the recorded origin of a stopped copy. This stays nil
        /// for successful copies, file failures, and every Move operation.
        let cancellationReason: ExportWorker.CopyCancellationReason?
        /// The operation could not establish or advance its durable
        /// file-safety boundary.
        let journalFailure: Bool
        /// Louppe has started reconciling an interrupted operation. Copy keeps
        /// verified completed files; Move preserves completed groups and
        /// restores incomplete ones to their conservative source state.
        let recoveryRequired: Bool
        /// Concrete worker failure retained for the export result and the
        /// recovery alert. Nil only when no useful cause was available.
        let failureMessage: String?
        let destination: URL
        /// A normal Export contains one destination. A routing Copy preserves
        /// the separately confirmed folders here for its result screen.
        let destinations: [URL]
        let xmpSummary: ExportWorker.XMPResultSummary?

        var isClean: Bool {
            !cancelled && failedPhotos == 0 && inconsistentPhotos == 0
                && !journalFailure && !recoveryRequired
                && xmpSummary?.hasProblems != true
        }
    }

    struct XMPConfirmation: Equatable {
        let mode: ExportMode
        let destination: URL
        let plan: XMPExportPreparedPlan
    }

    enum State: Equatable {
        case summary
        case preparingXMP(ExportMode)
        case awaitingXMPConfirmation(XMPConfirmation)
        case preparingMultiDestination
        case awaitingMultiDestinationConfirmation(MultiDestinationExportPlan)
        case working(
            mode: ExportMode,
            completedBytes: Int64,
            totalBytes: Int64
        )
        case finished(Outcome)
        case failed(String)
    }

    @Published var state: State = .summary
    @Published private(set) var isCancellingCopy = false
    @Published private(set) var isCopyStopConfirmationPresented = false
    private var copyCancelFlag: ExportWorker.CancelFlag?
    private var copyOperationID: UUID?
    private var xmpPreparationTask: Task<XMPPreparationResult, Never>?
    private var xmpPreparationID = UUID()
    private var pendingExport: PendingExport?
    private var multiDestinationPreparationTask:
        Task<MultiDestinationPreparationResult, Never>?
    private var multiDestinationPreparationID = UUID()
    private var pendingMultiDestinationExport: PendingMultiDestinationExport?
    /// An Open panel's sandbox extension must outlive detached preflight and
    /// copy work. Each token is released on every completion and cancellation
    /// path so a long editing session cannot exhaust the process limit.
    private var destinationFolderAccesses: [SecurityScopedFolderAccess] = []
    private var routingDestinationAccesses: [UUID: SecurityScopedFolderAccess] = [:]

    private static let copyLogger = Logger(
        subsystem: "com.alexandermarkin.louppe",
        category: "export.copy"
    )

    func reset() {
        xmpPreparationTask?.cancel()
        xmpPreparationTask = nil
        xmpPreparationID = UUID()
        pendingExport = nil
        multiDestinationPreparationTask?.cancel()
        multiDestinationPreparationTask = nil
        multiDestinationPreparationID = UUID()
        pendingMultiDestinationExport = nil
        state = .summary
        isCancellingCopy = false
        isCopyStopConfirmationPresented = false
        copyCancelFlag = nil
        copyOperationID = nil
        releaseDestinationFolderAccesses()
        releaseRoutingDestinationAccesses()
    }

    func retainRoutingDestinationAccess(_ url: URL, for routeID: UUID) {
        routingDestinationAccesses[routeID]?.stop()
        routingDestinationAccesses[routeID] = SecurityScopedFolderAccess(url: url)
    }

    private func retainDestinationAccess(_ url: URL) {
        releaseDestinationFolderAccesses()
        destinationFolderAccesses = [SecurityScopedFolderAccess(url: url)]
    }

    private func releaseDestinationFolderAccesses() {
        destinationFolderAccesses.forEach { $0.stop() }
        destinationFolderAccesses = []
    }

    private func releaseRoutingDestinationAccesses() {
        routingDestinationAccesses.values.forEach { $0.stop() }
        routingDestinationAccesses = [:]
    }

    /// Builds every route's immutable, alias-resolved Copy plan off the main
    /// actor. The confirmation screen is the only path that can start the
    /// shared Copy worker, so unmatched media can never leak into a default
    /// destination.
    func prepareMultiDestinationExport(
        routes: [MultiDestinationExportRoute],
        items: [PhotoItem],
        sourceFolder: URL?,
        includeXMP: Bool,
        familyContextItems: [PhotoItem],
        sessionGeneration: UInt64,
        xmpProfile: XMPApplicationProfile,
        visibleDecisionKeywords: Bool,
        allowExternalLabelReplacement: Bool,
        onOperationWillStart: @escaping @MainActor (ExportMode) -> Bool,
        onOperationDidFinish: @escaping @MainActor (
            _ mode: ExportMode,
            _ movedIDs: [String],
            _ requiresRecovery: Bool,
            _ interruptionMessage: String?
        ) -> Void
    ) {
        let preparationID = UUID()
        multiDestinationPreparationID = preparationID
        pendingMultiDestinationExport = nil
        state = .preparingMultiDestination
        let input = MultiDestinationExportPlanner.PreparationInput(
            routes: routes,
            items: items,
            sourceFolder: sourceFolder,
            includeXMP: includeXMP,
            familyContextItems: familyContextItems,
            sessionGeneration: sessionGeneration,
            xmpProfile: xmpProfile,
            visibleDecisionKeywords: visibleDecisionKeywords,
            allowExternalLabelReplacement: allowExternalLabelReplacement
        )
        let task = Task.detached(priority: .userInitiated) {
            () -> MultiDestinationPreparationResult in
            do {
                return .prepared(try await MultiDestinationExportPlanner.prepare(input))
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        multiDestinationPreparationTask = task
        Task { @MainActor [weak self] in
            let result = await task.value
            guard let self,
                  self.multiDestinationPreparationID == preparationID else {
                return
            }
            self.multiDestinationPreparationTask = nil
            switch result {
            case .prepared(let work):
                self.pendingMultiDestinationExport = PendingMultiDestinationExport(
                    work: work,
                    onOperationWillStart: onOperationWillStart,
                    onOperationDidFinish: onOperationDidFinish
                )
                self.state = .awaitingMultiDestinationConfirmation(work.plan)
            case .cancelled:
                self.releaseRoutingDestinationAccesses()
                self.state = .summary
            case .failed(let message):
                self.releaseRoutingDestinationAccesses()
                self.state = .failed("The routing copy could not be prepared safely. \(message)")
            }
        }
    }

    func cancelMultiDestinationPreparation() {
        guard case .preparingMultiDestination = state else { return }
        multiDestinationPreparationTask?.cancel()
        multiDestinationPreparationTask = nil
        multiDestinationPreparationID = UUID()
        pendingMultiDestinationExport = nil
        releaseRoutingDestinationAccesses()
        state = .summary
    }

    func backFromMultiDestinationConfirmation() {
        guard case .awaitingMultiDestinationConfirmation = state else { return }
        pendingMultiDestinationExport = nil
        releaseRoutingDestinationAccesses()
        state = .summary
    }

    func confirmMultiDestinationExport() {
        guard let pending = pendingMultiDestinationExport,
              case .awaitingMultiDestinationConfirmation = state else { return }
        pendingMultiDestinationExport = nil
        let plan = pending.work.plan
        guard let firstDestination = plan.destinations.first else {
            releaseRoutingDestinationAccesses()
            state = .failed("The routing copy no longer has a destination. Review the routes again.")
            return
        }
        guard plan.totalFiles > 0, pending.onOperationWillStart(.copy) else {
            releaseRoutingDestinationAccesses()
            state = .failed("Another file operation is already running. Wait for it to finish, then try again.")
            return
        }
        plan.destinations.forEach {
            SecurityScopedFolderBookmarks.recordRecoveryDestination($0)
        }

        isCancellingCopy = false
        isCopyStopConfirmationPresented = false
        let cancelFlag = ExportWorker.CancelFlag()
        copyCancelFlag = cancelFlag
        copyOperationID = UUID()
        state = .working(
            mode: .copy,
            completedBytes: 0,
            totalBytes: plan.workerPlan.totalTransferBytes
        )
        let byteProgress: ExportWorker.ByteProgress = { [weak self] completed, total in
            Task { @MainActor [weak self] in
                guard let self, case .working = self.state else { return }
                self.state = .working(
                    mode: .copy,
                    completedBytes: completed,
                    totalBytes: total
                )
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            ExportWorker.copy(
                pending.work.selectedItems,
                to: firstDestination,
                xmpPlan: plan.xmpPlan,
                preparedPlan: plan.workerPlan,
                isCancelled: { cancelFlag.isSet },
                cancellationReason: { cancelFlag.reason },
                progress: { _, _ in },
                byteProgress: byteProgress
            )
        }
        Task { @MainActor in
            let copy = await worker.value
            self.recordCopyResult(copy)
            self.copyCancelFlag = nil
            self.isCancellingCopy = false
            self.isCopyStopConfirmationPresented = false
            self.copyOperationID = nil
            pending.onOperationDidFinish(
                .copy,
                [],
                copy.requiresRecovery,
                copy.failureMessage
            )
            if !copy.requiresRecovery {
                SecurityScopedFolderBookmarks.clearRecoveryDestinations()
            }
            self.releaseRoutingDestinationAccesses()
            self.state = .finished(Outcome(
                mode: .copy,
                files: copy.xmpSummary?.mediaFiles ?? copy.copiedFiles,
                failedPhotos: copy.failedPhotos,
                inconsistentPhotos: copy.inconsistentPhotos,
                cancelled: copy.cancelled,
                cancellationReason: copy.cancellationReason,
                journalFailure: copy.journalFailure,
                recoveryRequired: copy.requiresRecovery,
                failureMessage: copy.failureMessage,
                destination: firstDestination,
                destinations: plan.destinations,
                xmpSummary: copy.xmpSummary
            ))
        }
    }

    func promptDestinationAndExport(
        sourceFolder: URL?,
        selected: [PhotoItem],
        familyContextItems: [PhotoItem],
        sessionGeneration: UInt64,
        mode: ExportMode,
        includeXMP: Bool,
        xmpProfile: XMPApplicationProfile,
        visibleDecisionKeywords: Bool,
        allowExternalLabelReplacement: Bool,
        onOperationWillStart: @escaping @MainActor (_ mode: ExportMode) -> Bool,
        onOperationDidFinish: @escaping @MainActor (
            _ mode: ExportMode,
            _ movedIDs: [String],
            _ requiresRecovery: Bool,
            _ interruptionMessage: String?
        ) -> Void
    ) {
        guard mode != .metadataXMP else {
            state = .failed("Metadata (XMP) writes beside the originals and does not use a destination.")
            return
        }
        guard !selected.isEmpty else {
            state = .failed("There are no items matching the selected metadata to export.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = mode == .copy
            ? "Choose where to copy the selected media."
            : "Choose where to move the selected media."
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        retainDestinationAccess(destination)

        let validatedDestination: ExportDestinationValidator.ValidatedDestination
        do {
            validatedDestination = try ExportDestinationValidator.validateBound(
                sourceFolder: sourceFolder,
                destination: destination,
                items: selected,
                mode: mode
            )
        } catch {
            releaseDestinationFolderAccesses()
            state = .failed(error.localizedDescription)
            return
        }

        if includeXMP {
            prepareXMPExport(
                selected: selected,
                familyContextItems: familyContextItems,
                sessionGeneration: sessionGeneration,
                mode: mode,
                xmpProfile: xmpProfile,
                visibleDecisionKeywords: visibleDecisionKeywords,
                allowExternalLabelReplacement:
                    allowExternalLabelReplacement,
                sourceFolder: sourceFolder,
                to: validatedDestination,
                onOperationWillStart: onOperationWillStart,
                onOperationDidFinish: onOperationDidFinish
            )
        } else {
            export(
                selected: selected,
                mode: mode,
                xmpPlan: nil,
                to: validatedDestination.url,
                destinationBinding: validatedDestination.binding,
                onOperationWillStart: onOperationWillStart,
                onOperationDidFinish: onOperationDidFinish
            )
        }
    }

    private func prepareXMPExport(
        selected: [PhotoItem],
        familyContextItems: [PhotoItem],
        sessionGeneration: UInt64,
        mode: ExportMode,
        xmpProfile: XMPApplicationProfile,
        visibleDecisionKeywords: Bool,
        allowExternalLabelReplacement: Bool,
        sourceFolder: URL?,
        to destination: ExportDestinationValidator.ValidatedDestination,
        onOperationWillStart: @escaping @MainActor (ExportMode) -> Bool,
        onOperationDidFinish: @escaping @MainActor (
            ExportMode,
            [String],
            Bool,
            String?
        ) -> Void
    ) {
        let input: XMPExportPreparationInput
        do {
            input = try XMPExportPreparationInput(
                selected: selected,
                familyContextItems: familyContextItems,
                sessionGeneration: sessionGeneration,
                profile: xmpProfile,
                visibleDecisionKeywords: visibleDecisionKeywords,
                allowExternalLabelReplacement:
                    allowExternalLabelReplacement
            )
        } catch {
            releaseDestinationFolderAccesses()
            state = .failed(
                "The export could not be prepared safely. \(error.localizedDescription)"
            )
            return
        }
        let preparationID = UUID()
        xmpPreparationID = preparationID
        state = .preparingXMP(mode)
        let worker = Task.detached(priority: .userInitiated) {
            () -> XMPPreparationResult in
            do {
                let xmpPlan = try await XMPExportPlanner.prepare(input)
                return .prepared(
                    xmpPlan,
                    try ExportWorker.makePlan(
                        for: selected,
                        in: destination.url,
                        xmpPlan: xmpPlan,
                        mode: mode,
                        destinationBinding: destination.binding
                    )
                )
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        xmpPreparationTask = worker
        Task { @MainActor [weak self] in
            let result = await worker.value
            guard let self, self.xmpPreparationID == preparationID else {
                return
            }
            self.xmpPreparationTask = nil
            switch result {
            case .prepared(let plan, let operationPlan):
                self.pendingExport = PendingExport(
                    selected: selected,
                    sourceFolder: sourceFolder,
                    mode: mode,
                    destination: destination.url,
                    plan: plan,
                    operationPlan: operationPlan,
                    xmpProfile: xmpProfile,
                    visibleDecisionKeywords: visibleDecisionKeywords,
                    allowExternalLabelReplacement:
                        allowExternalLabelReplacement,
                    onOperationWillStart: onOperationWillStart,
                    onOperationDidFinish: onOperationDidFinish
                )
                self.state = .awaitingXMPConfirmation(XMPConfirmation(
                    mode: mode,
                    destination: destination.url,
                    plan: plan
                ))
            case .cancelled:
                self.pendingExport = nil
                self.releaseDestinationFolderAccesses()
                self.state = .summary
            case .failed(let message):
                self.pendingExport = nil
                self.releaseDestinationFolderAccesses()
                self.state = .failed(
                    "The export could not be prepared safely. \(message)"
                )
            }
        }
    }

    func confirmXMPExport() {
        guard let pendingExport,
              case .awaitingXMPConfirmation = state else { return }
        self.pendingExport = nil
        export(
            selected: pendingExport.selected,
            mode: pendingExport.mode,
            xmpPlan: pendingExport.plan,
            preparedPlan: pendingExport.operationPlan,
            to: pendingExport.destination,
            onOperationWillStart: pendingExport.onOperationWillStart,
            onOperationDidFinish: pendingExport.onOperationDidFinish
        )
    }

    /// Discards the old immutable XMP/media selection after a conflict
    /// resolution, revalidates the retained destination, and performs the
    /// complete planner pass again before confirmation can be offered.
    func reprepareXMPExportAfterResolution(
        selected: [PhotoItem],
        familyContextItems: [PhotoItem],
        sessionGeneration: UInt64
    ) {
        guard let pendingExport,
              case .awaitingXMPConfirmation = state else { return }
        guard !selected.isEmpty else {
            self.pendingExport = nil
            releaseDestinationFolderAccesses()
            state = .failed(
                "After resolving the RAW + JPEG metadata, no items match the selected Export filters."
            )
            return
        }
        let destination: ExportDestinationValidator.ValidatedDestination
        do {
            destination = try ExportDestinationValidator.validateBound(
                sourceFolder: pendingExport.sourceFolder,
                destination: pendingExport.destination,
                items: selected,
                mode: pendingExport.mode
            )
        } catch {
            self.pendingExport = nil
            releaseDestinationFolderAccesses()
            state = .failed(error.localizedDescription)
            return
        }
        self.pendingExport = nil
        prepareXMPExport(
            selected: selected,
            familyContextItems: familyContextItems,
            sessionGeneration: sessionGeneration,
            mode: pendingExport.mode,
            xmpProfile: pendingExport.xmpProfile,
            visibleDecisionKeywords: pendingExport.visibleDecisionKeywords,
            allowExternalLabelReplacement:
                pendingExport.allowExternalLabelReplacement,
            sourceFolder: pendingExport.sourceFolder,
            to: destination,
            onOperationWillStart: pendingExport.onOperationWillStart,
            onOperationDidFinish: pendingExport.onOperationDidFinish
        )
    }

    func cancelXMPPreparation() {
        guard case .preparingXMP = state else { return }
        xmpPreparationTask?.cancel()
        xmpPreparationTask = nil
        xmpPreparationID = UUID()
        pendingExport = nil
        releaseDestinationFolderAccesses()
        state = .summary
    }

    func backFromXMPConfirmation() {
        guard case .awaitingXMPConfirmation = state else { return }
        pendingExport = nil
        releaseDestinationFolderAccesses()
        state = .summary
    }

    private func export(
        selected: [PhotoItem],
        mode: ExportMode,
        xmpPlan: XMPExportPreparedPlan?,
        preparedPlan: ExportWorker.Plan? = nil,
        to destination: URL,
        destinationBinding: DurableFileIO.DirectoryBinding? = nil,
        onOperationWillStart: @MainActor (_ mode: ExportMode) -> Bool,
        onOperationDidFinish: @escaping @MainActor (
            _ mode: ExportMode,
            _ movedIDs: [String],
            _ requiresRecovery: Bool,
            _ interruptionMessage: String?
        ) -> Void
    ) {
        let totalFiles = preparedPlan?.totalFiles
            ?? selected.reduce(0) { $0 + $1.allURLs.count }
        guard totalFiles > 0, onOperationWillStart(mode) else {
            releaseDestinationFolderAccesses()
            state = .failed("Another file operation is already running. Wait for it to finish, then try again.")
            return
        }
        SecurityScopedFolderBookmarks.recordRecoveryDestination(destination)

        isCancellingCopy = false
        isCopyStopConfirmationPresented = false
        let cancelFlag = mode == .copy ? ExportWorker.CancelFlag() : nil
        copyCancelFlag = cancelFlag
        copyOperationID = mode == .copy ? UUID() : nil
        let totalTransferBytes = preparedPlan?.totalTransferBytes
            ?? totalBytes(for: selected)
        state = .working(
            mode: mode,
            completedBytes: 0,
            totalBytes: totalTransferBytes
        )

        let byteProgress: ExportWorker.ByteProgress = { [weak self] completed, total in
            Task { @MainActor [weak self] in
                // A late throttled tick must never overwrite .finished.
                guard let self, case .working = self.state else { return }
                self.state = .working(
                    mode: mode,
                    completedBytes: completed,
                    totalBytes: total
                )
            }
        }

        let worker = Task.detached(priority: .userInitiated) {
            () -> WorkerResult in
            if mode == .copy {
                return .copy(ExportWorker.copy(
                    selected,
                    to: destination,
                    xmpPlan: xmpPlan,
                    preparedPlan: preparedPlan,
                    destinationBinding: destinationBinding,
                    isCancelled: { cancelFlag?.isSet ?? false },
                    cancellationReason: { cancelFlag?.reason },
                    progress: { _, _ in },
                    byteProgress: byteProgress
                ))
            }
            return .move(ExportWorker.move(
                selected,
                to: destination,
                xmpPlan: xmpPlan,
                preparedPlan: preparedPlan,
                destinationBinding: destinationBinding,
                progress: { _, _ in },
                byteProgress: byteProgress
            ))
        }

        Task { @MainActor in
            let result = await worker.value
            defer {
                self.isCopyStopConfirmationPresented = false
                self.copyOperationID = nil
            }
            copyCancelFlag = nil
            isCancellingCopy = false
            switch result {
            case .copy(let copy):
                self.recordCopyResult(copy)
                onOperationDidFinish(
                    .copy,
                    [],
                    copy.requiresRecovery,
                    copy.failureMessage
                )
                state = .finished(Outcome(
                    mode: .copy,
                    files: copy.xmpSummary?.mediaFiles
                        ?? copy.copiedFiles,
                    failedPhotos: copy.failedPhotos,
                    inconsistentPhotos: copy.inconsistentPhotos,
                    cancelled: copy.cancelled,
                    cancellationReason: copy.cancellationReason,
                    journalFailure: copy.journalFailure,
                    recoveryRequired: copy.requiresRecovery,
                    failureMessage: copy.failureMessage,
                    destination: destination,
                    destinations: [destination],
                    xmpSummary: copy.xmpSummary
                ))
                if !copy.requiresRecovery {
                    SecurityScopedFolderBookmarks.clearRecoveryDestinations()
                }
            case .move(let move):
                // Always deliver, even an empty list — the store clears its
                // in-flight state here.
                onOperationDidFinish(
                    .move,
                    move.movedItemIDs,
                    move.requiresRecovery,
                    move.failureMessage
                )
                state = .finished(Outcome(
                    mode: .move,
                    files: move.xmpSummary?.mediaFiles
                        ?? move.movedFiles,
                    failedPhotos: move.failedPhotos,
                    inconsistentPhotos: move.inconsistentPhotos,
                    cancelled: false,
                    cancellationReason: nil,
                    journalFailure: move.journalFailure,
                    recoveryRequired: move.requiresRecovery,
                    failureMessage: move.failureMessage,
                    destination: destination,
                    destinations: [destination],
                    xmpSummary: move.xmpSummary
                ))
                if !move.requiresRecovery {
                    SecurityScopedFolderBookmarks.clearRecoveryDestinations()
                }
            }
            self.releaseDestinationFolderAccesses()
        }
    }

    /// First step of the explicit, two-step Copy stop flow. A normal click,
    /// Return, Escape, or sheet event can never set the worker cancellation
    /// flag directly.
    func requestCopyStopConfirmation() {
        guard case .working(
            mode: .copy,
            completedBytes: _,
            totalBytes: _
        ) = state else { return }
        guard !isCancellingCopy, !isCopyStopConfirmationPresented else { return }
        isCopyStopConfirmationPresented = true
        let operation = copyOperationID?.uuidString ?? "unknown"
        Self.copyLogger.log(
            "Copy stop confirmation shown operation=\(operation, privacy: .public)"
        )
    }

    /// The only production path that can request cancellation of an active
    /// Copy. Its immutable reason travels with the worker result.
    func confirmCopyStop() {
        guard case .working(
            mode: .copy,
            completedBytes: _,
            totalBytes: _
        ) = state,
        let copyCancelFlag else {
            isCopyStopConfirmationPresented = false
            return
        }
        guard copyCancelFlag.request(.userConfirmed) else { return }
        isCancellingCopy = true
        isCopyStopConfirmationPresented = false
        let operation = copyOperationID?.uuidString ?? "unknown"
        Self.copyLogger.log(
            "Copy cancellation confirmed operation=\(operation, privacy: .public)"
        )
    }

    func dismissCopyStopConfirmation() {
        guard isCopyStopConfirmationPresented else { return }
        isCopyStopConfirmationPresented = false
        let operation = copyOperationID?.uuidString ?? "unknown"
        Self.copyLogger.log(
            "Copy stop confirmation dismissed operation=\(operation, privacy: .public)"
        )
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private enum WorkerResult: Sendable {
        case copy(ExportWorker.CopyResult)
        case move(ExportWorker.MoveResult)
    }

    private func totalBytes(for items: [PhotoItem]) -> Int64 {
        items.reduce(into: Int64(0)) { total, item in
            let (sum, overflowed) = total.addingReportingOverflow(
                item.totalFileSize
            )
            total = overflowed ? Int64.max : sum
        }
    }

    private func recordCopyResult(_ copy: ExportWorker.CopyResult) {
        guard copy.cancelled else { return }
        let operation = copyOperationID?.uuidString ?? "unknown"
        switch copy.cancellationReason {
        case .userConfirmed:
            Self.copyLogger.log(
                "Copy stopped by confirmed user request operation=\(operation, privacy: .public)"
            )
        case .unrecorded:
            Self.copyLogger.error(
                "Copy stopped without a recorded reason operation=\(operation, privacy: .public)"
            )
        case nil:
            Self.copyLogger.error(
                "Copy reported cancellation without a reason operation=\(operation, privacy: .public)"
            )
        }
    }

    private enum XMPPreparationResult: Sendable {
        case prepared(XMPExportPreparedPlan, ExportWorker.Plan)
        case cancelled
        case failed(String)
    }

    private enum MultiDestinationPreparationResult: Sendable {
        case prepared(MultiDestinationExportPlanner.PreparedWork)
        case cancelled
        case failed(String)
    }

    private struct PendingExport {
        let selected: [PhotoItem]
        let sourceFolder: URL?
        let mode: ExportMode
        let destination: URL
        let plan: XMPExportPreparedPlan
        let operationPlan: ExportWorker.Plan
        let xmpProfile: XMPApplicationProfile
        let visibleDecisionKeywords: Bool
        let allowExternalLabelReplacement: Bool
        let onOperationWillStart: @MainActor (ExportMode) -> Bool
        let onOperationDidFinish: @MainActor (
            ExportMode,
            [String],
            Bool,
            String?
        ) -> Void
    }

    private struct PendingMultiDestinationExport {
        let work: MultiDestinationExportPlanner.PreparedWork
        let onOperationWillStart: @MainActor (ExportMode) -> Bool
        let onOperationDidFinish: @MainActor (
            ExportMode,
            [String],
            Bool,
            String?
        ) -> Void
    }
}

private extension ExportWorker.XMPResultSummary {
    var hasProblems: Bool {
        unsupported > 0 || skipped > 0 || conflicts > 0 || failed > 0
    }
}
