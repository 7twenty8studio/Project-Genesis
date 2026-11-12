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
        // Laid out at the body size (so the line keeps its height) and drawn large.
        let initialFont = try #require(built.text.attribute(.font, at: start, effectiveRange: nil) as? UIFont)
        let bodyFont = try #require(built.text.attribute(.font, at: start + 1, effectiveRange: nil) as? UIFont)
        #expect(initialFont.pointSize == bodyFont.pointSize)
        #expect(built.text.attribute(.largeInitial, at: start, effectiveRange: nil) is LargeInitialMark)
        let room = try #require(built.text.attribute(.kern, at: start, effectiveRange: nil) as? CGFloat)
        #expect(room > 0, "Room after the letter for its large size")

        var plain = ReaderPreferences()
        plain.largeInitial = false
        let without = ChapterTextBuilder.build(genesis, style: ReaderStyle(preferences: plain, theme: .paper, contentSizeCategory: .large), decorations: ChapterDecorations())
        let plainStart = try #require(without.verseOffsets[first.id])
        #expect((without.text.string as NSString).substring(with: NSRange(location: plainStart, length: 1)) == "1", "Turned off, verse 1 is numbered as before")
    }

    @Test func everyLineOfScriptureIsTheSameHeight() throws {
        // A highlight, the large first letter, verse numbers and footnote
        // markers never change a line's height: verse paragraphs fix it.
        let genesis = try chapter(ChapterID(book: 1, chapter: 1))
        let first = try #require(genesis.verses.first)
        var decorations = ChapterDecorations()
        decorations.highlights[first.id] = .yellow
        let built = ChapterTextBuilder.build(genesis, style: style, decorations: decorations)
        var heights: Set<CGFloat> = []
        for verse in genesis.verses {
            let offset = try #require(built.verseOffsets[verse.id])
            let paragraph = try #require(built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
            #expect(paragraph.minimumLineHeight > 0 && paragraph.minimumLineHeight == paragraph.maximumLineHeight)
            heights.insert(paragraph.minimumLineHeight)
        }
        #expect(heights.count == 1, "Every verse uses the same line height")

        // The large first letter's room comes before the paragraph, not between its lines.
        let start = try #require(built.verseOffsets[first.id])
        let opening = try #require(built.text.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle)
        var plain = ReaderPreferences()
        plain.largeInitial = false
        let without = ChapterTextBuilder.build(genesis, style: ReaderStyle(preferences: plain, theme: .paper, contentSizeCategory: .large), decorations: decorations)
        let plainStart = try #require(without.verseOffsets[first.id])
        let plainOpening = try #require(without.text.attribute(.paragraphStyle, at: plainStart, effectiveRange: nil) as? NSParagraphStyle)
        #expect(opening.paragraphSpacingBefore > plainOpening.paragraphSpacingBefore)
        #expect(opening.minimumLineHeight == plainOpening.minimumLineHeight)
        #expect(built.text.attribute(.largeInitial, at: start, effectiveRange: nil) != nil)
    }

    @Test func largeInitialMetrics() {
        #expect(LargeInitialMetrics.rise(of: "T", capHeight: 30, ascender: 40) == 30)
        #expect(LargeInitialMetrics.rise(of: "\u{201C}C", capHeight: 30, ascender: 40) == 30)
        #expect(LargeInitialMetrics.rise(of: "É", capHeight: 30, ascender: 40) == 40, "An accent reaches above the cap height")
        // A line 24 pt tall with a 5 pt descender holds 19 pt above its baseline.
        #expect(LargeInitialMetrics.roomAbove(rise: 10, lineHeight: 24, bodyDescender: -5, fontSize: 19) == 0)
        #expect(LargeInitialMetrics.roomAbove(rise: 40, lineHeight: 24, bodyDescender: -5, fontSize: 19) == (40 + 3.8 - 19).rounded(.up))
    }

    @Test func pageTurnVolumePicksOneOfFiveLevels() {
        #expect(PageTurnFeedback.level(forVolume: 0) == 1)
        #expect(PageTurnFeedback.level(forVolume: 0.25) == 2)
        #expect(PageTurnFeedback.level(forVolume: 0.5) == 3, "The default is the middle level")
        #expect(PageTurnFeedback.level(forVolume: 1) == 5)
        #expect(PageTurnFeedback.level(forVolume: 7) == 5)
        for level in 1...PageTurnFeedback.levels {
            #expect(Bundle.main.url(forResource: "page-turn-\(level)", withExtension: "caf") != nil, "Level \(level) is bundled")
        }
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
