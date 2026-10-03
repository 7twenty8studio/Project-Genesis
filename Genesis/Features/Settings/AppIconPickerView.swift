import SwiftUI

/// Settings › App Icon: the standard icon, Night, the four seasons, or
/// Seasons to change with the calendar.
struct AppIconPickerView: View {
    @Environment(\.palette) private var palette
    @State private var choice = AppIcon.choice

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 18)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(AppIconChoice.allCases) { item in
                    Button {
                        choice = item
                        AppIcon.choice = item
                    } label: {
                        VStack(spacing: 8) {
                            Image(item.previewName)
                                .resizable()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    if item == .seasons {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.accent)
                                            .padding(5)
                                            .background(palette.surface, in: Circle())
                                            .offset(x: 6, y: 6)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder(choice == item ? palette.accent : palette.separator, lineWidth: choice == item ? 3 : 1)
                                        .padding(-4)
                                )
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(choice == item ? palette.accent : palette.text)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(choice == item ? .isSelected : [])
                    .accessibilityIdentifier("appIcon.\(item.rawValue)")
                }
            }
            .padding(24)

            Text("Seasons changes the icon through the year: Autumn, Winter, Spring and Summer, by where you live. iPhone shows a short notice whenever an app's icon changes.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 24)
        }
        .themedScreen()
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
