import Foundation
import Testing
@testable import Genesis

@Suite("Scripture direction")
struct ScriptureDirectionTests {
    @Test func psalm119StanzaIsMarkedLeftToRight() {
        let text = "נ NUN. Thy word is a lamp unto my feet, and a light unto my path."
        let shown = ScriptureDirection.display(text)
        #expect(shown == "\u{200E}" + text)
        // Only an invisible mark is added: the words are the verse's own.
        #expect(shown.replacingOccurrences(of: "\u{200E}", with: "") == text)
    }

    @Test func everyPoetryLineIsMarked() {
        let shown = ScriptureDirection.display("ב BETH.\nWherewithal shall a young man cleanse his way?")
        #expect(shown == "\u{200E}ב BETH.\n\u{200E}Wherewithal shall a young man cleanse his way?")
    }

    @Test(arguments: [
        "Thy word is a lamp unto my feet, and a light unto my path.",
        "Lámpara es á mis pies tu palabra, Y lumbrera á mi camino.",
        "נֵר־לְרַגְלִי דְבָרֶךָ",
    ])
    func otherTextIsUnchanged(text: String) {
        #expect(ScriptureDirection.display(text) == text)
    }

    @Test func verseDisplayTextKeepsPlainTextForSharing() {
        let verse = Verse(id: VerseID(book: 19, chapter: 119, verse: 105), text: "נ NUN. Thy word is a lamp unto my feet.", startsParagraph: false, isPoetry: true)
        #expect(verse.plainText == "נ NUN. Thy word is a lamp unto my feet.")
        #expect(verse.displayText == "\u{200E}נ NUN. Thy word is a lamp unto my feet.")
    }
}
