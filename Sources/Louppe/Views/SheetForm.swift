import SwiftUI

/// Keeps lengthy setup and review text scrollable without moving the actions.
/// Matches the spacing of the source-folder tools.
struct SheetForm<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            Divider()
            actions()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .background(Color.appBackground)
        .tint(Color.louppeAccent)
    }
}
