import Foundation

enum Testament: String, Codable, Sendable, CaseIterable {
    case old = "OT"
    case new = "NT"

    var title: String {
        switch self {
        case .old: "Old Testament"
        case .new: "New Testament"
        }
    }
}

/// One of the 66 books of the Protestant canon. Book numbers (1–66) are the
/// stable key shared by every translation database.
struct BibleBook: Identifiable, Hashable, Sendable {
    let id: Int
    let osis: String
    let name: String
    let abbreviation: String
    let testament: Testament
    let chapterCount: Int
    /// Extra lowercase spellings accepted by the reference parser.
    let aliases: [String]

    static func withNumber(_ number: Int) -> BibleBook {
        all[min(max(number, 1), all.count) - 1]
    }

    static var oldTestament: [BibleBook] { all.filter { $0.testament == .old } }
    static var newTestament: [BibleBook] { all.filter { $0.testament == .new } }

    static let all: [BibleBook] = [
        .init(id: 1, osis: "Gen", name: "Genesis", abbreviation: "Gen", testament: .old, chapterCount: 50, aliases: ["ge", "gn"]),
        .init(id: 2, osis: "Exod", name: "Exodus", abbreviation: "Exod", testament: .old, chapterCount: 40, aliases: ["ex", "exo"]),
        .init(id: 3, osis: "Lev", name: "Leviticus", abbreviation: "Lev", testament: .old, chapterCount: 27, aliases: ["le", "lv"]),
        .init(id: 4, osis: "Num", name: "Numbers", abbreviation: "Num", testament: .old, chapterCount: 36, aliases: ["nu", "nm", "nb"]),
        .init(id: 5, osis: "Deut", name: "Deuteronomy", abbreviation: "Deut", testament: .old, chapterCount: 34, aliases: ["dt", "de", "deu"]),
        .init(id: 6, osis: "Josh", name: "Joshua", abbreviation: "Josh", testament: .old, chapterCount: 24, aliases: ["jos", "jsh"]),
        .init(id: 7, osis: "Judg", name: "Judges", abbreviation: "Judg", testament: .old, chapterCount: 21, aliases: ["jdg", "jg", "jdgs"]),
        .init(id: 8, osis: "Ruth", name: "Ruth", abbreviation: "Ruth", testament: .old, chapterCount: 4, aliases: ["rth", "ru"]),
        .init(id: 9, osis: "1Sam", name: "1 Samuel", abbreviation: "1 Sam", testament: .old, chapterCount: 31, aliases: ["1sa", "1s", "1sm"]),
        .init(id: 10, osis: "2Sam", name: "2 Samuel", abbreviation: "2 Sam", testament: .old, chapterCount: 24, aliases: ["2sa", "2s", "2sm"]),
        .init(id: 11, osis: "1Kgs", name: "1 Kings", abbreviation: "1 Kgs", testament: .old, chapterCount: 22, aliases: ["1ki", "1k", "1kin"]),
        .init(id: 12, osis: "2Kgs", name: "2 Kings", abbreviation: "2 Kgs", testament: .old, chapterCount: 25, aliases: ["2ki", "2k", "2kin"]),
        .init(id: 13, osis: "1Chr", name: "1 Chronicles", abbreviation: "1 Chr", testament: .old, chapterCount: 29, aliases: ["1ch", "1chron"]),
        .init(id: 14, osis: "2Chr", name: "2 Chronicles", abbreviation: "2 Chr", testament: .old, chapterCount: 36, aliases: ["2ch", "2chron"]),
        .init(id: 15, osis: "Ezra", name: "Ezra", abbreviation: "Ezra", testament: .old, chapterCount: 10, aliases: ["ezr"]),
        .init(id: 16, osis: "Neh", name: "Nehemiah", abbreviation: "Neh", testament: .old, chapterCount: 13, aliases: ["ne"]),
        .init(id: 17, osis: "Esth", name: "Esther", abbreviation: "Esth", testament: .old, chapterCount: 10, aliases: ["est", "es"]),
        .init(id: 18, osis: "Job", name: "Job", abbreviation: "Job", testament: .old, chapterCount: 42, aliases: ["jb"]),
        .init(id: 19, osis: "Ps", name: "Psalms", abbreviation: "Ps", testament: .old, chapterCount: 150, aliases: ["psalm", "psa", "pss", "psm", "pslm"]),
        .init(id: 20, osis: "Prov", name: "Proverbs", abbreviation: "Prov", testament: .old, chapterCount: 31, aliases: ["pr", "prv", "pro"]),
        .init(id: 21, osis: "Eccl", name: "Ecclesiastes", abbreviation: "Eccl", testament: .old, chapterCount: 12, aliases: ["ec", "ecc", "qoh", "qoheleth"]),
        .init(id: 22, osis: "Song", name: "Song of Solomon", abbreviation: "Song", testament: .old, chapterCount: 8, aliases: ["so", "sos", "song of songs", "canticles", "canticle of canticles"]),
        .init(id: 23, osis: "Isa", name: "Isaiah", abbreviation: "Isa", testament: .old, chapterCount: 66, aliases: ["is"]),
        .init(id: 24, osis: "Jer", name: "Jeremiah", abbreviation: "Jer", testament: .old, chapterCount: 52, aliases: ["je", "jr"]),
        .init(id: 25, osis: "Lam", name: "Lamentations", abbreviation: "Lam", testament: .old, chapterCount: 5, aliases: ["la"]),
        .init(id: 26, osis: "Ezek", name: "Ezekiel", abbreviation: "Ezek", testament: .old, chapterCount: 48, aliases: ["eze", "ezk"]),
        .init(id: 27, osis: "Dan", name: "Daniel", abbreviation: "Dan", testament: .old, chapterCount: 12, aliases: ["da", "dn"]),
        .init(id: 28, osis: "Hos", name: "Hosea", abbreviation: "Hos", testament: .old, chapterCount: 14, aliases: ["ho"]),
        .init(id: 29, osis: "Joel", name: "Joel", abbreviation: "Joel", testament: .old, chapterCount: 3, aliases: ["jl"]),
        .init(id: 30, osis: "Amos", name: "Amos", abbreviation: "Amos", testament: .old, chapterCount: 9, aliases: ["am"]),
        .init(id: 31, osis: "Obad", name: "Obadiah", abbreviation: "Obad", testament: .old, chapterCount: 1, aliases: ["ob", "oba"]),
        .init(id: 32, osis: "Jonah", name: "Jonah", abbreviation: "Jonah", testament: .old, chapterCount: 4, aliases: ["jnh", "jon"]),
        .init(id: 33, osis: "Mic", name: "Micah", abbreviation: "Mic", testament: .old, chapterCount: 7, aliases: ["mc"]),
        .init(id: 34, osis: "Nah", name: "Nahum", abbreviation: "Nah", testament: .old, chapterCount: 3, aliases: ["na"]),
        .init(id: 35, osis: "Hab", name: "Habakkuk", abbreviation: "Hab", testament: .old, chapterCount: 3, aliases: ["hb"]),
        .init(id: 36, osis: "Zeph", name: "Zephaniah", abbreviation: "Zeph", testament: .old, chapterCount: 3, aliases: ["zep", "zp"]),
        .init(id: 37, osis: "Hag", name: "Haggai", abbreviation: "Hag", testament: .old, chapterCount: 2, aliases: ["hg"]),
        .init(id: 38, osis: "Zech", name: "Zechariah", abbreviation: "Zech", testament: .old, chapterCount: 14, aliases: ["zec", "zc"]),
        .init(id: 39, osis: "Mal", name: "Malachi", abbreviation: "Mal", testament: .old, chapterCount: 4, aliases: ["ml"]),
        .init(id: 40, osis: "Matt", name: "Matthew", abbreviation: "Matt", testament: .new, chapterCount: 28, aliases: ["mt", "mat"]),
        .init(id: 41, osis: "Mark", name: "Mark", abbreviation: "Mark", testament: .new, chapterCount: 16, aliases: ["mk", "mrk", "mr"]),
        .init(id: 42, osis: "Luke", name: "Luke", abbreviation: "Luke", testament: .new, chapterCount: 24, aliases: ["lk", "luk"]),
        .init(id: 43, osis: "John", name: "John", abbreviation: "John", testament: .new, chapterCount: 21, aliases: ["jn", "jhn", "joh"]),
        .init(id: 44, osis: "Acts", name: "Acts", abbreviation: "Acts", testament: .new, chapterCount: 28, aliases: ["ac", "act", "acts of the apostles"]),
        .init(id: 45, osis: "Rom", name: "Romans", abbreviation: "Rom", testament: .new, chapterCount: 16, aliases: ["ro", "rm"]),
        .init(id: 46, osis: "1Cor", name: "1 Corinthians", abbreviation: "1 Cor", testament: .new, chapterCount: 16, aliases: ["1co"]),
        .init(id: 47, osis: "2Cor", name: "2 Corinthians", abbreviation: "2 Cor", testament: .new, chapterCount: 13, aliases: ["2co"]),
        .init(id: 48, osis: "Gal", name: "Galatians", abbreviation: "Gal", testament: .new, chapterCount: 6, aliases: ["ga"]),
        .init(id: 49, osis: "Eph", name: "Ephesians", abbreviation: "Eph", testament: .new, chapterCount: 6, aliases: ["ephes"]),
        .init(id: 50, osis: "Phil", name: "Philippians", abbreviation: "Phil", testament: .new, chapterCount: 4, aliases: ["php", "pp"]),
        .init(id: 51, osis: "Col", name: "Colossians", abbreviation: "Col", testament: .new, chapterCount: 4, aliases: ["co"]),
        .init(id: 52, osis: "1Thess", name: "1 Thessalonians", abbreviation: "1 Thess", testament: .new, chapterCount: 5, aliases: ["1th", "1thes"]),
        .init(id: 53, osis: "2Thess", name: "2 Thessalonians", abbreviation: "2 Thess", testament: .new, chapterCount: 3, aliases: ["2th", "2thes"]),
        .init(id: 54, osis: "1Tim", name: "1 Timothy", abbreviation: "1 Tim", testament: .new, chapterCount: 6, aliases: ["1ti", "1tm"]),
        .init(id: 55, osis: "2Tim", name: "2 Timothy", abbreviation: "2 Tim", testament: .new, chapterCount: 4, aliases: ["2ti", "2tm"]),
        .init(id: 56, osis: "Titus", name: "Titus", abbreviation: "Titus", testament: .new, chapterCount: 3, aliases: ["tit", "ti"]),
        .init(id: 57, osis: "Phlm", name: "Philemon", abbreviation: "Phlm", testament: .new, chapterCount: 1, aliases: ["philem", "phm"]),
        .init(id: 58, osis: "Heb", name: "Hebrews", abbreviation: "Heb", testament: .new, chapterCount: 13, aliases: ["he"]),
        .init(id: 59, osis: "Jas", name: "James", abbreviation: "Jas", testament: .new, chapterCount: 5, aliases: ["jm", "jam"]),
        .init(id: 60, osis: "1Pet", name: "1 Peter", abbreviation: "1 Pet", testament: .new, chapterCount: 5, aliases: ["1pe", "1pt", "1p"]),
        .init(id: 61, osis: "2Pet", name: "2 Peter", abbreviation: "2 Pet", testament: .new, chapterCount: 3, aliases: ["2pe", "2pt", "2p"]),
        .init(id: 62, osis: "1John", name: "1 John", abbreviation: "1 John", testament: .new, chapterCount: 5, aliases: ["1jn", "1jhn", "1jo"]),
        .init(id: 63, osis: "2John", name: "2 John", abbreviation: "2 John", testament: .new, chapterCount: 1, aliases: ["2jn", "2jhn", "2jo"]),
        .init(id: 64, osis: "3John", name: "3 John", abbreviation: "3 John", testament: .new, chapterCount: 1, aliases: ["3jn", "3jhn", "3jo"]),
        .init(id: 65, osis: "Jude", name: "Jude", abbreviation: "Jude", testament: .new, chapterCount: 1, aliases: ["jud", "jd"]),
        .init(id: 66, osis: "Rev", name: "Revelation", abbreviation: "Rev", testament: .new, chapterCount: 22, aliases: ["re", "rv", "revelations", "revelation of john", "apocalypse"]),
    ]
}
