import SwiftUI

/// Report, block and delete for anything people post, offered as a menu
/// button and on long press. App Store guideline 1.2 requires reporting and
/// blocking wherever people can see each other's posts.
struct ContentActions: ViewModifier {
    let kind: ContentKind
    let id: UUID
    let authorName: String
    let isMine: Bool
    /// The author, or a group leader for group content.
    let canRemove: Bool
    let onRemove: () async -> Void
    let onBlock: () async -> Void
    let onHidden: () -> Void

    @Environment(CommunityStore.self) private var community
    @State private var reporting = false
    @State private var confirmingBlock = false
    @State private var confirmingRemove = false
    @State private var thanks = false

    /// `value` is sent to the server as the report reason (kept in English);
    /// `title` is what people see.
    struct Reason: Sendable {
        let value: String
        let title: String
    }

    static let reasons: [Reason] = [
        Reason(value: "Abusive or hateful", title: String(localized: "Abusive or hateful")),
        Reason(value: "Sexual or inappropriate", title: String(localized: "Sexual or inappropriate")),
        Reason(value: "Spam or advertising", title: String(localized: "Spam or advertising")),
        Reason(value: "Shares private information", title: String(localized: "Shares private information")),
        Reason(value: "Something else", title: String(localized: "Something else")),
    ]

    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        // A visible "…" menu too, for people who don't know about long press.
        HStack(alignment: .top, spacing: 4) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.secondaryText)
            .accessibilityLabel("More")
            .accessibilityIdentifier("content.more")
        }
            .contextMenu { menuItems }
            .confirmationDialog("Report this?", isPresented: $reporting, titleVisibility: .visible) {
                ForEach(Self.reasons, id: \.value) { reason in
                    Button(reason.title) {
                        Task {
                            if await community.report(kind, id: id, reason: reason.value) {
                                // Hide it once the thank-you is dismissed: hiding first
                                // removes this row, and its alert with it.
                                thanks = true
                            }
                        }
                    }
                }
            } message: {
                Text("Reports are private. It will be hidden for you and reviewed.")
            }
            .confirmationDialog("Block \(authorName)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Task {
                        await onBlock()
                        onHidden()
                    }
                }
            } message: {
                Text("You won't see their posts, prayer requests or comments. They aren't told.")
            }
            .confirmationDialog("Delete this?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await onRemove() }
                }
            }
            .alert("Thank you", isPresented: $thanks) {
                Button("OK", role: .cancel) { onHidden() }
            } message: {
                Text("Thanks for helping keep Genesis a safe place. You can also block this person from the same menu.")
            }
    }

    @ViewBuilder
    private var menuItems: some View {
        if canRemove {
            Button("Delete", systemImage: "trash", role: .destructive) { confirmingRemove = true }
        }
        if !isMine {
            Button("Report", systemImage: "flag") { reporting = true }
            Button("Block \(authorName)", systemImage: "hand.raised") { confirmingBlock = true }
        }
    }
}

extension View {
    func contentActions(
        _ kind: ContentKind,
        id: UUID,
        authorName: String,
        isMine: Bool,
        canRemove: Bool,
        onRemove: @escaping () async -> Void,
        onBlock: @escaping () async -> Void,
        onHidden: @escaping () -> Void = {}
    ) -> some View {
        modifier(ContentActions(kind: kind, id: id, authorName: authorName, isMine: isMine, canRemove: canRemove, onRemove: onRemove, onBlock: onBlock, onHidden: onHidden))
    }
}
