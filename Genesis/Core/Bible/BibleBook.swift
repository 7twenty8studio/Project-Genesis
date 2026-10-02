import Foundation

enum Testament: String, Codable, Sendable, CaseIterable {
    case old = "OT"
    case new = "NT"

    var title: String {
        switch self {
        case .old: String(localized: "Old Testament")
        case .new: String(localized: "New Testament")
        }
    }
}

/// One of the 66 books of the Protestant canon. Book numbers (1–66) are the
/// stable key shared by every translation database.
struct BibleBook: Identifiable, Hashable, Sendable {
    let id: Int
    let osis: String
    /// The English name ("1 Kings"). Screens use `name`, which follows the
    /// app's language.
    let englishName: String
    let englishAbbreviation: String
    let testament: Testament
    let chapterCount: Int
    /// Extra lowercase spellings accepted by the reference parser.
    let aliases: [String]

    /// The book's name in the app's language: "John" or "Juan".
    var name: String { name(in: AppLanguage.code) }
    var abbreviation: String { abbreviation(in: AppLanguage.code) }

    /// The name in a given language ("en" or "es"); English for others.
    func name(in language: String) -> String {
        language.hasPrefix("es") ? Self.spanish[id - 1].name : englishName
    }

    func abbreviation(in language: String) -> String {
        language.hasPrefix("es") ? Self.spanish[id - 1].abbreviation : englishAbbreviation
    }

    /// Every name and abbreviation in every language, for the reference parser.
    var allNames: [String] {
        [englishName, englishAbbreviation, Self.spanish[id - 1].name, Self.spanish[id - 1].abbreviation]
    }

    var spanishAliases: [String] { Self.spanish[id - 1].aliases }

    static func withNumber(_ number: Int) -> BibleBook {
        all[min(max(number, 1), all.count) - 1]
    }

    static var oldTestament: [BibleBook] { all.filter { $0.testament == .old } }
    static var newTestament: [BibleBook] { all.filter { $0.testament == .new } }

