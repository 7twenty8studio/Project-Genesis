import Testing
@testable import Genesis

@Suite("Pronouncing original words")
struct PronunciationTests {
    @Test("Hebrew keeps letters and vowels, drops accents and punctuation")
    func hebrew() {
        // בְּרֵאשִׁ֖ית with a tipcha (U+0596).
        #expect(PronunciationText.spoken("\u{05D1}\u{05BC}\u{05B0}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05B4}\u{0596}\u{05D9}\u{05EA}", language: .hebrew)
            == "\u{05D1}\u{05BC}\u{05B0}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05B4}\u{05D9}\u{05EA}")
        // A meteg (U+05BD) and sof pasuq (U+05C3) are dropped.
        #expect(PronunciationText.spoken("\u{05D4}\u{05B8}\u{05BD}\u{05D0}\u{05B8}\u{05E8}\u{05B6}\u{05E5}\u{05C3}", language: .hebrew)
            == "\u{05D4}\u{05B8}\u{05D0}\u{05B8}\u{05E8}\u{05B6}\u{05E5}")
        // A maqaf joins two words: they're said as two.
        #expect(PronunciationText.spoken("\u{05DB}\u{05B8}\u{05BC}\u{05DC}\u{05BE}\u{05D4}\u{05B7}", language: .hebrew)
            == "\u{05DB}\u{05B8}\u{05BC}\u{05DC} \u{05D4}\u{05B7}")
        // A paseq set apart is dropped with its space.
        #expect(PronunciationText.spoken("\u{05D0}\u{05B5}\u{05DC} \u{05C0}", language: .hebrew) == "\u{05D0}\u{05B5}\u{05DC}")
    }

    @Test("Greek becomes monotonic without punctuation")
    func greek() {
        #expect(PronunciationText.spoken("Ἐν", language: .greek) == "Εν")
        #expect(PronunciationText.spoken("ἀρχῇ", language: .greek) == "αρχή")
        #expect(PronunciationText.spoken("θεὸν,", language: .greek) == "θεόν")
        #expect(PronunciationText.spoken("ἦν·", language: .greek) == "ήν")
        #expect(PronunciationText.spoken("λόγος.", language: .greek) == "λόγος")
        #expect(PronunciationText.spoken("Ἰησοῦς", language: .greek) == "Ιησούς")
        #expect(PronunciationText.spoken("δι’", language: .greek) == "δι")
    }

    @Test("Nothing to say gives an empty string")
    func empty() {
        #expect(PronunciationText.spoken("", language: .hebrew).isEmpty)
        #expect(PronunciationText.spoken("·", language: .greek).isEmpty)
    }

    @Test("Each language has a speech voice code")
    func voiceLanguages() {
        #expect(OriginalLanguage.hebrew.speechLanguage == "he")
        #expect(OriginalLanguage.greek.speechLanguage == "el")
    }

    @Test("Pronunciation is announced in What's New")
    func announced() {
        let note = WhatsNewCatalog.hearOriginalWords
        #expect(WhatsNewCatalog.all.contains(note))
        #expect(WhatsNewCatalog.all.filter { $0.id == note.id }.count == 1)
        #expect(note.feature == .wordStudy)
    }
}
