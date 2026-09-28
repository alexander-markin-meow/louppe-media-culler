import SwiftUI
import AppKit

extension Color {
    /// The single background gray used everywhere in the app (Browser, photo
    /// pane, info panel, Grid view) so there's one consistent shade.
    static let appBackground = Color(nsColor: .windowBackgroundColor)

    /// Louppe's brand purple (#9853A6). The one accent color for everything
    /// that isn't a yes/no rating (those stay green/red): selection borders,
    /// the export button, links, toggles, and the app-icon glyph.
    static let louppeAccent = Color(red: 0x98 / 255, green: 0x53 / 255, blue: 0xA6 / 255)
}

/// Top-level switch between the three app phases:
/// welcome screen → scanning progress → the culling session.
struct RootView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        Group {
            switch store.phase {
            case .welcome:
                WelcomeView(store: store)
            case .scanning(let found):
                ScanningView(store: store, found: found)
            case .ready:
                SessionView(store: store)
            }
        }
        .accessibilityHidden(store.isRecoveringInterruptedOperations)
        // Tint every standard control (buttons, links, pickers, toggles,
        // progress bars — including sheets and popovers) with the brand purple.
        .tint(Color.louppeAccent)
        .frame(
            minWidth: windowLayout.minimumContentSize.width,
            minHeight: windowLayout.minimumContentSize.height
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if store.recoveryNeedsAttention {
                    RecoveryWarningBanner(
                        message: store.recoveryAttentionMessage
                            ?? "Some interrupted files are still untouched.",
                        canRetry: store.canRetryInterruptedOperationRecovery,
                        retry: store.retryInterruptedOperationRecovery,
                        keepFilesAsTheyAre: store.keepInterruptedFilesAsTheyAre
                    )
                }
                if let warning = store.persistenceWarning {
                    PersistenceWarningBanner(
                        message: warning,
                        showsRetry: store.canRetryPersistence,
                        retry: store.retryPersistence
                    )
                }
            }
            .accessibilityHidden(store.isRecoveringInterruptedOperations)
        }
        .overlay {
            if store.isRecoveringInterruptedOperations {
                InterruptedOperationRecoveryOverlay()
            }
        }
        .alert(
            "Interrupted operation recovered",
            isPresented: operationRecoveryReportIsPresented
        ) {
            Button("OK") {
                store.dismissOperationRecoveryReport()
            }
        } message: {
            Text(recoveryMessage)
        }
        // The same NSWindow survives all three phases. Welcome/Scanning use a
        // compact full-size-content layout; the active session expands and
        // opts out so photos cannot scroll behind the glass toolbar.
        .background(WindowContentLayout(layout: windowLayout))
    }

    private var windowLayout: MainWindowLayout {
        switch store.phase {
        case .welcome, .scanning:
            return .launch
        case .ready:
            return .session
        }
    }

    private var operationRecoveryReportIsPresented: Binding<Bool> {
        Binding(
            get: {
                store.operationRecoveryReportRequiresAcknowledgement
            },
            set: {
                if !$0 { store.dismissOperationRecoveryReport() }
            }
        )
    }

    private var recoveryMessage: String {
        guard let report = store.operationRecoveryReport else { return "" }
        let interruptionPrefix = store.operationRecoveryCause.map {
            $0.hasSuffix(".") ? "\($0) " : "\($0). "
        } ?? ""
        var actions: [String] = []
        if report.preservedCopies > 0 {
            actions.append(
                "kept \(report.preservedCopies) completed cop"
                    + (report.preservedCopies == 1 ? "y" : "ies")
                    + " at the destination"
            )
        }
        if report.preservedMoves > 0 {
            actions.append(
                "kept \(report.preservedMoves) completed Move file"
                    + (report.preservedMoves == 1 ? "" : "s")
                    + " at the destination"
            )
        }
        if report.restoredFiles > 0 {
            actions.append(
                "restored \(report.restoredFiles) original file"
                    + (report.restoredFiles == 1 ? "" : "s")
            )
        }
        if report.removedPartialCopies > 0 {
            actions.append(
                "removed \(report.removedPartialCopies) incomplete cop"
                    + (report.removedPartialCopies == 1 ? "y" : "ies")
            )
        }
        return interruptionPrefix
            + "Louppe \(actions.joined(separator: " and ")). No existing file was overwritten."
    }
}

private struct InterruptedOperationRecoveryOverlay: View {
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Recovering interrupted files")
            Text("Making interrupted file operations safe…")
                .font(.headline)
            Text("Checking files before opening the folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
        .accessibilityElement(children: .combine)
        .accessibilityFocused($isAccessibilityFocused)
        .onAppear { isAccessibilityFocused = true }
    }
}

private struct RecoveryWarningBanner: View {
    let message: String
    let canRetry: Bool
    let retry: () -> Void
    let keepFilesAsTheyAre: () -> Void
    @AccessibilityFocusState private var isWarningFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Interrupted operation warning. \(message)")
                .accessibilityFocused($isWarningFocused)
                .onAppear { isWarningFocused = true }
            Spacer(minLength: 12)
            Button("Keep Files As They Are", action: keepFilesAsTheyAre)
                .disabled(!canRetry)
            Button("Retry Recovery", action: retry)
                .disabled(!canRetry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Visible but non-modal: review can continue while a read-only folder uses
/// the backup, and an unsafe save can be retried without dismissing an alert.
private struct PersistenceWarningBanner: View {
    let message: String
    let showsRetry: Bool
    let retry: () -> Void
    @AccessibilityFocusState private var isWarningFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Session save warning. \(message)")
                .accessibilityFocused($isWarningFocused)
                .onAppear { isWarningFocused = true }
            Spacer(minLength: 12)
            if showsRetry {
                Button("Retry Saving", action: retry)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private enum MainWindowLayout: Equatable {
    case launch
    case session

    var usesFullSizeContent: Bool {
        self == .launch
    }

    var minimumContentSize: CGSize {
        switch self {
        case .launch:
            return CGSize(width: 520, height: 520)
        case .session:
            return CGSize(width: 900, height: 600)
        }
    }

    var preferredContentSize: CGSize {
        switch self {
        case .launch:
            return CGSize(width: 560, height: 560)
        case .session:
            return CGSize(width: 1100, height: 700)
        }
    }
}

/// Keeps the persistent app window's size and content layout in sync with the
/// current SwiftUI phase. Window corner geometry remains entirely system-owned.
private struct WindowContentLayout: NSViewRepresentable {
    let layout: MainWindowLayout

    func makeNSView(context: Context) -> NSView {
        let view = Configurator()
        view.layout = layout
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? Configurator else { return }
        view.layout = layout
        view.apply()
    }

    private final class Configurator: NSView {
        var layout = MainWindowLayout.launch
        private var appliedLayout: MainWindowLayout?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.styleMask.contains(.fullSizeContentView) != layout.usesFullSizeContent {
                if layout.usesFullSizeContent {
                    window.styleMask.insert(.fullSizeContentView)
                } else {
                    window.styleMask.remove(.fullSizeContentView)
                }
            }

            window.contentMinSize = layout.minimumContentSize
            guard appliedLayout != layout else { return }
            appliedLayout = layout

            switch layout {
            case .launch:
                window.setContentSize(layout.preferredContentSize)
            case .session:
                let current = window.contentLayoutRect.size
                if current.width < layout.preferredContentSize.width
                    || current.height < layout.preferredContentSize.height {
                    window.setContentSize(layout.preferredContentSize)
                }
            }
        }
    }
}
