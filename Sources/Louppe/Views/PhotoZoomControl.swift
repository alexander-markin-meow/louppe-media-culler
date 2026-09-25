import SwiftUI

/// Compact Gallery zoom control. Fit is an explicit state; the slider shows
/// source-pixel magnification from 5% to 400% on a logarithmic scale.
struct PhotoZoomControl: View {
    @ObservedObject var store: SessionStore

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
                .disabled(store.displayedPhotoZoomScale == nil)
                .accessibilityLabel("Photo zoom")
                .accessibilityValue(currentValueLabel)
                .help("Zoom from 5% to 400%. At 100%, one source pixel fills one display pixel.")

            Text(currentValueLabel)
                .font(.caption.monospacedDigit())
                .frame(width: 45, alignment: .trailing)
        }
        .controlSize(.small)
        .tint(Color.louppeAccent)
    }

    private var currentValueLabel: String {
        guard let scale = store.displayedPhotoZoomScale else { return "…" }
        return "\(Int((scale * 100).rounded()))%"
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                let scale = Double(ActualSizeGeometry.clampedZoom(
                    store.displayedPhotoZoomScale ?? ActualSizeGeometry.minimumZoom
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
