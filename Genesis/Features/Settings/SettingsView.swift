import SwiftUI

/// App settings from Home: features, Bibles and account. Reading settings
/// live in the reader ("Aa").
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var showsBibles = false
    @State private var showsAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FeaturesSettingsView()
                    } label: {
                        Label("Features", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("settings.features")
                    Button {
                        showsBibles = true
                    } label: {
                        Label("Bibles", systemImage: "books.vertical")
                    }
                    Button {
                        showsAccount = true
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                }
                .listRowBackground(palette.surface)
                .foregroundStyle(palette.text)

                Section {
                } footer: {
                    Text("Reading settings such as font, theme and page turns are in the reader under Aa.")
                }
            }
            .themedScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("appSettings.done")
                }
            }
            .sheet(isPresented: $showsBibles) { BibleDownloadsView() }
            .sheet(isPresented: $showsAccount) { AccountView() }
        }
    }
}
