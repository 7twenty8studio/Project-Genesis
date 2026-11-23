import Foundation
import UIKit

/// Church sermons kept in memory, for UI tests and unit tests: no network,
/// repeatable. Membership comes from the community backend it's given, and
/// the rules mirror the database's: a link sermon is for anyone, a members
/// sermon only for the church's members (anyone else learns only that it's
/// for members), the archive only for members, search only finds churches
/// that chose to be listed and only their link sermons, a report needs an
/// account, counts once per person, and three hide the sermon.
actor InMemoryChurchSermonBackend: ChurchSermonBackend {
    private struct Row {
        var sermon: PublishedSermon
        var publishedAt: Date
        var hidden = false
        var unpublished = false
    }

    private let community: CommunityBackend
    private var rows: [String: Row] = [:]
    private var listed: [UUID: String] = [:]
    private var reports: [String: Set<UUID>] = [:]
    private(set) var counts: [String: [ChurchSermonEvent: Int]] = [:]
    /// The church's sermons switch; off is as if none existed.
    private var sermonsOn = true
    /// Each church's Locations and Times (the church's own text, not app text).
    private var locations: [UUID: [ChurchLocation]] = [:]

    /// The sample group of InMemoryCommunityBackend ("Grace Fellowship"),
    /// a church with sermons that the test person belongs to.
    static let sampleChurchID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    /// A listed church the test person isn't in.
    static let otherChurchID = UUID(uuidString: "00000000-0000-0000-0000-00000000C1C1")!
    /// Published to the link, the first in a series.
    static let linkSlug = "restweary1"
    /// Members only, the next in the series.
    static let membersSlug = "restweary2"
    /// Another church's members-only sermon.
    static let otherMembersSlug = "rivermemb1"
    /// Another church's link sermon.
    static let otherLinkSlug = "riverlink1"
    /// The launch-day demo's sermon (only with -uiTestingDemo): the outline
    /// the demo film writes in Church Studio.
    static let demoSlug = "launchday1"

    /// Translation labels as a pastor types them (not app text).
    private static let kjv = "KJV"
    private static let niv = "NIV"

    init(community: CommunityBackend, seeded: Bool = true) {
        self.community = community
        guard seeded else { return }
        listed[Self.sampleChurchID] = "Grace Fellowship"
        listed[Self.otherChurchID] = "Riverside Church"
        locations[Self.sampleChurchID] = [
            ChurchLocation(
                name: "Main Campus", street: "1 Hill Road", city: "Austin", region: "TX", postalCode: "78701",
                country: "United States", address: "1 Hill Road, Austin, TX 78701, United States",
                gatherings: [
                    ChurchGathering(weekday: .sun, time: "09:00"),
                    ChurchGathering(weekday: .sun, time: "11:00"),
                    ChurchGathering(weekday: .wed, time: "19:00", note: "Bible study"),
                ]),
        ]
        let first = Self.sample(
            slug: Self.linkSlug, church: Self.sampleChurchID, churchName: "Grace Fellowship", title: "Rest for the Weary",
            speaker: "Pastor Ruth", series: "Come to Me", day: -7, audience: .link,
            cover: PublishedSermon.Cover(path: "\(Self.sampleChurchID.uuidString.lowercased())/cover.jpg", alt: "A quiet lake at dawn", decorative: false),
            blocks: [
                .paragraph(id: "b1", text: "Jesus calls the tired and the burdened to himself."),
                .heading(id: "b2", text: "Come to me", level: 2),
                .scripture(id: "b3", reference: SermonReference(raw: "Matthew 11:28-30", start: VerseID(rawValue: 40_011_028), end: VerseID(rawValue: 40_011_030), status: .verified, label: Self.kjv, translation: Self.kjv, quoteWithheld: false)),
                .list(id: "b4", items: ["Come as you are", "Take his yoke", "Learn from him"], ordered: false),
                .heading(id: "b5", text: "Rest for your souls", level: 2),
                .scripture(id: "b6", reference: SermonReference(raw: "Rom 8:28", start: VerseID(rawValue: 45_008_028), end: nil, status: .verified, label: Self.niv, translation: nil, quoteWithheld: true)),
                .quote(id: "b7", text: "Our hearts are restless until they rest in you."),
                .scripture(id: "b8", reference: SermonReference(raw: "Jo 99:99", start: nil, end: nil, status: .unlinked, label: nil, translation: nil, quoteWithheld: false)),
            ]
        )
        let second = Self.sample(
            slug: Self.membersSlug, church: Self.sampleChurchID, churchName: "Grace Fellowship", title: "The Good Shepherd",
            speaker: "Pastor Ruth", series: "Come to Me", day: 0, audience: .members, cover: nil,
            blocks: [
                .heading(id: "c1", text: "He knows his sheep", level: 2),
                .scripture(id: "c2", reference: SermonReference(raw: "John 10:11", start: VerseID(rawValue: 43_010_011), end: nil, status: .verified, label: nil, translation: nil, quoteWithheld: false)),
                .paragraph(id: "c3", text: "For members of Grace Fellowship."),
            ]
        )
        let otherMembers = Self.sample(
            slug: Self.otherMembersSlug, church: Self.otherChurchID, churchName: "Riverside Church", title: "Members Night",
            speaker: "Pastor Sam", series: nil, day: -1, audience: .members, cover: nil,
            blocks: [.paragraph(id: "d1", text: "Only for Riverside's members.")]
        )
        let otherLink = Self.sample(
            slug: Self.otherLinkSlug, church: Self.otherChurchID, churchName: "Riverside Church", title: "Living Water",
            speaker: "Pastor Sam", series: nil, day: -3, audience: .link, cover: nil,
            blocks: [
                .heading(id: "e1", text: "The woman at the well", level: 2),
                .scripture(id: "e2", reference: SermonReference(raw: "John 4:14", start: VerseID(rawValue: 43_004_014), end: nil, status: .verified, label: nil, translation: nil, quoteWithheld: false)),
            ]
        )
        for (offset, sermon) in [first, second, otherMembers, otherLink].enumerated() {
            rows[sermon.slug] = Row(sermon: sermon, publishedAt: Date.now.addingTimeInterval(Double(offset - 10) * 3_600))
        }
        if UITestingOptions.current.isDemo {
            let demo = Self.demoSermon
            rows[demo.slug] = Row(sermon: demo, publishedAt: .now)
        }
    }

    /// Every passage is quoted from the KJV, so it shows verbatim from the bundled Bible.
    private static var demoSermon: PublishedSermon {
        func passage(_ id: String, _ raw: String, _ start: Int, _ end: Int?) -> SermonBlock {
            .scripture(id: id, reference: SermonReference(
                raw: raw, start: VerseID(rawValue: start), end: end.map(VerseID.init(rawValue:)), status: .verified,
                label: kjv, translation: kjv, quoteWithheld: false))
        }
        return sample(
            slug: demoSlug, church: sampleChurchID, churchName: "Grace Fellowship", title: "Rest for the Weary",
            speaker: "Pastor Ruth", series: "Come to Me", day: 0, audience: .link, cover: nil,
            blocks: [
                .paragraph(id: "l1", text: "Jesus calls the tired and the burdened to himself."),
                .heading(id: "l2", text: "Come to me", level: 2),
                passage("l3", "Matthew 11:28-30", 40_011_028, 40_011_030),
                .list(id: "l4", items: ["Come as you are", "Take his yoke", "Learn from him"], ordered: false),
                .heading(id: "l5", text: "He restores my soul", level: 2),
                passage("l6", "Psalm 23:1-3", 19_023_001, 19_023_003),
                .quote(id: "l7", text: "Our hearts are restless until they rest in you."),
                .heading(id: "l8", text: "Go in peace", level: 2),
                passage("l9", "John 14:27", 43_014_027, nil),
            ]
        )
    }

    private static func sample(
        slug: String, church: UUID, churchName: String, title: String, speaker: String, series: String?, day: Int,
        audience: ChurchSermonAudience, cover: PublishedSermon.Cover?, blocks: [SermonBlock]
    ) -> PublishedSermon {
        let date = Calendar.current.date(byAdding: .day, value: day, to: .now) ?? .now
        return PublishedSermon(
            id: UUID(), slug: slug, groupID: church, church: churchName, title: title, speaker: speaker, series: series,
            preachedOn: Timestamp.dayString(from: date), location: "Main hall", language: "en", cover: cover,
            audience: audience, blocks: blocks, previous: nil, next: nil, isMember: false
        )
    }

    // MARK: Testing

    func unpublish(_ slug: String) { rows[slug]?.unpublished = true }
    func setSermonsOn(_ on: Bool) { sermonsOn = on }
    func setLocations(_ places: [ChurchLocation], for church: UUID) { locations[church] = places }
    func count(of event: ChurchSermonEvent, slug: String) -> Int { counts[slug]?[event] ?? 0 }

    // MARK: Rules

    private func isMember(of church: UUID) async -> Bool {
        (try? await community.myGroups().contains { $0.id == church }) ?? false
    }

    private func live(_ row: Row) -> Bool { sermonsOn && !row.hidden && !row.unpublished }

    private func canRead(_ row: Row) async -> Bool {
        guard live(row) else { return false }
        if row.sermon.audience == .link { return true }
        return await isMember(of: row.sermon.groupID)
    }

    private func summary(_ row: Row) -> ChurchSermonSummary {
        let s = row.sermon
        return ChurchSermonSummary(slug: s.slug, title: s.title, speaker: s.speaker, series: s.series, preachedOn: s.preachedOn, audience: s.audience)
    }

    /// Readable sermons of the same series, in preaching order.
    private func series(of row: Row) async -> [Row] {
        guard let series = row.sermon.series else { return [] }
        var found: [Row] = []
        for other in rows.values where other.sermon.groupID == row.sermon.groupID && other.sermon.series == series {
            if await canRead(other) { found.append(other) }
        }
        return found.sorted { ($0.sermon.preachedOn ?? "", $0.publishedAt) < ($1.sermon.preachedOn ?? "", $1.publishedAt) }
    }

    // MARK: ChurchSermonBackend

    func sermon(slug: String) async throws -> ChurchSermonLookup {
        guard let row = rows[slug], live(row) else { return .notFound }
        let member = await isMember(of: row.sermon.groupID)
        if row.sermon.audience == .members, !member { return .membersOnly }
        let series = await series(of: row)
        let index = series.firstIndex { $0.sermon.slug == slug }
        let s = row.sermon
        return .sermon(PublishedSermon(
            id: s.id, slug: s.slug, groupID: s.groupID, church: s.church, title: s.title, speaker: s.speaker, series: s.series,
            preachedOn: s.preachedOn, location: s.location, language: s.language, cover: s.cover, audience: s.audience, blocks: s.blocks,
            previous: index.flatMap { $0 > 0 ? summary(series[$0 - 1]) : nil },
            next: index.flatMap { $0 + 1 < series.count ? summary(series[$0 + 1]) : nil },
            isMember: member,
            locations: locations[s.groupID] ?? []
        ))
    }

    func archive(group: UUID) async throws -> [ChurchSermonSummary] {
        guard sermonsOn, listed[group] != nil, await isMember(of: group) else {
            throw CommunityError.message(ChurchSermonError.messages["not_allowed"] ?? "")
        }
        var found: [Row] = []
        for row in rows.values where row.sermon.groupID == group {
            if await canRead(row) { found.append(row) }
        }
        return found.sorted { ($0.sermon.preachedOn ?? "", $0.publishedAt) > ($1.sermon.preachedOn ?? "", $1.publishedAt) }.map(summary)
    }

    func searchChurches(_ query: String) async throws -> [SermonChurch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard sermonsOn, q.count >= 2 else { return [] }
        return listed
            .filter { $0.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
            .map { id, name in
                let sermons = rows.values
                    .filter { $0.sermon.groupID == id && live($0) && $0.sermon.audience == .link }
                    .sorted { $0.publishedAt > $1.publishedAt }
                    .prefix(5)
                    .map(summary)
                return SermonChurch(id: id, name: name, sermons: Array(sermons))
            }
            .sorted { $0.name < $1.name }
    }

    func report(slug: String, reason: String) async throws {
        guard let me = await community.currentUserID() else { throw CommunityError.message(ChurchSermonError.messages["not_signed_in"] ?? "") }
        guard let row = rows[slug], await canRead(row) else { throw CommunityError.message(ChurchSermonError.messages["not_found"] ?? "") }
        reports[slug, default: []].insert(me)
        if reports[slug, default: []].count >= 3 { rows[slug]?.hidden = true }
    }

    func cover(path: String) async throws -> Data? {
        guard let row = rows.values.first(where: { $0.sermon.cover?.path == path }), await canRead(row) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor(red: 0.55, green: 0.62, blue: 0.58, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        }
    }

    func count(_ event: ChurchSermonEvent, slug: String) async {
        guard let row = rows[slug], live(row) else { return }
        counts[slug, default: [:]][event, default: 0] += 1
    }
}