    static let all: [BibleBook] = [
        .init(id: 1, osis: "Gen", englishName: "Genesis", englishAbbreviation: "Gen", testament: .old, chapterCount: 50, aliases: ["ge", "gn"]),
        .init(id: 2, osis: "Exod", englishName: "Exodus", englishAbbreviation: "Exod", testament: .old, chapterCount: 40, aliases: ["ex", "exo"]),
        .init(id: 3, osis: "Lev", englishName: "Leviticus", englishAbbreviation: "Lev", testament: .old, chapterCount: 27, aliases: ["le", "lv"]),
        .init(id: 4, osis: "Num", englishName: "Numbers", englishAbbreviation: "Num", testament: .old, chapterCount: 36, aliases: ["nu", "nm", "nb"]),
        .init(id: 5, osis: "Deut", englishName: "Deuteronomy", englishAbbreviation: "Deut", testament: .old, chapterCount: 34, aliases: ["dt", "de", "deu"]),
        .init(id: 6, osis: "Josh", englishName: "Joshua", englishAbbreviation: "Josh", testament: .old, chapterCount: 24, aliases: ["jos", "jsh"]),
        .init(id: 7, osis: "Judg", englishName: "Judges", englishAbbreviation: "Judg", testament: .old, chapterCount: 21, aliases: ["jdg", "jg", "jdgs"]),
        .init(id: 8, osis: "Ruth", englishName: "Ruth", englishAbbreviation: "Ruth", testament: .old, chapterCount: 4, aliases: ["rth", "ru"]),
        .init(id: 9, osis: "1Sam", englishName: "1 Samuel", englishAbbreviation: "1 Sam", testament: .old, chapterCount: 31, aliases: ["1sa", "1s", "1sm"]),
        .init(id: 10, osis: "2Sam", englishName: "2 Samuel", englishAbbreviation: "2 Sam", testament: .old, chapterCount: 24, aliases: ["2sa", "2s", "2sm"]),
        .init(id: 11, osis: "1Kgs", englishName: "1 Kings", englishAbbreviation: "1 Kgs", testament: .old, chapterCount: 22, aliases: ["1ki", "1k", "1kin"]),
        .init(id: 12, osis: "2Kgs", englishName: "2 Kings", englishAbbreviation: "2 Kgs", testament: .old, chapterCount: 25, aliases: ["2ki", "2k", "2kin"]),
        .init(id: 13, osis: "1Chr", englishName: "1 Chronicles", englishAbbreviation: "1 Chr", testament: .old, chapterCount: 29, aliases: ["1ch", "1chron"]),
        .init(id: 14, osis: "2Chr", englishName: "2 Chronicles", englishAbbreviation: "2 Chr", testament: .old, chapterCount: 36, aliases: ["2ch", "2chron"]),
        .init(id: 15, osis: "Ezra", englishName: "Ezra", englishAbbreviation: "Ezra", testament: .old, chapterCount: 10, aliases: ["ezr"]),
        .init(id: 16, osis: "Neh", englishName: "Nehemiah", englishAbbreviation: "Neh", testament: .old, chapterCount: 13, aliases: ["ne"]),
        .init(id: 17, osis: "Esth", englishName: "Esther", englishAbbreviation: "Esth", testament: .old, chapterCount: 10, aliases: ["est", "es"]),
        .init(id: 18, osis: "Job", englishName: "Job", englishAbbreviation: "Job", testament: .old, chapterCount: 42, aliases: ["jb"]),
        .init(id: 19, osis: "Ps", englishName: "Psalms", englishAbbreviation: "Ps", testament: .old, chapterCount: 150, aliases: ["psalm", "psa", "pss", "psm", "pslm"]),
        .init(id: 20, osis: "Prov", englishName: "Proverbs", englishAbbreviation: "Prov", testament: .old, chapterCount: 31, aliases: ["pr", "prv", "pro"]),
        .init(id: 21, osis: "Eccl", englishName: "Ecclesiastes", englishAbbreviation: "Eccl", testament: .old, chapterCount: 12, aliases: ["ec", "ecc", "qoh", "qoheleth"]),
        .init(id: 22, osis: "Song", englishName: "Song of Solomon", englishAbbreviation: "Song", testament: .old, chapterCount: 8, aliases: ["so", "sos", "song of songs", "canticles", "canticle of canticles"]),
        .init(id: 23, osis: "Isa", englishName: "Isaiah", englishAbbreviation: "Isa", testament: .old, chapterCount: 66, aliases: ["is"]),
        .init(id: 24, osis: "Jer", englishName: "Jeremiah", englishAbbreviation: "Jer", testament: .old, chapterCount: 52, aliases: ["je", "jr"]),
        .init(id: 25, osis: "Lam", englishName: "Lamentations", englishAbbreviation: "Lam", testament: .old, chapterCount: 5, aliases: ["la"]),
        .init(id: 26, osis: "Ezek", englishName: "Ezekiel", englishAbbreviation: "Ezek", testament: .old, chapterCount: 48, aliases: ["eze", "ezk"]),
        .init(id: 27, osis: "Dan", englishName: "Daniel", englishAbbreviation: "Dan", testament: .old, chapterCount: 12, aliases: ["da", "dn"]),
        .init(id: 28, osis: "Hos", englishName: "Hosea", englishAbbreviation: "Hos", testament: .old, chapterCount: 14, aliases: ["ho"]),
        .init(id: 29, osis: "Joel", englishName: "Joel", englishAbbreviation: "Joel", testament: .old, chapterCount: 3, aliases: ["jl"]),
        .init(id: 30, osis: "Amos", englishName: "Amos", englishAbbreviation: "Amos", testament: .old, chapterCount: 9, aliases: ["am"]),
        .init(id: 31, osis: "Obad", englishName: "Obadiah", englishAbbreviation: "Obad", testament: .old, chapterCount: 1, aliases: ["ob", "oba"]),
        .init(id: 32, osis: "Jonah", englishName: "Jonah", englishAbbreviation: "Jonah", testament: .old, chapterCount: 4, aliases: ["jnh", "jon"]),
        .init(id: 33, osis: "Mic", englishName: "Micah", englishAbbreviation: "Mic", testament: .old, chapterCount: 7, aliases: ["mc"]),
        .init(id: 34, osis: "Nah", englishName: "Nahum", englishAbbreviation: "Nah", testament: .old, chapterCount: 3, aliases: ["na"]),
        .init(id: 35, osis: "Hab", englishName: "Habakkuk", englishAbbreviation: "Hab", testament: .old, chapterCount: 3, aliases: ["hb"]),
        .init(id: 36, osis: "Zeph", englishName: "Zephaniah", englishAbbreviation: "Zeph", testament: .old, chapterCount: 3, aliases: ["zep", "zp"]),
        .init(id: 37, osis: "Hag", englishName: "Haggai", englishAbbreviation: "Hag", testament: .old, chapterCount: 2, aliases: ["hg"]),
        .init(id: 38, osis: "Zech", englishName: "Zechariah", englishAbbreviation: "Zech", testament: .old, chapterCount: 14, aliases: ["zec", "zc"]),
        .init(id: 39, osis: "Mal", englishName: "Malachi", englishAbbreviation: "Mal", testament: .old, chapterCount: 4, aliases: ["ml"]),
        .init(id: 40, osis: "Matt", englishName: "Matthew", englishAbbreviation: "Matt", testament: .new, chapterCount: 28, aliases: ["mt", "mat"]),
        .init(id: 41, osis: "Mark", englishName: "Mark", englishAbbreviation: "Mark", testament: .new, chapterCount: 16, aliases: ["mk", "mrk", "mr"]),
        .init(id: 42, osis: "Luke", englishName: "Luke", englishAbbreviation: "Luke", testament: .new, chapterCount: 24, aliases: ["lk", "luk"]),
        .init(id: 43, osis: "John", englishName: "John", englishAbbreviation: "John", testament: .new, chapterCount: 21, aliases: ["jn", "jhn", "joh"]),
        .init(id: 44, osis: "Acts", englishName: "Acts", englishAbbreviation: "Acts", testament: .new, chapterCount: 28, aliases: ["ac", "act", "acts of the apostles"]),
        .init(id: 45, osis: "Rom", englishName: "Romans", englishAbbreviation: "Rom", testament: .new, chapterCount: 16, aliases: ["ro", "rm"]),
        .init(id: 46, osis: "1Cor", englishName: "1 Corinthians", englishAbbreviation: "1 Cor", testament: .new, chapterCount: 16, aliases: ["1co"]),
        .init(id: 47, osis: "2Cor", englishName: "2 Corinthians", englishAbbreviation: "2 Cor", testament: .new, chapterCount: 13, aliases: ["2co"]),
        .init(id: 48, osis: "Gal", englishName: "Galatians", englishAbbreviation: "Gal", testament: .new, chapterCount: 6, aliases: ["ga"]),
        .init(id: 49, osis: "Eph", englishName: "Ephesians", englishAbbreviation: "Eph", testament: .new, chapterCount: 6, aliases: ["ephes"]),
        .init(id: 50, osis: "Phil", englishName: "Philippians", englishAbbreviation: "Phil", testament: .new, chapterCount: 4, aliases: ["php", "pp"]),
        .init(id: 51, osis: "Col", englishName: "Colossians", englishAbbreviation: "Col", testament: .new, chapterCount: 4, aliases: ["co"]),
        .init(id: 52, osis: "1Thess", englishName: "1 Thessalonians", englishAbbreviation: "1 Thess", testament: .new, chapterCount: 5, aliases: ["1th", "1thes"]),
        .init(id: 53, osis: "2Thess", englishName: "2 Thessalonians", englishAbbreviation: "2 Thess", testament: .new, chapterCount: 3, aliases: ["2th", "2thes"]),
        .init(id: 54, osis: "1Tim", englishName: "1 Timothy", englishAbbreviation: "1 Tim", testament: .new, chapterCount: 6, aliases: ["1ti", "1tm"]),
        .init(id: 55, osis: "2Tim", englishName: "2 Timothy", englishAbbreviation: "2 Tim", testament: .new, chapterCount: 4, aliases: ["2ti", "2tm"]),
        .init(id: 56, osis: "Titus", englishName: "Titus", englishAbbreviation: "Titus", testament: .new, chapterCount: 3, aliases: ["tit", "ti"]),
        .init(id: 57, osis: "Phlm", englishName: "Philemon", englishAbbreviation: "Phlm", testament: .new, chapterCount: 1, aliases: ["philem", "phm"]),
        .init(id: 58, osis: "Heb", englishName: "Hebrews", englishAbbreviation: "Heb", testament: .new, chapterCount: 13, aliases: ["he"]),
        .init(id: 59, osis: "Jas", englishName: "James", englishAbbreviation: "Jas", testament: .new, chapterCount: 5, aliases: ["jm", "jam"]),
        .init(id: 60, osis: "1Pet", englishName: "1 Peter", englishAbbreviation: "1 Pet", testament: .new, chapterCount: 5, aliases: ["1pe", "1pt", "1p"]),
        .init(id: 61, osis: "2Pet", englishName: "2 Peter", englishAbbreviation: "2 Pet", testament: .new, chapterCount: 3, aliases: ["2pe", "2pt", "2p"]),
        .init(id: 62, osis: "1John", englishName: "1 John", englishAbbreviation: "1 John", testament: .new, chapterCount: 5, aliases: ["1jn", "1jhn", "1jo"]),
        .init(id: 63, osis: "2John", englishName: "2 John", englishAbbreviation: "2 John", testament: .new, chapterCount: 1, aliases: ["2jn", "2jhn", "2jo"]),
        .init(id: 64, osis: "3John", englishName: "3 John", englishAbbreviation: "3 John", testament: .new, chapterCount: 1, aliases: ["3jn", "3jhn", "3jo"]),
        .init(id: 65, osis: "Jude", englishName: "Jude", englishAbbreviation: "Jude", testament: .new, chapterCount: 1, aliases: ["jud", "jd"]),
        .init(id: 66, osis: "Rev", englishName: "Revelation", englishAbbreviation: "Rev", testament: .new, chapterCount: 22, aliases: ["re", "rv", "revelations", "revelation of john", "apocalypse"]),
    ]

