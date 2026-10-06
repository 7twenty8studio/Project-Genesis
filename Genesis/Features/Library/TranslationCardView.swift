import SwiftUI

/// One Bible in the Global Reading Library: its name, what it's like
/// (approach, reading level, audio, rights) and a Read or Download button.
struct TranslationCardView: View {
    let entry: LibraryEntry
    let isCurrent: Bool
    let isDownloading: Bool
    let read: () -> Void
    let download: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                header
                Spacer(minLength: 8)
                action
            }
            if !entry.translation.summary.isEmpty {
                Text(entry.translation.summary)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            facts
        }
        .padding(.vertical, 6)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.translation.abbreviation)
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.translation.name)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(entry.isInstalled ? "bibles.installed.\(entry.id)" : "bibles.available.\(entry.id)")
    }

    /// "1769 · On this device" or "2023 · 4.2 MB".
    private var subtitle: String {
        var parts = [entry.translation.year]
        if entry.isInstalled {
            parts.append(String(localized: "On this device"))
        } else if let download = entry.download {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(download.fileBytes), countStyle: .file))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var action: some View {
        if isDownloading {
            ProgressView()
                .accessibilityLabel(entry.isInstalled ? String(localized: "Updating") : String(localized: "Downloading"))
        } else if isCurrent {
            Label(String(localized: "Reading now", comment: "On a Bible's card: this is the Bible being read"), systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("bibles.current.\(entry.id)")
        } else if entry.isInstalled {
            Button(String(localized: "Read", comment: "Button: start reading this Bible"), action: read)
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityLabel(String(localized: "Read \(entry.translation.name)"))
                .accessibilityIdentifier("bibles.read.\(entry.id)")
        } else {
            Button(action: download) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .accessibilityLabel(String(localized: "Download \(entry.translation.name)"))
            .accessibilityIdentifier("bibles.download.\(entry.id)")
        }
    }

    // MARK: Facts

    private struct Fact: Hashable {
        let systemImage: String
        let text: String
    }

    private var factList: [Fact] {
        var list: [Fact] = []
        if let approach = entry.profile.approach {
            list.append(Fact(systemImage: approach.systemImage, text: approach.title))
        }
        if let level = entry.profile.readingLevel {
            list.append(Fact(systemImage: "textformat", text: level.title))
        }
        list.append(entry.hasRecordedAudio
            ? Fact(systemImage: "waveform", text: String(localized: "Recorded audio"))
            : Fact(systemImage: "speaker.wave.2", text: String(localized: "Read aloud by a device voice")))
        if let rights = entry.profile.rights {
            list.append(Fact(systemImage: rights == .publicDomain ? "checkmark.seal" : "doc.text", text: rights.title))
        }
        return list
    }

    @ViewBuilder
    private var facts: some View {
        let list = factList
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(list, id: \.self) { factView($0) }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(0..<(list.count + 1) / 2, id: \.self) { row in
                        GridRow {
                            factView(list[row * 2])
                            if row * 2 + 1 < list.count {
                                factView(list[row * 2 + 1])
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bibles.facts.\(entry.id)")
    }

    private func factView(_ fact: Fact) -> some View {
        Label {
            Text(fact.text).foregroundStyle(palette.secondaryText)
        } icon: {
            Image(systemName: fact.systemImage).foregroundStyle(palette.accent)
        }
        .font(.caption)
    }
}
