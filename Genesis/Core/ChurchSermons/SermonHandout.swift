import Foundation

/// One blank in a published outline (fill-in-the-blank handouts, migration
/// 20261128000000). The outline's text holds "[[n]]" where it goes. The
/// answer comes only once the church has revealed the key for this
/// revision, and never for an open blank (the member's own words).
struct SermonBlank: Codable, Hashable, Sendable {
    let n: Int
    let open: Bool
    let hint: String?
    let answer: String?

    /// Whether this blank has a key to check against.
    var isCheckable: Bool { !open && answer != nil }
}

/// Whether readers have the key: "hidden" until the pastor reveals it,
/// "revealed", or "never" (nothing is checked).
enum SermonAnswers: String, Codable, Hashable, Sendable {
    case hidden, revealed, never
}

/// The pure rules for blanks, the same as the guest page's
/// (web/src/lib/blanks.ts).
enum SermonBlanks {
    enum Piece: Hashable, Sendable {
        case text(String)
        case blank(Int)
    }

    /// Splits published text at its "[[n]]" markers; a marker with no
    /// blank of that number stays as words.
    static func pieces(_ text: String, known: (Int) -> Bool) -> [Piece] {
        var out: [Piece] = []
        var rest = Substring(text)
        var words = ""
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            let digits = after.prefix { $0.isASCII && $0.isNumber }
            let close = after.index(after.startIndex, offsetBy: digits.count)
            if (1...3).contains(digits.count), after[close...].hasPrefix("]]"), let n = Int(digits), known(n) {
                words += rest[..<open.lowerBound]
                if !words.isEmpty { out.append(.text(words)) }
                words = ""
                out.append(.blank(n))
                rest = after[after.index(close, offsetBy: 2)...]
            } else {
                words += rest[..<open.upperBound]
                rest = after
            }
        }
        words += rest
        if !words.isEmpty { out.append(.text(words)) }
        return out
    }

    /// The blank numbers in a piece of text, in order.
    static func numbers(in text: String, known: (Int) -> Bool) -> [Int] {
        pieces(text, known: known).compactMap { if case let .blank(n) = $0 { n } else { nil } }
    }

    /// Text with each blank as a line (for Copy), or as the given words.
    static func filled(_ text: String, known: (Int) -> Bool, fill: (Int) -> String = { _ in "_____" }) -> String {
        pieces(text, known: known).map { piece in
            switch piece {
            case let .text(words): words
            case let .blank(n): fill(n)
            }
        }
        .joined()
    }

    /// An answer as it's compared: case, accents, spacing and the
    /// punctuation around it don't count.
    static func normalized(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let trimmed = folded.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether a member's words match the key.
    static func isCorrect(_ response: String, answer: String) -> Bool {
        let r = normalized(response)
        return !r.isEmpty && r == normalized(answer)
    }
}

/// A member's own saved work on a church's handout: the revision they
/// filled in (its outline, so it still opens after an unpublish), their
/// answers, and the key only if they had it once it was revealed. Kept
/// with their sermon notes (`Sermon.handouts`, synced as
/// sermons.handouts) and never sent to the church. A later edit by the
/// church makes a new revision, so it never changes how this one is
/// checked.
struct SermonHandout: Codable, Hashable, Sendable, Identifiable {
    var sermonID: UUID
    var slug: String
    var revision: Int
    var title: String
    var church: String
    var savedAt: Date
    var blocks: [HandoutBlock]
    /// Answers only when the key was saved.
    var blanks: [SermonBlank]
    /// The member's words, by blank number.
    var responses: [String: String]

    var id: String { "\(sermonID.uuidString)-\(revision)" }

    /// "sermonId", so the key survives sync's snake_case round trip
    /// (sermon_id comes back as sermonId).
    enum CodingKeys: String, CodingKey {
        case sermonID = "sermonId"
        case slug, revision, title, church, savedAt, blocks, blanks, responses
    }

    /// Whether this saved copy can be checked: it holds the revealed key.
    var hasKey: Bool { blanks.contains(where: \.isCheckable) }

    var outline: [SermonBlock] { blocks.compactMap(\.block) }

    /// A new saved copy of this revision.
    init(sermon: PublishedSermon, responses: [String: String], keepKey: Bool, savedAt: Date = .now) {
        sermonID = sermon.id
        slug = sermon.slug
        revision = sermon.revision
        title = sermon.title
        church = sermon.church
        self.savedAt = savedAt
        blocks = sermon.blocks.map(HandoutBlock.init)
        blanks = sermon.blanks.map { blank in
            SermonBlank(n: blank.n, open: blank.open, hint: blank.hint, answer: keepKey ? blank.answer : nil)
        }
        self.responses = responses
    }

    /// The saved copies kept per sermon notes (the server keeps at most 10).
    static let maximumKept = 10

    /// The most bytes kept (the server takes up to 1,000,000).
    static let maximumBytes = 900_000

    /// The newest saved copies that fit, encoded: at most `maximumKept`, and
    /// the oldest dropped first while they're over `maximumBytes`.
    static func encodeKept(_ handouts: [SermonHandout]) -> String {
        var kept = Array(handouts.suffix(maximumKept))
        var raw = encode(kept)
        while raw.utf8.count > maximumBytes, !kept.isEmpty {
            kept.removeFirst()
            raw = encode(kept)
        }
        return raw
    }

    /// Encoded for `Sermon.handoutsRaw`.
    static func encode(_ handouts: [SermonHandout]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard !handouts.isEmpty, let data = try? encoder.encode(handouts) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ raw: String) -> [SermonHandout] {
        guard !raw.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SermonHandout].self, from: Data(raw.utf8))) ?? []
    }
}

/// One block of a saved handout, as published (Scripture as a reference
/// only, never its words).
struct HandoutBlock: Codable, Hashable, Sendable {
    var id: String
    var kind: String
    var text: String?
    var level: Int?
    var items: [String]?
    var ordered: Bool?
    var raw: String?
    var start: Int?
    var end: Int?
    var status: String?
    var label: String?
    var translation: String?

    init(_ block: SermonBlock) {
        id = block.id
        switch block {
        case let .heading(_, text, level):
            kind = "heading"
            self.text = text
            self.level = level
        case let .paragraph(_, text):
            kind = "paragraph"
            self.text = text
        case let .quote(_, text):
            kind = "quote"
            self.text = text
        case let .list(_, items, ordered):
            kind = "list"
            self.items = items
            self.ordered = ordered
        case let .scripture(_, reference):
            kind = "scripture"
            raw = reference.raw
            start = reference.start?.rawValue
            end = reference.end?.rawValue
            status = reference.status.rawValue
            label = reference.label
            translation = reference.translation
        }
    }

    var block: SermonBlock? {
        switch kind {
        case "heading": text.map { .heading(id: id, text: $0, level: min(max(level ?? 2, 1), 3)) }
        case "paragraph": text.map { .paragraph(id: id, text: $0) }
        case "quote": text.map { .quote(id: id, text: $0) }
        case "list": items.map { .list(id: id, items: $0, ordered: ordered ?? false) }
        case "scripture":
            raw.map { raw in
                let start = start.map(VerseID.init(rawValue:))
                let status = SermonReference.Status(rawValue: status ?? "") ?? .unlinked
                return .scripture(id: id, reference: SermonReference(
                    raw: raw, start: start, end: end.map(VerseID.init(rawValue:)),
                    status: status == .verified && start == nil ? .unlinked : status,
                    label: label, translation: translation, quoteWithheld: false))
            }
        default: nil
        }
    }
}
