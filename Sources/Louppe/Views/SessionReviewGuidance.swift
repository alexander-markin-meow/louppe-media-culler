import SwiftUI

/// A single status strip below the media, with optional first-use guidance.
struct SessionReviewFooter: View {
    @ObservedObject var store: SessionStore
    @AppStorage("louppe.showQuickStart") private var showQuickStart = true

    var body: some View {
        VStack(spacing: 4) {
            if showQuickStart {
                HStack(spacing: 8) {
                    Text("F Yes · D No · arrows browse · ⌘Z undo. Decisions save automatically; No leaves files in place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help("F marks Yes and D marks No. By default, they move to the next undecided item; change this in Settings → Review. Arrow keys browse; ⌘Z undoes. Decisions save automatically, and No never moves files to Trash.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss tips", systemImage: "xmark") {
                        showQuickStart = false
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide this tip. See Help > Louppe Help for shortcuts.")
                }
            }

            HStack(spacing: 0) {
                Text(informationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(informationSummary)
                    .accessibilityLabel(informationSummary)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Group {
                    if store.viewMode == .gallery,
                       let item = store.currentItem,
                       item.mediaKind == .photo && item.isSupported {
                        PhotoZoomControl(store: store)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: store.currentItem?.isRaw == true ? 300 : 240, height: 28)

                Text(store.sessionSaveStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Decisions, stars, and labels save automatically. Reopen this folder to continue. Use Export → Metadata (XMP) to share ratings with other editing apps.")
                    .accessibilityLabel("Session: \(store.sessionSaveStatus)")
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.appBackground)
    }

    private var informationSummary: String {
        var parts: [String] = []
        if store.filter.isActive {
            parts.append(store.filter.reviewSummary)
        }
        if store.isReviewComplete && !store.isGroupedReviewActive {
            parts.append("Review complete: \(store.yesCount) Yes · \(store.noCount) No")
        }
        return parts.joined(separator: "  ·  ")
    }
}

extension PhotoFilter {
    var reviewSummary: String {
        var parts: [String] = []
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { parts.append("Search: “\(search)”") }
        if !excludedDecisionStates.isEmpty {
            let choices: [(PhotoItemRatingState, String)] = [
                (.yes, "Yes"), (.no, "No"), (.undecided, "Undecided"), (.mixed, "Mixed")
            ]
            let included = choices.filter { !excludedDecisionStates.contains($0.0) }.map(\.1)
            parts.append("Decision: " + (included.isEmpty ? "none" : included.joined(separator: ", ")))
        }
        if !excludedStarStates.isEmpty { parts.append("Stars") }
        if !excludedColorStates.isEmpty { parts.append("Color") }
        if dateEnabled { parts.append("Date") }
        if !excludedTypes.isEmpty { parts.append("File type") }
        if !excludedMediaKinds.isEmpty { parts.append("Media type") }
        if !excludedSubfolders.isEmpty { parts.append("Subfolder") }
        if !excludedCameras.isEmpty { parts.append("Camera") }
        if !excludedLenses.isEmpty { parts.append("Lens") }
        if apertureEnabled || shutterEnabled || isoEnabled { parts.append("Exposure") }
        if durationEnabled { parts.append("Duration") }
        if videoFrameRateEnabled || !excludedVideoResolutions.isEmpty || !excludedVideoCodecs.isEmpty {
            parts.append("Video details")
        }
        return "Filters: " + parts.joined(separator: " · ")
    }
}
