import SwiftUI

/// One Bible in the Global Reading Library: its name, what it's like
/// (approach, reading level, audio, rights) and a Read or Download button.
struct TranslationCardView: View {
    let entry: LibraryEntry
    let isCurrent: Bool
    let isDownloading: Bool
    /// How far a YouVersion Bible has come, 0...1 (nil: not measured).
    var progress: Double? = nil
    /// Books an unfinished YouVersion download already has (0 if none).
    var savedBooks = 0
    let read: () -> Void
    let download: () -> Void
    /// Forgets an unfinished download.
    var discard: (() -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(BibleLibrary.self) private var library

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
            downloadState
            facts
            // YouVersion Bibles: said before anyone chooses one (our
            // agreement with YouVersion keeps them out of paid features).
            if entry.translation.isYouVersion {
                Text(String(localized: "Free to read, always. Listening isn't available, and widgets and Premium tools such as Memorize use the \(library.premiumToolsBibleName(for: entry.translation)) with this Bible."))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bibles.youVersionNote.\(entry.id)")
            }
            // A licensed Bible's copyright notice, as the publisher wrote it.
            if entry.translation.isLicensed {
                Text(entry.translation.license)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Parts

    private static let bookCount = YouVersionBibleBuilder.bookCodes.count
    private var savedBookCount: Int { savedBooks }

    /// A YouVersion Bible downloading (a bar, book by book) or paused
    /// partway (how much is kept, to continue later).
    @ViewBuilder
    private var downloadState: some View {
        if isDownloading, let progress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(palette.accent)
                Text(String(localized: "Downloading · \(Int((progress * Double(Self.bookCount)).rounded())) of \(Self.bookCount) books"))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bibles.progress.\(entry.id)")
        } else if !isDownloading, !entry.isInstalled, savedBooks > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(savedBooks), total: Double(Self.bookCount))
                    .tint(palette.secondaryText)
                HStack {
                    Text(String(localized: "Paused · \(savedBookCount) of \(Self.bookCount) books saved"))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if let discard {
                        Button(String(localized: "Discard"), role: .destructive, action: discard)
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("bibles.discard.\(entry.id)")
                    }
                }
            }
        }
    }

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
        } else if let download = entry.download, download.fileBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(download.fileBytes), countStyle: .file))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var action: some View {
        if isDownloading {
            ProgressView()
                .accessibilityLabel(entry.isInstalled ? String(localized: "Updating") : String(localized: "Downloading"))
        } else if !entry.isInstalled, savedBooks > 0 {
            Button(action: download) {
                Label(String(localized: "Continue"), systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .accessibilityLabel(String(localized: "Continue downloading \(entry.translation.name)"))
            .accessibilityIdentifier("bibles.continue.\(entry.id)")
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
        if entry.translation.isYouVersion {
            list.append(Fact(systemImage: "gift", text: String(localized: "Always free", comment: "On a Bible's card: this Bible is free to read")))
        } else {
            list.append(entry.hasRecordedAudio
                ? Fact(systemImage: "waveform", text: String(localized: "Recorded audio"))
                : Fact(systemImage: "speaker.wave.2", text: String(localized: "Read aloud by a device voice")))
        }
        if entry.translation.requiresPremium {
            list.append(Fact(systemImage: "crown", text: String(localized: "With Premium", comment: "On a Bible's card: this Bible needs Premium")))
        }
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
