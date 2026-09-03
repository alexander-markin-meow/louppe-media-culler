import SwiftUI

/// One quiet metadata row that reveals exact cue values only on request. It
/// never appears in Grid cells and never changes review metadata.
struct CameraQualityCuesRow: View {
    let item: PhotoItem
    let analysis: HistogramAnalysis?
    let analysisSource: HistogramAnalysisSource
    let isRawAnalysisPending: Bool
    let preferences: CameraQualityWarningPreferences
    @State private var isPopoverPresented = false

    private var warnings: [CameraQualityWarning] {
        CameraQualityWarning.warnings(
            for: item,
            analysis: analysis,
            analysisSource: analysisSource,
            preferences: preferences
        )
    }

    var isVisible: Bool {
        !warnings.isEmpty
    }

    var body: some View {
        if !warnings.isEmpty {
            Button {
                isPopoverPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text("⚠︎ \(warnings.count) quality \(warnings.count == 1 ? "cue" : "cues")")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(warnings.count) quality \(warnings.count == 1 ? "cue" : "cues")"
            )
            .accessibilityHint("Show exact values and sources")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
                qualityCuesPopover
            }
        }
    }

    private var qualityCuesPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quality cues")
                .font(.subheadline.weight(.semibold))

            ForEach(warnings) { warning in
                warningRow(warning)
            }

            if let clippingSourceDescription {
                Text(clippingSourceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isRawAnalysisPending {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking RAW data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var clippingSourceDescription: String? {
        warnings.first { warning in
            warning.kind == .highlightClipping
                || warning.kind == .shadowClipping
        }?.source.description
    }

    private func warningRow(_ warning: CameraQualityWarning) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(warning.title)
                .font(.callout.weight(.medium))
            Text(warning.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Source: \(warning.source.label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.accessibilityLabel)
    }
}

/// The preferences page deliberately exposes only the three practical
/// thresholds behind the optional review cues.
struct CameraQualityWarningsSettingsView: View {
    @AppStorage(CameraQualityWarningPreferences.Keys.isEnabled)
    private var isEnabled = true
    @AppStorage(CameraQualityWarningPreferences.Keys.highISOThreshold)
    private var highISOThreshold = CameraQualityWarningPreferences.defaultHighISOThreshold
    @AppStorage(CameraQualityWarningPreferences.Keys.slowShutterThreshold)
    private var slowShutterThreshold = CameraQualityWarningPreferences.defaultSlowShutterThreshold
    @AppStorage(CameraQualityWarningPreferences.Keys.clippingPercentageThreshold)
    private var clippingPercentageThreshold = CameraQualityWarningPreferences.defaultClippingPercentageThreshold

    var body: some View {
        Form {
            Section {
                Toggle("Show quality cues", isOn: $isEnabled)
            } footer: {
                Text("Optional review cues only — they never affect ratings, filters, selection, exports, sidecars, or files.")
            }

            Section("Cue thresholds") {
                Picker("High ISO", selection: $highISOThreshold) {
                    ForEach(
                        CameraQualityWarningPreferences.highISOThresholdOptions,
                        id: \.self
                    ) { threshold in
                        Text("ISO \(MetadataFormat.iso(threshold)) or above")
                            .tag(threshold)
                    }
                }

                Picker("Slow shutter", selection: $slowShutterThreshold) {
                    ForEach(
                        CameraQualityWarningPreferences.slowShutterThresholdOptions,
                        id: \.self
                    ) { threshold in
                        Text("\(shutter(threshold)) or slower")
                            .tag(threshold)
                    }
                }

                Picker("Clipping", selection: $clippingPercentageThreshold) {
                    ForEach(
                        CameraQualityWarningPreferences.clippingPercentageThresholdOptions,
                        id: \.self
                    ) { threshold in
                        Text("\(percentage(threshold)) near black or white")
                            .tag(threshold)
                    }
                }
            }
            .disabled(!isEnabled)

            Section {
                Button("Restore Quality Cue Defaults") {
                    isEnabled = true
                    highISOThreshold = CameraQualityWarningPreferences.defaultHighISOThreshold
                    slowShutterThreshold = CameraQualityWarningPreferences.defaultSlowShutterThreshold
                    clippingPercentageThreshold = CameraQualityWarningPreferences.defaultClippingPercentageThreshold
                }
            }

            Section {
                Text(CameraQualityWarning.clippingSettingsDescription)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .tint(Color.louppeAccent)
    }

    private func shutter(_ value: Double) -> String {
        let formatted = MetadataFormat.shutter(value)
        return formatted.hasSuffix("s") ? formatted : "\(formatted)s"
    }

    private func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
