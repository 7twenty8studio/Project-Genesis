import Foundation
import Testing
import UIKit
@testable import Genesis

@MainActor
@Suite("Reader rendering")
struct ReaderRenderingTests {
    private func chapter(_ id: ChapterID, translation: Translation = .kjv) throws -> Chapter {
        let url = try #require(Bundle.main.url(forResource: translation.id, withExtension: "sqlite"))
        return try BibleRepository(translation: translation, url: url).chapter(id)
    }

    private var style: ReaderStyle {
        ReaderStyle(preferences: ReaderPreferences(), theme: .paper, contentSizeCategory: .large)
    }

    @Test func everyVerseAppearsVerbatim() throws {
        let chapter = try chapter(ChapterID(book: 43, chapter: 1))
        let built = ChapterTextBuilder.build(chapter, style: style, decorations: ChapterDecorations())
        let text = built.text.string
        for verse in chapter.verses {
            #expect(text.contains(verse.text.replacingOccurrences(of: "\n", with: "\u{2028}")))
            #expect(built.verseOffsets[verse.id] != nil)
        }
    }

    @Test func largeInitialOnlyRestylesTheFirstLetter() throws {
        let plainSplit = try #require(ChapterTextBuilder.initialSplit("In the beginning"))
        #expect(plainSplit.initial == "I" && plainSplit.rest == "n the beginning")
        let quoted = try #require(ChapterTextBuilder.initialSplit("\u{201C}Comfort ye"))
        #expect(quoted.initial == "\u{201C}C" && quoted.rest == "omfort ye", "An opening quotation mark stays with the letter")
        #expect(ChapterTextBuilder.initialSplit("…") == nil)

        let genesis = try chapter(ChapterID(book: 1, chapter: 1))
        let built = ChapterTextBuilder.build(genesis, style: style, decorations: ChapterDecorations())
        let first = try #require(genesis.verses.first)
        let start = try #require(built.verseOffsets[first.id])
        // No "1" before the first verse: the large initial opens the chapter.
        #expect((built.text.string as NSString).substring(with: NSRange(location: start, length: 1)) == "I")
        let initialFont = try #require(built.text.attribute(.font, at: start, effectiveRange: nil) as? UIFont)
        let bodyFont = try #require(built.text.attribute(.font, at: start + 1, effectiveRange: nil) as? UIFont)
        #expect(initialFont.pointSize > bodyFont.pointSize * 2)

        var plain = ReaderPreferences()
        plain.largeInitial = false
        let without = ChapterTextBuilder.build(genesis, style: ReaderStyle(preferences: plain, theme: .paper, contentSizeCategory: .large), decorations: ChapterDecorations())
        let plainStart = try #require(without.verseOffsets[first.id])
        #expect((without.text.string as NSString).substring(with: NSRange(location: plainStart, length: 1)) == "1", "Turned off, verse 1 is numbered as before")
    }

    @Test func pagesCoverTextExactlyOnce() throws {
        let chapter = try chapter(ChapterID(book: 19, chapter: 119), translation: .web)
        let built = ChapterTextBuilder.build(chapter, style: style, decorations: ChapterDecorations())
        let pages = Paginator.pages(for: built.text, pageSize: CGSize(width: 340, height: 600))
        #expect(pages.count > 5)
        #expect(pages.first?.location == 0)
        for (previous, next) in zip(pages, pages.dropFirst()) {
            #expect(NSMaxRange(previous) == next.location)
        }
        #expect(pages.last.map(NSMaxRange) == built.text.length)
    }

    @Test func pageLookupFindsVerse() throws {
        let chapter = try chapter(ChapterID(book: 19, chapter: 119))
        let built = ChapterTextBuilder.build(chapter, style: style, decorations: ChapterDecorations())
        let paginated = PaginatedChapter(built: built, pages: Paginator.pages(for: built.text, pageSize: CGSize(width: 340, height: 600)))
        let verse = VerseID(book: 19, chapter: 119, verse: 105)
        let page = paginated.pageIndex(containing: verse)
        #expect(page > 0)
        #expect(NSLocationInRange(built.verseOffsets[verse]!, paginated.pages[page]))
    }

    @Test func shareTextIncludesReference() throws {
        let chapter = try chapter(ChapterID(book: 43, chapter: 11))
        let match = chapter.verses.first { $0.id.verse == 35 }
        let verse = try #require(match)
        let text = ChapterTextBuilder.shareText(for: [verse], translation: .kjv)
        #expect(text == "\u{201C}Jesus wept.\u{201D}\n\u{2014} John 11:35 (KJV)")
    }
}
