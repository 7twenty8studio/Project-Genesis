import SwiftUI

/// Text to put into the notes at the cursor from outside the editor: a
/// verse reference (Church Mode's lookup) or a template.
struct SermonNotesInsertion: Equatable {
    enum Kind: Equatable {
        case reference(String)
        case template(String)
    }

    let kind: Kind
    let id = UUID()
}

/// The notes, edited formatted: bold, italic, headings, lists and quotes
/// show as they look, from the buttons or the system's text menu. They're
/// saved as Markdown (`SermonRichText` converts both ways).
struct SermonNotesEditor: View {
    @Binding var text: String
    @Binding var insertion: SermonNotesInsertion?
    var largeText = false

    @State private var richText = AttributedString()
    @State private var selection = AttributedTextSelection()
    /// The Markdown last written to `text`, so the editor knows its own changes.
    @State private var written: String?
    /// Whether the person has placed the cursor; until then insertions go at the end.
    @State private var hasCursor = false
    @FocusState private var isFocused: Bool
    @Environment(\.palette) private var palette
    @Environment(\.fontResolutionContext) private var fontContext

    private var style: SermonRichText.Style {
        SermonRichText.Style(largeText: largeText, quoteColor: palette.secondaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formatBar
            TextEditor(text: $richText, selection: $selection)
                .font(style.body)
                .foregroundStyle(palette.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: largeText ? 320 : 240)
                .focused($isFocused)
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("sermon.body")
        }
        .onAppear { load() }
        .onChange(of: text) { if text != written { load() } }
        .onChange(of: largeText) { load() }
        .onChange(of: palette) { load() }
        .onChange(of: isFocused) { if isFocused { hasCursor = true } }
        .onChange(of: richText) { old, _ in edited(from: old) }
        .onChange(of: insertion) { insertPending() }
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            ForEach(SermonMarkdown.Format.allCases) { format in
                Button {
                    apply(format)
                } label: {
                    Image(systemName: format.systemImage)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(format.title)
                .accessibilityIdentifier("sermon.format.\(format.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.accent)
    }

    // MARK: Loading and saving

    private func load() {
        let cursor = SermonRichText.offsets(of: selection, in: richText)
        richText = SermonRichText.attributed(text, style: style)
        selection = SermonRichText.selection(cursor, in: richText)
        written = text
    }

    /// After every change: carry lists and quotes on after Return, keep each
    /// line's style whole, and save the Markdown.
    private func edited(from old: AttributedString) {
        var updated = richText
        var cursor = SermonRichText.offsets(of: selection, in: updated)
        var typing: AttributeContainer?
        if cursor.isEmpty,
           let ended = SermonRichText.endedLine(old: String(old.characters), new: String(updated.characters), cursor: cursor.lowerBound) {
            if SermonRichText.endsList(ended.text) {
                updated = SermonRichText.replacing(ended.start..<cursor.lowerBound, with: AttributedString(), in: updated)
                cursor = ended.start..<ended.start
            } else if let mark = SermonRichText.continuation(of: ended.text) {
                updated = SermonRichText.replacing(cursor, with: AttributedString(mark), in: updated)
                let end = cursor.lowerBound + mark.count
                cursor = end..<end
            } else {
                // A heading ends with its line; a quote carries on.
                switch SermonRichText.lineStyle(at: ended.start, in: updated) {
                case .heading: typing = style.typingAttributes(nil)
                case .quote: typing = style.typingAttributes(.quote)
                case nil: break
                }
            }
        }
        updated = SermonRichText.normalized(updated, style: style, context: fontContext)
        if updated != richText {
            richText = updated
            selection = SermonRichText.selection(cursor, in: updated, typingAttributes: typing)
        } else if let typing {
            selection = SermonRichText.selection(cursor, in: updated, typingAttributes: typing)
        }
        let markdown = SermonRichText.markdown(richText, context: fontContext)
        if markdown != text {
            written = markdown
            text = markdown
        }
    }

    // MARK: Formatting

    private func apply(_ format: SermonMarkdown.Format) {
        switch format {
        case .bold, .italic: toggleInline(format)
        default: toggleLines(format)
        }
    }

    /// Bold or italic on the selection (or for what's typed next), off when
    /// it's all that already.
    private func toggleInline(_ format: SermonMarkdown.Format) {
        let base = style.body
        let context = fontContext
        let fonts = selection.attributes(in: richText).map { $0[SermonRichText.FontAttribute.self] ?? base }
        let isOn = !fonts.isEmpty && fonts.allSatisfy { font in
            let resolved = font.resolve(in: context)
            return format == .bold ? resolved.isBold : resolved.isItalic
        }
        richText.transformAttributes(in: &selection) { attributes in
            let font = attributes[SermonRichText.FontAttribute.self] ?? base
            attributes[SermonRichText.FontAttribute.self] = format == .bold ? font.bold(!isOn) : font.italic(!isOn)
        }
    }

    private func toggleLines(_ format: SermonMarkdown.Format) {
        let range = SermonRichText.offsets(of: selection, in: richText)
        // An empty line has nothing to style yet: what's typed next takes it.
        if let lineStyle = format.lineStyle, range.isEmpty, SermonRichText.isEmptyLine(at: range.lowerBound, in: richText) {
            let isOn = selection.typingAttributes(in: richText)[SermonLineStyleAttribute.self] == lineStyle
            selection = SermonRichText.selection(range, in: richText, typingAttributes: style.typingAttributes(isOn ? nil : lineStyle))
            return
        }
        let result = SermonRichText.toggling(format, in: richText, selection: range, style: style, context: fontContext)
        richText = result.text
        selection = SermonRichText.selection(result.selection, in: result.text)
    }

    // MARK: Insertions

    private func insertPending() {
        guard let insertion else { return }
        self.insertion = nil
        let plain = String(richText.characters)
        let cursor = hasCursor ? SermonRichText.offsets(of: selection, in: richText).upperBound : nil
        switch insertion.kind {
        case let .reference(reference):
            let edit = SermonMarkdown.inserting(reference, into: plain, at: cursor)
            let position = min(cursor ?? plain.count, plain.count)
            let added = String(Array(edit.text)[position..<(position + edit.text.count - plain.count)])
            richText = SermonRichText.replacing(position..<position, with: AttributedString(added), in: richText)
            selection = SermonRichText.selection(edit.selection, in: richText)
        case let .template(markdown):
            let template = SermonRichText.attributed(markdown, style: style)
            if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                richText = template
                selection = SermonRichText.selection(template.characters.count..<template.characters.count, in: richText)
                return
            }
            let characters = Array(plain)
            let position = min(cursor ?? characters.count, characters.count)
            let separators = JournalTemplate.separators(before: String(characters[..<position]), after: String(characters[position...]))
            var added = AttributedString(separators.prefix)
            added.append(template)
            let end = position + added.characters.count
            added.append(AttributedString(separators.suffix))
            richText = SermonRichText.replacing(position..<position, with: added, in: richText)
            selection = SermonRichText.selection(end..<end, in: richText)
        }
    }
}