    /// Spanish names and abbreviations, as in the Reina-Valera, in book order.
    struct SpanishName: Sendable {
        let name: String
        let abbreviation: String
        let aliases: [String]
    }

    static let spanish: [SpanishName] = [
        .init(name: "Génesis", abbreviation: "Gn", aliases: ["gen", "gén"]),
        .init(name: "Éxodo", abbreviation: "Éx", aliases: ["exo", "éxo"]),
        .init(name: "Levítico", abbreviation: "Lv", aliases: ["lev"]),
        .init(name: "Números", abbreviation: "Nm", aliases: ["num"]),
        .init(name: "Deuteronomio", abbreviation: "Dt", aliases: ["deut"]),
        .init(name: "Josué", abbreviation: "Jos", aliases: []),
        .init(name: "Jueces", abbreviation: "Jue", aliases: ["jue"]),
        .init(name: "Rut", abbreviation: "Rt", aliases: []),
        .init(name: "1 Samuel", abbreviation: "1 S", aliases: []),
        .init(name: "2 Samuel", abbreviation: "2 S", aliases: []),
        .init(name: "1 Reyes", abbreviation: "1 R", aliases: ["1re", "1rey"]),
        .init(name: "2 Reyes", abbreviation: "2 R", aliases: ["2re", "2rey"]),
        .init(name: "1 Crónicas", abbreviation: "1 Cr", aliases: ["1cro"]),
        .init(name: "2 Crónicas", abbreviation: "2 Cr", aliases: ["2cro"]),
        .init(name: "Esdras", abbreviation: "Esd", aliases: []),
        .init(name: "Nehemías", abbreviation: "Neh", aliases: []),
        .init(name: "Ester", abbreviation: "Est", aliases: []),
        .init(name: "Job", abbreviation: "Job", aliases: []),
        .init(name: "Salmos", abbreviation: "Sal", aliases: ["salmo"]),
        .init(name: "Proverbios", abbreviation: "Pr", aliases: ["prov"]),
        .init(name: "Eclesiastés", abbreviation: "Ec", aliases: ["ecl"]),
        .init(name: "Cantares", abbreviation: "Cnt", aliases: ["cantar de los cantares", "cantar", "cant"]),
        .init(name: "Isaías", abbreviation: "Is", aliases: ["isa"]),
        .init(name: "Jeremías", abbreviation: "Jer", aliases: []),
        .init(name: "Lamentaciones", abbreviation: "Lm", aliases: ["lam"]),
        .init(name: "Ezequiel", abbreviation: "Ez", aliases: ["eze"]),
        .init(name: "Daniel", abbreviation: "Dn", aliases: []),
        .init(name: "Oseas", abbreviation: "Os", aliases: []),
        .init(name: "Joel", abbreviation: "Jl", aliases: []),
        .init(name: "Amós", abbreviation: "Am", aliases: []),
        .init(name: "Abdías", abbreviation: "Abd", aliases: []),
        .init(name: "Jonás", abbreviation: "Jon", aliases: []),
        .init(name: "Miqueas", abbreviation: "Mi", aliases: ["miq"]),
        .init(name: "Nahúm", abbreviation: "Nah", aliases: []),
        .init(name: "Habacuc", abbreviation: "Hab", aliases: []),
        .init(name: "Sofonías", abbreviation: "Sof", aliases: []),
        .init(name: "Hageo", abbreviation: "Hag", aliases: []),
        .init(name: "Zacarías", abbreviation: "Zac", aliases: []),
        .init(name: "Malaquías", abbreviation: "Mal", aliases: []),
        .init(name: "Mateo", abbreviation: "Mt", aliases: ["mat"]),
        .init(name: "Marcos", abbreviation: "Mr", aliases: ["mar"]),
        .init(name: "Lucas", abbreviation: "Lc", aliases: ["luc"]),
        .init(name: "Juan", abbreviation: "Jn", aliases: []),
        .init(name: "Hechos", abbreviation: "Hch", aliases: ["hechos de los apóstoles", "hec"]),
        .init(name: "Romanos", abbreviation: "Ro", aliases: ["rom"]),
        .init(name: "1 Corintios", abbreviation: "1 Co", aliases: ["1cor"]),
        .init(name: "2 Corintios", abbreviation: "2 Co", aliases: ["2cor"]),
        .init(name: "Gálatas", abbreviation: "Gá", aliases: ["gal"]),
        .init(name: "Efesios", abbreviation: "Ef", aliases: ["efe"]),
        .init(name: "Filipenses", abbreviation: "Fil", aliases: []),
        .init(name: "Colosenses", abbreviation: "Col", aliases: []),
        .init(name: "1 Tesalonicenses", abbreviation: "1 Ts", aliases: ["1tes"]),
        .init(name: "2 Tesalonicenses", abbreviation: "2 Ts", aliases: ["2tes"]),
        .init(name: "1 Timoteo", abbreviation: "1 Ti", aliases: ["1tim"]),
        .init(name: "2 Timoteo", abbreviation: "2 Ti", aliases: ["2tim"]),
        .init(name: "Tito", abbreviation: "Tit", aliases: []),
        .init(name: "Filemón", abbreviation: "Flm", aliases: ["file"]),
        .init(name: "Hebreos", abbreviation: "He", aliases: ["heb"]),
        .init(name: "Santiago", abbreviation: "Stg", aliases: ["sant"]),
        .init(name: "1 Pedro", abbreviation: "1 P", aliases: ["1ped"]),
        .init(name: "2 Pedro", abbreviation: "2 P", aliases: ["2ped"]),
        .init(name: "1 Juan", abbreviation: "1 Jn", aliases: []),
        .init(name: "2 Juan", abbreviation: "2 Jn", aliases: []),
        .init(name: "3 Juan", abbreviation: "3 Jn", aliases: []),
        .init(name: "Judas", abbreviation: "Jud", aliases: []),
        .init(name: "Apocalipsis", abbreviation: "Ap", aliases: ["apoc"]),
    ]
}
