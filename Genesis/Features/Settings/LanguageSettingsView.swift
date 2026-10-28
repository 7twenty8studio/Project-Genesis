import SwiftUI

/// Settings › Language: the iPhone's language, English or Español. The
/// screens change the next time Versely opens, so a new choice says so.
struct LanguageSettingsView: View {
    @Environment(\.palette) private var palette
    @State private var choice = AppLanguageChoice.saved

    var body: some View {
        List {
            ThemedRows {
                Section {
                    ForEach(AppLanguageChoice.allCases) { item in
                        Button {
                            choice = item
                            AppLanguageChoice.saved = item
                        } label: {
                            HStack {
                                Text(verbatim: item.title)
                                    .foregroundStyle(palette.text)
                                Spacer()
                                if choice == item {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(choice == item ? .isSelected : [])
                        .accessibilityIdentifier("language.\(item.rawValue)")
                    }
                } footer: {
                    Text("Versely is available in English and Spanish. Widgets follow your iPhone's language.")
                }
                .listRowBackground(palette.surface)

                if choice != AppLanguageChoice.atLaunch {
                    Section {
                        Label("Close Versely and open it again to see it in \(choice.title).", systemImage: "arrow.clockwise")
                            .foregroundStyle(palette.text)
                            .accessibilityIdentifier("language.reopen")
                    }
                    .listRowBackground(palette.surface)
                    .transition(.opacity)
                }
            }
        }
        .animation(Motion.easeOut(0.2), value: choice)
        .themedScreen()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
