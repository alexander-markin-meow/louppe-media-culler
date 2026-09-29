import SwiftUI

struct ReviewPreferencesSettingsView: View {
    @State private var preferences = ReviewPreferences.load()
    @AppStorage(RawDisplayMode.preferenceKey) private var rawDisplayMode = RawDisplayMode.fast
    @AppStorage(AppleRawDecoder.preferenceKey) private var rawDecoder = AppleRawDecoder.appleDefault

    var body: some View {
        Form {
            Section {
                Toggle("Advance after a decision", isOn: $preferences.advancesAfterDecision)
            }

            Section {
                Picker("View", selection: $preferences.defaultView) {
                    Text("Gallery").tag(ViewMode.gallery)
                    Text("Grid").tag(ViewMode.grid)
                }
                Picker("Sort by", selection: $preferences.defaultSort.key) {
                    ForEach(PhotoSort.Key.allCases, id: \.self) { key in
                        Text(key.preferenceTitle).tag(key)
                    }
                }
                Picker("Order", selection: $preferences.defaultSort.ascending) {
                    Text(preferences.defaultSort.key.ascendingLabel).tag(true)
                    Text(preferences.defaultSort.key.descendingLabel).tag(false)
                }
                Toggle("Divide into groups", isOn: $preferences.isGroupingEnabled)
                    .disabled(preferences.defaultSort.key == .name)
            } header: {
                Text("New folders")
            }

            Section {
                Picker("RAW display", selection: $rawDisplayMode) {
                    Text("Fast").tag(RawDisplayMode.fast)
                    Text("RAW at all zoom levels").tag(RawDisplayMode.raw)
                }
                Picker("Apple RAW decoder", selection: $rawDecoder) {
                    ForEach(AppleRawDecoder.allCases, id: \.self) { decoder in
                        Text(decoder.title).tag(decoder)
                            .disabled(decoder == .raw9 && !AppleRawDecoder.supportsRAW9)
                    }
                }
            }

            Section {
                Button("Restore Review Defaults") {
                    preferences = ReviewPreferences()
                    rawDisplayMode = .fast
                    rawDecoder = .appleDefault
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: preferences) { _, value in value.save() }
        .onAppear { preferences = ReviewPreferences.load() }
        .tint(Color.louppeAccent)
    }
}
