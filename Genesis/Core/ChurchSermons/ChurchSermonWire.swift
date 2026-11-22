import Foundation

/// The JSON the church sermon functions return (migrations 20261120000000
/// and 20261124000000's locations),
/// read leniently: a block or field from a later version is skipped rather
/// than failing the whole sermon.
enum ChurchSermonWire {
    /// published_sermon(p_slug).
    static func lookup(from data: Data) throws -> ChurchSermonLookup {
        let status = try JSONDecoder().decode(StatusOnly.self, from: data).status
        switch status {
        case "ok":
            guard let sermon = try JSONDecoder().decode(SermonRow.self, from: data).sermon else { return .notFound }
            return .sermon(sermon)
        case "members_only": return .membersOnly
        default: return .notFound
        }
    }

    /// group_sermons(p_group): published summaries for members; for
    /// leaders, every sermon with its status, of which only the live ones
    /// are kept (drafts are for Church Studio on the web).
    static func archive(from data: Data) throws -> [ChurchSermonSummary] {
        let rows = try JSONDecoder().decode([Lossy<ArchiveRow>].self, from: data).compactMap(\.value)
        return rows.compactMap { row in
            if row.status != nil {
                guard row.status == "published", row.live_audience != nil, row.hidden != true else { return nil }
            }
            return row.summary
        }
    }

    /// search_sermon_churches(p_query).
    static func churches(from data: Data) throws -> [SermonChurch] {
        try JSONDecoder().decode([Lossy<ChurchRow>].self, from: data).compactMap(\.value?.church)
    }

    // MARK: Rows

    private struct StatusOnly: Decodable {
        let status: String
    }

    /// Decodes an element, or nil when it doesn't read.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    struct SummaryRow: Decodable {
        let slug: String
        let title: String?
        let speaker: String?
        let series: String?
        let preached_on: String?
        let audience: String?
        let live_audience: String?

        var summary: ChurchSermonSummary? {
            guard ChurchSermonLink.isSlug(slug) else { return nil }
            return ChurchSermonSummary(
                slug: slug, title: title ?? "", speaker: speaker ?? "", series: series.flatMap(Self.nonEmpty),
                preachedOn: preached_on.map { String($0.prefix(10)) },
                audience: ChurchSermonAudience(rawValue: live_audience ?? audience ?? "") ?? .members
            )
        }

        static func nonEmpty(_ text: String) -> String? {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
    }

    private struct ArchiveRow: Decodable {
        let slug: String
        let title: String?
        let speaker: String?
        let series: String?
        let preached_on: String?
        let audience: String?
        let status: String?
        let live_audience: String?
        let hidden: Bool?

        var summary: ChurchSermonSummary? {
            SummaryRow(slug: slug, title: title, speaker: speaker, series: series, preached_on: preached_on, audience: audience, live_audience: live_audience).summary
        }
    }

    private struct ChurchRow: Decodable {
        let group_id: UUID
        let name: String
        let sermons: [Lossy<SummaryRow>]?

        var church: SermonChurch {
            SermonChurch(id: group_id, name: name, sermons: (sermons ?? []).compactMap { $0.value?.summary })
        }
    }

    private struct CoverRow: Decodable {
        let path: String?
        let alt: String?
        let decorative: Bool?
    }

    private struct ReferenceRow: Decodable {
        let raw: String?
        let start: Int?
        let end: Int?
        let status: String?
        let label: String?
        let translation: String?
        let quote_withheld: Bool?

        var reference: SermonReference? {
            guard let raw else { return nil }
            let status = SermonReference.Status(rawValue: status ?? "") ?? .unlinked
            let start = start.flatMap(Self.verse)
            let end = end.flatMap(Self.verse)
            return SermonReference(
                raw: raw, start: start, end: end,
                // A reference the app can't read doesn't link.
                status: status == .verified && start == nil ? .unlinked : status,
                label: label.flatMap(SummaryRow.nonEmpty),
                translation: translation.flatMap { ChurchSermonQuote.codes.contains($0) ? $0 : nil },
                quoteWithheld: quote_withheld ?? false
            )
        }

        static func verse(_ raw: Int) -> VerseID? {
            let id = VerseID(rawValue: raw)
            guard (1...66).contains(id.book), id.chapter > 0, id.verse > 0 else { return nil }
            return id
        }
    }

    private struct BlockRow: Decodable {
        let id: String
        let kind: String
        let text: String?
        let level: Int?
        let items: [String]?
        let ordered: Bool?
        let ref: ReferenceRow?

        var block: SermonBlock? {
            switch kind {
            case "heading": text.map { SermonBlock.heading(id: id, text: $0, level: min(max(level ?? 2, 1), 3)) }
            case "paragraph": text.map { SermonBlock.paragraph(id: id, text: $0) }
            case "quote": text.map { SermonBlock.quote(id: id, text: $0) }
            case "list": items.map { SermonBlock.list(id: id, items: $0, ordered: ordered ?? false) }
            case "scripture": ref?.reference.map { SermonBlock.scripture(id: id, reference: $0) }
            default: nil
            }
        }
    }

    private struct LocationRow: Decodable {
        let name: String?
        let address: String?
        let times: String?

        var location: ChurchLocation? {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return ChurchLocation(name: name, address: address ?? "", times: times ?? "")
        }
    }

    private struct SermonRow: Decodable {
        let id: UUID
        let slug: String
        let group_id: UUID
        let church: String?
        let title: String?
        let speaker: String?
        let series: String?
        let preached_on: String?
        let location: String?
        let language: String?
        let cover: CoverRow?
        let audience: String?
        let blocks: [Lossy<BlockRow>]?
        let previous: Lossy<SummaryRow>?
        let next: Lossy<SummaryRow>?
        let is_member: Bool?
        let locations: [Lossy<LocationRow>]?

        var sermon: PublishedSermon? {
            guard ChurchSermonLink.isSlug(slug) else { return nil }
            let cover = cover.flatMap { row -> PublishedSermon.Cover? in
                guard let path = row.path, !path.isEmpty else { return nil }
                return PublishedSermon.Cover(path: path, alt: row.alt ?? "", decorative: row.decorative ?? false)
            }
            return PublishedSermon(
                id: id, slug: slug, groupID: group_id, church: church ?? "", title: title ?? "", speaker: speaker ?? "",
                series: series.flatMap(SummaryRow.nonEmpty), preachedOn: preached_on.map { String($0.prefix(10)) },
                location: location ?? "", language: language ?? "en", cover: cover,
                audience: ChurchSermonAudience(rawValue: audience ?? "") ?? .members,
                blocks: (blocks ?? []).compactMap { $0.value?.block },
                previous: previous?.value?.summary, next: next?.value?.summary,
                isMember: is_member ?? false,
                locations: (locations ?? []).compactMap { $0.value?.location }
            )
        }
    }
}

/// The Bibles whose quotations a church may publish (as a code, never the
/// words): the same list as `genesis_quote_translation` in the database.
enum ChurchSermonQuote {
    static let codes: Set<String> = ["KJV", "WEB", "ASV", "RV1909", "BLIVRE"]
}
