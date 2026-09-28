import SwiftUI
import UniformTypeIdentifiers

/// The Louppe logo — the same 3×3 grid as the app icon, with the middle
/// "keeper" tile filled — drawn natively so it stays crisp at any size and
/// always matches the brand purple. Proportions were measured from the
/// 1024 px app-icon master (AppIcon/AppIcon-1024.png).
struct LouppeLogo: View {
    var size: CGFloat = 64

    var body: some View {
        let tile = size / 3.82          // 3 tiles + 2 gaps of 0.41 × tile
        let gap = tile * 0.41
        let stroke = tile * 0.135
        let radius = tile * 0.2
        VStack(spacing: gap) {
            ForEach(0..<3) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3) { column in
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(Color.louppeAccent, lineWidth: stroke)
                            .background(
                                // Only the center tile — the keeper — is filled.
                                row == 1 && column == 1
                                    ? RoundedRectangle(cornerRadius: radius).fill(Color.louppeAccent)
                                    : nil
                            )
                            .frame(width: tile, height: tile)
                    }
                }
            }
        }
    }
}

/// The start screen: pick a folder (or a recent one) to begin a session.
struct WelcomeView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow
    @State private var isFolderDropTarget = false
    @State private var folderDropError: String?
    @State private var isNewSessionConfirmationPresented = false

    var body: some View {
        VStack(spacing: 18) {
            Link(destination: URL(string: "https://louppe.eu/")!) {
                LouppeLogo(size: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Visit the Louppe website")
            .help("Open louppe.eu")
            Text("Louppe")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.louppeAccent)

            VStack(spacing: 10) {
                Button {
                    store.promptForSourceFolder()
                } label: {
                    Label("Choose Media Folder…", systemImage: "folder")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                .controlSize(.large)
                .keyboardShortcut("o")

                Label(
                    isFolderDropTarget
                        ? "Release to open this folder"
                        : "or drag a media folder here",
                    systemImage: isFolderDropTarget
                        ? "folder.badge.plus"
                        : "arrow.down.doc"
                )
                .font(.callout)
                .foregroundStyle(
                    isFolderDropTarget ? Color.louppeAccent : .secondary
                )
            }
            .frame(maxWidth: 360)
            .padding(16)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isFolderDropTarget
                            ? Color.louppeAccent
                            : Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: isFolderDropTarget ? 2 : 1, dash: [6])
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open a media folder")
            .accessibilityHint("Choose a folder or drag a folder here to start reviewing it")

            VStack(spacing: 3) {
                Text("Photos (including RAW), videos, and audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Quick Start and supported formats") {
                    openWindow(id: LouppeHelpWindow.id)
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if let folderDropError {
                Text(folderDropError)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if let error = store.scanError {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(
                            store.canOpenMismatchedSessionAnyway
                                ? Color.secondary
                                : Color.orange
                        )
                        .multilineTextAlignment(.center)

                    if store.canOpenMismatchedSessionAnyway {
                        Button("Open Anyway") {
                            store.openMismatchedSessionAnyway()
                        }
                        .accessibilityHint(
                            "Verifies saved filenames, then uses this legacy session with the current folder"
                        )
                    } else if store.canOpenIdentityConflictAsNewSession {
                        Button("Open as New Session") {
                            isNewSessionConfirmationPresented = true
                        }
                        .accessibilityHint(
                            "Forgets saved decisions for this folder and opens the current files unrated"
                        )
                    }
                }
            }

            if !store.recentFolders.isEmpty {
                VStack(spacing: 6) {
                    Text("Recent")
                        .font(.caption.smallCaps())
                        .foregroundStyle(.secondary)
                    ForEach(store.recentFolders.prefix(5), id: \.path) { url in
                        Button {
                            store.openFolder(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "clock")
                                .frame(maxWidth: 320)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(Color.louppeAccent)
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("Open \(url.path)")
                        .help(url.path)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isFolderDropTarget,
            perform: openDroppedFolder
        )
        .alert(
            "Open as a New Session?",
            isPresented: $isNewSessionConfirmationPresented
        ) {
            Button("Open as New Session", role: .destructive) {
                store.openIdentityConflictAsNewSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the saved Louppe decisions for this folder and opens the current files unrated. Your photos and videos are not changed."
            )
        }
        .toolbar { LaunchToolbarTitle() }
        .navigationTitle("")
    }

    private func openDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { item, _ in
            let url: URL?
            if let urlItem = item as? URL {
                url = urlItem
            } else if let urlItem = item as? NSURL {
                url = urlItem as URL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            Task { @MainActor in
                guard let url else {
                    folderDropError = "Louppe couldn't read the dropped folder. Please try again."
                    return
                }

                var isDirectory = ObjCBool(false)
                guard FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue else {
                    folderDropError = "Drop a folder containing photos, videos, audio, or text files, not an individual file."
                    return
                }

                folderDropError = nil
                store.openFolder(url)
            }
        }
        return true
    }
}

/// Shown while a folder scan is in progress.
struct ScanningView: View {
    @ObservedObject var store: SessionStore
    let found: Int

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Scanning media")
                .accessibilityValue(progressText)

            Text("Scanning “\(folderName)”…")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folderPath)
                .accessibilityLabel("Scanning \(folderPath)")

            Text(progressText)
                .foregroundStyle(.secondary)

        }
        .padding(.horizontal, 40)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.cancelScan()
                } label: {
                    Label("Cancel Scan", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut(.cancelAction)
                .help("Cancel scanning and return to the start screen (Esc)")
            }
            LaunchToolbarTitle()
        }
        .navigationTitle("")
        .onExitCommand {
            store.cancelScan()
        }
    }

    private var folderName: String {
        guard let folder = store.sourceFolder else { return "Folder" }
        return folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
    }

    private var folderPath: String {
        store.sourceFolder?.path ?? ""
    }

    private var progressText: String {
        guard found > 0 else { return "Looking for media…" }
        return found == 1 ? "1 item found" : "\(found.formatted()) items found"
    }
}

/// Welcome and Scanning deliberately use a real unified toolbar rather than a
/// custom rounded window. On macOS 26 this gives the launch window Apple's
/// larger native toolbar-window corners while preserving the centered title.
private struct LaunchToolbarTitle: ToolbarContent {
    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                Text("Louppe")
                    .font(.headline)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                Text("Louppe")
                    .font(.headline)
            }
        }
    }
}
