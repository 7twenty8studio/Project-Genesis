import SwiftUI

/// The editor's Premium extras: start from a template, or export as a PDF.
/// Without Premium the same menu shows them, and choosing one opens the
/// Premium screen.
struct JournalExtrasMenu: View {
    let owner: AttachmentOwner
    let onTemplate: (JournalTemplate) -> Void
    let onExport: () -> Void

    @Environment(EntitlementService.self) private var entitlements
    @State private var premium: PremiumFeature?

    var body: some View {
        Menu {
            if isUnlocked {
                items
            } else {
                Section("Premium") { items }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("\(owner.rawValue).extras")
        .premiumSheet($premium)
    }

    @ViewBuilder
    private var items: some View {
        Menu {
            ForEach(JournalTemplate.templates(for: owner)) { template in
                Button(template.title(), systemImage: template.systemImage) {
                    unlocked { onTemplate(template) }
                }
                .accessibilityIdentifier("template.\(template.rawValue)")
            }
        } label: {
            Label("Templates", systemImage: "doc.text")
        }
        .accessibilityIdentifier("journal.templates")
        Button("Export PDF", systemImage: "square.and.arrow.up") {
            unlocked(onExport)
        }
        .accessibilityIdentifier("journal.exportPDF")
    }

    private var isUnlocked: Bool { entitlements.allows(.journalExtras) }

    private func unlocked(_ action: () -> Void) {
        if isUnlocked {
            action()
        } else {
            premium = .journalExtras
        }
    }
}
