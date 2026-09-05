import SwiftUI

/// The toolbar sort popover, styled after FilterView: pick a sort key and a
/// direction, and choose whether the visible list divides into groups.
/// It only reorders what's shown and never touches ratings.
struct SortView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort")
                .font(.headline)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("Sort by", spacing: 2) {
                        keyRow("Date taken", .captureDate)
                        keyRow("Name", .name)
                        keyRow("Decision", .decision)
                        keyRow("Star rating", .starRating)
                        keyRow("Color label", .colorLabel)
                        keyRow("Subfolder", .subfolder, disabled: store.availableSubfolders.count <= 1)
                        keyRow("File type", .fileType)
                        keyRow("Media type", .mediaKind, disabled: store.availableMediaKinds.count <= 1)
                        keyRow("Camera", .camera)
                        keyRow("Lens", .lens)
                        keyRow("Aperture", .aperture, disabled: store.apertureRange == nil)
                        keyRow("Shutter speed", .shutterSpeed, disabled: store.shutterRange == nil)
                        keyRow("ISO", .iso, disabled: store.isoRange == nil)
                        keyRow("Media duration", .duration, disabled: store.durationRange == nil)
                        keyRow(
                            "Video resolution",
                            .videoResolution,
                            disabled: store.availableVideoResolutions.count <= 1
                        )
                        keyRow(
                            "Video frame rate",
                            .videoFrameRate,
                            disabled: store.videoFrameRateRange == nil
                        )
                        keyRow(
                            "Video codec",
                            .videoCodec,
                            disabled: store.availableVideoCodecs.count <= 1
                        )
                    }

                    Divider()

                    section("Order") {
                        orderRow(store.sort.key.ascendingLabel, ascending: true)
                        orderRow(store.sort.key.descendingLabel, ascending: false)
                    }

                    Divider()

                    section("Groups") {
                        Toggle("Divide into groups", isOn: $store.isGroupingEnabled)
                            .toggleStyle(.checkbox)
                            // Name sorting never divides: every file name is unique.
                            .disabled(store.sort.key == .name)
                    }

                    Divider()

                    section("Review groups") {
                        if store.isDuplicateBurstAnalysisRunning {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyzing locally…")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel") {
                                    store.cancelDuplicateBurstAnalysis()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Button(
                                store.duplicateBurstAnalysisState == .ready
                                    ? "Refresh Local Analysis"
                                    : "Analyze Folder Locally"
                            ) {
                                store.analyzeDuplicateAndBurstGroups()
                            }
                            .disabled(store.items.isEmpty || store.isFileOperationRunning)
                        }

                        reviewModeRow(.exactDuplicates)
                        reviewModeRow(.likelySimilarPhotos)
                        reviewModeRow(.captureBursts)

                        if store.isGroupedReviewActive {
                            Button("Return to Normal Review") {
                                store.exitGroupedReview()
                            }
                            .buttonStyle(.borderless)
                        }

                        if store.groupedReviewMode == .likelySimilarPhotos {
                            similarityControl
                        }
                        if store.groupedReviewMode == .captureBursts {
                            burstControl
                        }

                        Text(store.duplicateBurstAnalysisSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Review-only: ratings, Clean Up, Export, and originals stay under your control.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 5)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { store.isSortPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 340, height: 560)
        .background(Color.appBackground)
        .tint(Color.louppeAccent)
    }

    private func section(_ title: String, spacing: CGFloat = 8, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func keyRow(_ label: String, _ key: PhotoSort.Key, disabled: Bool = false) -> some View {
        checkRow(label, isSelected: store.sort.key == key, disabled: disabled) {
            store.sort.key = key
        }
    }

    private func orderRow(_ label: String, ascending: Bool) -> some View {
        checkRow(label, isSelected: store.sort.ascending == ascending, disabled: false) {
            store.sort.ascending = ascending
        }
    }

    private func reviewModeRow(_ mode: DuplicateBurstAnalysis.ReviewMode) -> some View {
        checkRow(
            mode.displayName,
            isSelected: store.groupedReviewMode == mode,
            disabled: store.items.isEmpty || store.isFileOperationRunning
        ) {
            store.enterGroupedReview(mode)
        }
    }

    private var similarityControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Similarity")
                Spacer()
                Text(similarityLabel)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(store.visualSimilarityDistance) },
                    set: { store.setVisualSimilarityDistance(Int($0.rounded())) }
                ),
                in: 3...16,
                step: 1
            )
            .accessibilityLabel("Likely-similar photo sensitivity")
            .accessibilityValue(similarityLabel)
            Text("Lower is stricter. Similarity is a local preview cue, not a certainty.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var burstControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Burst interval")
                Spacer()
                Text(String(format: "%.1f s", store.burstGroupingInterval))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { store.burstGroupingInterval },
                    set: { store.setBurstGroupingInterval($0) }
                ),
                in: 0.5...10,
                step: 0.5
            )
            .accessibilityLabel("Capture burst interval")
            .accessibilityValue(String(format: "%.1f seconds", store.burstGroupingInterval))
            Text("Photos are grouped when consecutive capture times are within this gap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var similarityLabel: String {
        switch store.visualSimilarityDistance {
        case ...5: return "Strict"
        case 6...10: return "Balanced"
        default: return "Broad"
        }
    }

    /// A menu-like row: reserved checkmark column so labels stay aligned,
    /// whole width clickable.
    private func checkRow(
        _ label: String,
        isSelected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 14, alignment: .leading)
                    .opacity(isSelected ? 1 : 0)
                Text(label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
