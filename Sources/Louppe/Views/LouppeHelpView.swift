import SwiftUI

enum LouppeHelpWindow {
    static let id = "help"
}

/// A small, searchable reference that can open independently of a photo session.
struct LouppeHelpView: View {
    @State private var shortcutSearch = ""
    @AppStorage("louppe.showQuickStart") private var showQuickStart = true

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys }

        func matches(_ query: String) -> Bool {
            keys.localizedStandardContains(query)
                || action.localizedStandardContains(query)
        }
    }

    private static let shortcuts: [Shortcut] = [
        .init(keys: "F / D", action: "Mark Yes / No; advance by default (Settings → Review)"),
        .init(keys: "0–5", action: "Clear or set stars, independently of Yes / No"),
        .init(keys: "← / →, J / L", action: "Previous / next item; arrows seek in Gallery video"),
        .init(keys: "↑ / ↓", action: "Previous / next item or Grid row"),
        .init(keys: "Space / K", action: "Play or pause media; Space advances on photos"),
        .init(keys: "⇧← / ⇧→", action: "Seek five seconds in Gallery video"),
        .init(keys: "S", action: "Toggle 100% photo view"),
        .init(keys: "A", action: "Toggle phone-sized photo view"),
        .init(keys: "X", action: "Toggle photo clipping overlay"),
        .init(keys: "Tab / G", action: "Switch Gallery / Grid"),
        .init(keys: "Q", action: "Show or hide Gallery thumbnail browser"),
        .init(keys: "W", action: "Show or hide Info panel"),
        .init(keys: "⌘+ / ⌘−", action: "Make Grid thumbnails larger / smaller"),
        .init(keys: "E / ⌘E", action: "Open Export"),
        .init(keys: "R", action: "Clear all Yes / No decisions"),
        .init(keys: "Z / ⌘Z", action: "Undo the latest review or file action"),
        .init(keys: "⌘O", action: "Open another folder"),
        .init(keys: "⌘R", action: "Rescan the current folder"),
        .init(keys: "⌘F", action: "Open Filter and focus Search"),
        .init(keys: "⌘K", action: "Open Command Palette"),
        .init(keys: "⌘A", action: "Select all visible items"),
        .init(keys: "⌘← / ⌘→", action: "Change playback speed; previous / next photo"),
        .init(keys: "⌘⇧← / ⌘⇧→", action: "Select to the first / last item"),
        .init(keys: "Esc", action: "Cancel a scan or clear selection"),
        .init(keys: "⌘⌫", action: "Move selected items to Trash; ⌘Z restores them"),
    ]

    private var matchingShortcuts: [Shortcut] {
        let query = shortcutSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.shortcuts }
        return Self.shortcuts.filter { $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get started")
                        .font(.title2.bold())
                    Text("Choose or drop a media folder. Louppe scans its subfolders and opens the review in Gallery or Grid.")
                    Text("Mark keepers Yes (F) and rejects No (D). Both keys advance to the next undecided item by default; change this in Settings → Review. Stars (0–5) and color labels are separate from that decision.")
                    Text("Use Export to copy chosen media. The Clean Up toolbar action asks before moving rejects to the macOS Trash.")
                    Text("Decisions, stars, and color labels save automatically. Reopen the same folder to continue. Marking No never trashes a file by itself. Export → Metadata (XMP) makes ratings available to compatible editing apps.")
                    Toggle("Show quick-start tips while reviewing", isOn: $showQuickStart)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Look closer and find similar photos")
                        .font(.headline)
                    Text("Use the zoom slider below the photo or pinch to zoom. Move around an enlarged photo with two-finger scrolling or click and drag. S returns custom zoom to centered 100%, then toggles Fit; A toggles Phone size. Double-click a photo to inspect that point at 100%.")
                    Text("View → Review Groups finds exact duplicates, similar photos, and capture bursts. Analysis stays local and never changes decisions or files. Use Normal Review to return.")
                    Text("In Filter, choose whether matching RAW + JPEG files are reviewed together or separately. The same toggle is available in the Command Palette (⌘K); search for RAW, JPEG, or pairing.")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Supported media")
                        .font(.headline)
                    Text("Photos: common RAW formats, JPEG, HEIC, PNG, TIFF, and other ImageIO formats. Videos: MOV, MP4, M4V, and other macOS media formats. Audio: MP3, M4A, WAV, FLAC, and more.")
                    Text("Some recognized files may appear without a preview when macOS cannot decode them.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard shortcuts")
                        .font(.headline)
                    TextField("Search shortcuts or actions", text: $shortcutSearch)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search keyboard shortcuts")

                    if matchingShortcuts.isEmpty {
                        ContentUnavailableView.search(text: shortcutSearch)
                    } else {
                        ForEach(matchingShortcuts) { shortcut in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(shortcut.keys)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 122, alignment: .leading)
                                Text(shortcut.action)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Divider()

                Link("Contact Alex · a@alex-markin.com", destination: URL(string: "mailto:a@alex-markin.com")!)
            }
            .frame(maxWidth: 570, alignment: .leading)
            .padding(24)
        }
        .background(Color.appBackground)
    }
}
