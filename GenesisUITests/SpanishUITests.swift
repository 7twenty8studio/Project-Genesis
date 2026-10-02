import XCTest

/// Genesis in Spanish: the screens follow the language chosen for the app.
/// Other tests run in English and find things by English labels; these launch
/// in Spanish and find things by identifier.
final class SpanishUITests: GenesisUITestCase {
    private static let spanish = ["-AppleLanguages", "(es)", "-AppleLocale", "es_MX"]

    @MainActor
    func testScreensAreInSpanish() {
        let app = Genesis.launch(extra: Self.spanish)
        let home = app.buttons["house"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: Genesis.launchTimeout), "The Home tab is there")
        XCTAssertEqual(home.label, "Inicio", "Tab titles are in Spanish")

        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()
        let language = app.buttons["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: Genesis.timeout), "Settings offers the language")
        XCTAssertTrue(language.label.contains("Idioma"), "Settings is in Spanish: \(language.label)")
        XCTAssertTrue(language.label.contains("Español"), "It shows the current language: \(language.label)")
    }
}
