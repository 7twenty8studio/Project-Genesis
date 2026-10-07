import Foundation
import Testing
import UIKit
@testable import Genesis

@MainActor
@Suite("Premium look: illuminated initials, typefaces and icons")
struct PremiumLookTests {
    private func loadChapter(_ id: ChapterID) throws -> Chapter {
        let url = try #require(Bundle.main.url(forResource: Translation.kjv.id, withExtension: "sqlite"))
        return try BibleRepository(translation: .kjv, url: url).chapter(id)
    }

    private func style(_ initial: InitialStyle, font: ReaderFont = .newYork, premium: Bool) -> ReaderStyle {
        var preferences = ReaderPreferences()
        preferences.initialStyle = initial
        preferences.font = font
        return ReaderStyle(preferences: preferences, theme: .paper, contentSizeCategory: .large, allowsPremiumLook: premium)
    }

    private func service(premium: Bool) -> EntitlementService {
        EntitlementService(defaults: UserDefaults(suiteName: "PremiumLookTests-\(UUID())")!, override: premium)
    }

    // MARK: Illuminated initial

    @Test(arguments: [ChapterID(book: 1, chapter: 1), ChapterID(book: 43, chapter: 1), ChapterID(book: 19, chapter: 23)])
    func illuminatedInitialKeepsEveryVerseVerbatim(_ id: ChapterID) throws {
        let chapter = try loadChapter(id)
        let built = ChapterTextBuilder.build(chapter, style: style(.illuminated, premium: true), decorations: ChapterDecorations())
        let text = built.text.string as NSString
        for verse in chapter.verses {
            #expect(built.text.string.contains(verse.text.replacingOccurrences(of: "\n", with: "\u{2028}")))
            let offset = try #require(built.verseOffsets[verse.id])
            #expect(offset < built.text.length)
            let raw = built.text.attribute(.verseID, at: offset, effectiveRange: nil) as? Int
            #expect(raw == verse.id.rawValue, "Each verse offset points into its own verse")
        }

        // The verse opens with the picture, then the verse's own first letter.
        let first = try #require(chapter.verses.first)
        let start = try #require(built.verseOffsets[first.id])
        #expect(text.substring(with: NSRange(location: start, length: 1)) == "\u{FFFC}")
        #expect(built.text.attribute(.attachment, at: start, effectiveRange: nil) is NSTextAttachment)
        let split = try #require(ChapterTextBuilder.initialSplit(first.text.replacingOccurrences(of: "\n", with: "\u{2028}")))
        #expect(text.substring(with: NSRange(location: start + 1, length: (split.initial as NSString).length)) == split.initial)

        // Take the picture away and the text is exactly the classic large initial's.
        let classic = ChapterTextBuilder.build(chapter, style: style(.plain, premium: true), decorations: ChapterDecorations())
        #expect(text.replacingCharacters(in: NSRange(location: start, length: 1), with: "") == classic.text.string)
    }

    @Test func illuminatedInitialPaginatesCleanly() throws {
        let chapter = try loadChapter(ChapterID(book: 1, chapter: 1))
        let built = ChapterTextBuilder.build(chapter, style: style(.illuminated, premium: true), decorations: ChapterDecorations())
        let pages = Paginator.pages(for: built.text, pageSize: CGSize(width: 340, height: 600))
        #expect(pages.first?.location == 0)
        for (previous, next) in zip(pages, pages.dropFirst()) {
            #expect(NSMaxRange(previous) == next.location)
        }
        #expect(pages.last.map(NSMaxRange) == built.text.length)
    }

    @Test func illuminatedInitialIsAboutTwoLinesTall() throws {
        let bodyFont = ReaderFont.newYork.uiFont(size: 19)
        let ornament = try #require(ChapterTextBuilder.illuminatedInitial("I", style: style(.illuminated, premium: true), bodyFont: bodyFont))
        #expect(ornament.image != nil)
        #expect(ornament.bounds.height > bodyFont.lineHeight * 1.5)
        #expect(ornament.bounds.height < bodyFont.lineHeight * 2.5)
    }

    // MARK: Premium fallback

    @Test func initialStyleFallsBackToPlainWithoutPremium() throws {
        #expect(style(.illuminated, premium: false).initialStyle == .plain)
        #expect(style(.illuminated, premium: true).initialStyle == .illuminated)
        #expect(style(.plain, premium: false).initialStyle == .plain)

        let chapter = try loadChapter(ChapterID(book: 1, chapter: 1))
        let built = ChapterTextBuilder.build(chapter, style: style(.illuminated, premium: false), decorations: ChapterDecorations())
        #expect(!built.text.string.contains("\u{FFFC}"), "No illuminated picture without Premium")
    }

    @Test func initialStyleDecodesLeniently() throws {
        let decoder = JSONDecoder()
        let missing = try decoder.decode(ReaderPreferences.self, from: Data(#"{"fontSize": 20}"#.utf8))
        #expect(missing.initialStyle == .plain)
        let unknown = try decoder.decode(ReaderPreferences.self, from: Data(#"{"initialStyle": "gilded"}"#.utf8))
        #expect(unknown.initialStyle == .plain)
        var preferences = ReaderPreferences()
        preferences.initialStyle = .illuminated
        let saved = try decoder.decode(ReaderPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved.initialStyle == .illuminated)
    }

    @Test func premiumTypefacesFallBackWithoutPremium() {
        #expect(style(.plain, font: .spectral, premium: false).font == .newYork)
        #expect(style(.plain, font: .spectral, premium: true).font == .spectral)
        #expect(style(.plain, font: .literata, premium: false).font == .literata, "Free typefaces stay free")
    }

    // MARK: Typefaces

    @Test(arguments: [ReaderFont.crimsonPro, .sourceSerif, .spectral])
    func premiumTypefacesAreBundledAndPremium(_ font: ReaderFont) throws {
        #expect(font.isPremium)
        let faces = try #require(font.bundledFaces)
        for name in [faces.regular, faces.semibold, faces.italic] {
            #expect(UIFont(name: name, size: 17) != nil, "\(name) is registered (UIAppFonts)")
        }
        #expect(font.uiFont(size: 17).fontName == faces.regular)
        #expect(font.uiFont(size: 17, weight: .semibold).fontName == faces.semibold)
        #expect(font.uiFont(size: 17, italic: true).fontName == faces.italic)
        #expect(!service(premium: false).allows(font))
        #expect(service(premium: true).allows(font))
    }

    @Test func freeTypefacesStayFree() {
        let free = service(premium: false)
        for font in ReaderFont.allCases where !font.isPremium {
            #expect(free.allows(font))
        }
        #expect(ReaderFont.allCases.filter(\.isPremium).count == 3)
    }

    // MARK: App icons

    @Test func onlyTheStandardIconIsFree() {
        let free = service(premium: false)
        let premium = service(premium: true)
        for icon in AppIconChoice.allCases {
            #expect(icon.isPremium == (icon != .standard))
            #expect(free.allows(icon: icon) == (icon == .standard))
            #expect(premium.allows(icon: icon))
        }
    }
}
