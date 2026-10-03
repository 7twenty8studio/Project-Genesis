import Foundation
import Testing
@testable import Genesis

@Suite("Seasonal themes")
struct SeasonalThemeTests {
    private func date(_ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    @Test func northernSeasons() {
        #expect(Season.current(on: date(10), region: "US") == .autumn)
        #expect(Season.current(on: date(1), region: "US") == .winter)
        #expect(Season.current(on: date(12), region: "MX") == .winter)
        #expect(Season.current(on: date(4), region: "GB") == .spring)
        #expect(Season.current(on: date(7), region: "ES") == .summer)
        #expect(Season.current(on: date(7), region: nil) == .summer)
    }

    @Test func southernSeasonsAreFlipped() {
        #expect(Season.current(on: date(10), region: "AR") == .spring)
        #expect(Season.current(on: date(1), region: "AU") == .summer)
        #expect(Season.current(on: date(7), region: "CL") == .winter)
        #expect(Season.current(on: date(4), region: "NZ") == .autumn)
    }

    @Test func seasonsThemeFollowsTheCalendar() {
        let theme = ReaderTheme.seasons.resolved(for: .light, on: date(10))
        // Depends on the test machine's region only for the hemisphere.
        #expect([ReaderTheme.autumn, .spring].contains(theme))
        #expect(ReaderTheme.autumn.resolved(for: .dark) == .autumn)
        #expect(ReaderTheme.autumn.season == .autumn)
        #expect(ReaderTheme.paper.season == nil)
    }

    @Test func seasonalThemesArePremiumOnTexturedPaper() {
        for theme in [ReaderTheme.seasons, .autumn, .winter, .spring, .summer] {
            #expect(theme.isPremium)
            #expect(theme.hasPaperTexture)
            #expect(!theme.isDark)
        }
        #expect(!ReaderTheme.paper.hasPaperTexture)
        #expect(!ReaderTheme.slate.hasPaperTexture)
    }

    @Test func seasonalTouchesDefaultOnForSavedPreferences() throws {
        let saved = #"{"theme":"autumn","fontSize":20}"#
        let preferences = try JSONDecoder().decode(ReaderPreferences.self, from: Data(saved.utf8))
        #expect(preferences.theme == .autumn)
        #expect(preferences.seasonalEffects)
    }
}
