import SwiftUI

/// Compact Gallery zoom control. Fit is an explicit state; the slider shows
/// source-pixel magnification from 5% to 400% on a logarithmic scale.
struct PhotoZoomControl: View {
    @ObservedObject var store: SessionStore
    @State private var lastReading: ZoomReading?

    private let minimum = Double(ActualSizeGeometry.minimumZoom)
    private let maximum = Double(ActualSizeGeometry.maximumZoom)

    var body: some View {
        HStack(spacing: 5) {
            Button("Fit") { store.zoomToFit() }
                .buttonStyle(.bordered)
                .fontWeight(store.zoomMode == .fit ? .semibold : .regular)
                .accessibilityLabel("Fit photo in window")
                .accessibilityAddTraits(store.zoomMode == .fit ? .isSelected : [])

            Slider(value: sliderValue, in: 0...1)
                .frame(width: 105)
                .disabled(displayedScale == nil)
                .accessibilityLabel("Photo zoom")
                .accessibilityValue(currentValueLabel)
                .help("Zoom from 5% to 400%. At 100%, one source pixel fills one display pixel.")

            Text(currentValueLabel)
                .font(.caption.monospacedDigit())
                .frame(width: 45, alignment: .trailing)
        }
        .controlSize(.small)
        .tint(Color.louppeAccent)
        .onChange(of: currentReading, initial: true) { _, reading in
            if let reading { lastReading = reading }
        }
    }

    private struct ZoomReading: Equatable {
        let revision: PhotoContentRevision
        let scale: CGFloat
    }

    private var currentReading: ZoomReading? {
        guard let revision = store.currentItem?.contentRevision,
              let scale = store.displayedPhotoZoomScale else { return nil }
        return ZoomReading(revision: revision, scale: scale)
    }

    private var displayedScale: CGFloat? {
        if let reading = currentReading { return reading.scale }
        // Fit/Phone report their scale after layout. Hold the current photo's
        // last value during that handoff: sending the native slider to 5%
        // and disabling/re-enabling it interrupts its knob/track animation.
        guard lastReading?.revision == store.currentItem?.contentRevision
        else { return nil }
        return lastReading?.scale
    }

    private var currentValueLabel: String {
        guard let scale = displayedScale else { return "…" }
        return "\(Int((scale * 100).rounded()))%"
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                let scale = Double(ActualSizeGeometry.clampedZoom(
                    displayedScale ?? ActualSizeGeometry.minimumZoom
                ))
                return log(scale / minimum) / log(maximum / minimum)
            },
            set: { fraction in
                let clamped = min(max(fraction, 0), 1)
                let scale = minimum * pow(maximum / minimum, clamped)
                store.setPhotoZoomScale(CGFloat(scale))
            }
        )
    }
}
