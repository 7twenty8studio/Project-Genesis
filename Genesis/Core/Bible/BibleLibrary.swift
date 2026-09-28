import Foundation
import Observation

/// Owns the offline Bible databases and the reader's chosen translation.
///
/// Bundled translations ship inside the app. Downloaded translations (a later
/// phase) will live in Application Support/Bibles and are looked up first, so
/// an updated download can replace a bundled edition.
@MainActor
@Observable
final class BibleLibrary {
    private(set) var translations: [Translation] = Translation.bundled

    var currentTranslation: Translation {
        didSet { defaults.set(currentTranslation.id, forKey: Self.translationKey) }
    }

    @ObservationIgnored private var repositories: [String: BibleRepository] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundle: Bundle
    /// Nil only if the bundled cross-reference database is missing.
    @ObservationIgnored let crossReferences: CrossReferenceRepository?

    private static let translationKey = "library.currentTranslation"

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        let savedID = defaults.string(forKey: Self.translationKey)
        currentTranslation = Translation.bundled.first { $0.id == savedID } ?? .kjv
        crossReferences = bundle.url(forResource: "CrossReferences", withExtension: "sqlite")
            .flatMap { try? CrossReferenceRepository(url: $0) }
    }

    /// True once the person has picked a translation during onboarding.
    var hasChosenTranslation: Bool {
        defaults.string(forKey: Self.translationKey) != nil
    }

    var current: BibleRepository { repository(for: currentTranslation) }

    func repository(for translation: Translation) -> BibleRepository {
        if let cached = repositories[translation.id] { return cached }
        guard let url = databaseURL(for: translation) else {
            preconditionFailure("\(translation.id).sqlite is missing from the app bundle.")
        }
        do {
            let repository = try BibleRepository(translation: translation, url: url)
            repositories[translation.id] = repository
            return repository
        } catch {
            preconditionFailure("Could not open \(translation.id): \(error)")
        }
    }

    /// Where a translation's database lives: a download if present, else the bundle.
    func databaseURL(for translation: Translation) -> URL? {
        let downloaded = Self.downloadsDirectory.appending(path: "\(translation.id).sqlite")
        if FileManager.default.fileExists(atPath: downloaded.path(percentEncoded: false)) {
            return downloaded
        }
        return bundle.url(forResource: translation.id, withExtension: "sqlite")
    }

    func isAvailableOffline(_ translation: Translation) -> Bool {
        databaseURL(for: translation) != nil
    }

    nonisolated static var downloadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Bibles", directoryHint: .isDirectory)
    }
}
