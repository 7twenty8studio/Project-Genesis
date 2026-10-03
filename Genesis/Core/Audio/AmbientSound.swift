import Foundation

/// A background sound to read and pray with. Each is a seamless loop bundled
/// as `ambient-<id>.m4a` (built by Tools/Ambient/make_ambient.py; credits in
/// AmbientCredits.txt).
enum AmbientSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case rain, waves, wind, fireplace, birdsong, pad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: String(localized: "Rain", comment: "Ambient sound")
        case .waves: String(localized: "Ocean Waves", comment: "Ambient sound")
        case .wind: String(localized: "Wind", comment: "Ambient sound")
        case .fireplace: String(localized: "Fireplace", comment: "Ambient sound")
        case .birdsong: String(localized: "Birdsong", comment: "Ambient sound")
        case .pad: String(localized: "Worship Pad", comment: "Ambient sound: a soft sustained keyboard chord")
        }
    }

    var systemImage: String {
        switch self {
        case .rain: "cloud.rain"
        case .waves: "water.waves"
        case .wind: "wind"
        case .fireplace: "flame"
        case .birdsong: "bird"
        case .pad: "music.note"
        }
    }

    /// The loop's exact length; anything an encoder padded after it is skipped.
    var loopSeconds: Double {
        switch self {
        case .rain: 90
        case .waves: 96
        case .wind: 100
        case .fireplace: 120
        case .birdsong: 180
        case .pad: 120
        }
    }

    /// A comfortable starting volume (0...1).
    var defaultVolume: Float {
        switch self {
        case .rain, .waves, .fireplace: 0.8
        case .wind, .birdsong: 0.6
        case .pad: 0.7
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: "ambient-\(rawValue)", withExtension: "m4a")
    }
}

/// A ready-made blend of sounds.
struct AmbientMix: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let volumes: [AmbientSound: Float]

    static let all: [AmbientMix] = [
        AmbientMix(id: "quiet-rain", title: String(localized: "Quiet Rain", comment: "Ambient mix"), systemImage: "cloud.rain", volumes: [.rain: 0.8]),
        AmbientMix(id: "fireside", title: String(localized: "Fireside", comment: "Ambient mix: fire with rain outside"), systemImage: "flame", volumes: [.fireplace: 0.85, .rain: 0.35]),
        AmbientMix(id: "garden", title: String(localized: "Morning Garden", comment: "Ambient mix"), systemImage: "sun.horizon", volumes: [.birdsong: 0.65, .wind: 0.3]),
        AmbientMix(id: "seaside", title: String(localized: "Seaside", comment: "Ambient mix"), systemImage: "water.waves", volumes: [.waves: 0.8, .wind: 0.25]),
        AmbientMix(id: "sanctuary", title: String(localized: "Sanctuary", comment: "Ambient mix: worship pad with soft rain"), systemImage: "building.columns", volumes: [.pad: 0.7, .rain: 0.25]),
    ]
}
