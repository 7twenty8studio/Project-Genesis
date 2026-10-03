import Foundation
import Testing
@testable import Genesis

@Suite("Ambient sounds")
@MainActor
struct AmbientSoundTests {
    private func makeService() -> (AmbientSoundService, SilentAmbientOutput, UserDefaults) {
        let defaults = UserDefaults(suiteName: "ambient-tests-\(UUID().uuidString)")!
        let output = SilentAmbientOutput()
        return (AmbientSoundService(output: output, defaults: defaults), output, defaults)
    }

    @Test func choosingASoundPlaysIt() {
        let (ambient, output, _) = makeService()
        ambient.toggle(.rain)
        #expect(ambient.isPlaying)
        #expect(ambient.showsControls)
        #expect(output.playing[.rain] == AmbientSound.rain.defaultVolume)

        ambient.toggle(.rain)
        #expect(!ambient.isPlaying, "Taking out the last sound stops playing")
        #expect(output.playing.isEmpty)
    }

    @Test func mixesReplaceTheSounds() throws {
        let (ambient, output, _) = makeService()
        ambient.toggle(.birdsong)
        let fireside = try #require(AmbientMix.all.first { $0.id == "fireside" })
        ambient.choose(fireside)
        #expect(ambient.currentMix == fireside)
        #expect(Set(output.playing.keys) == [.fireplace, .rain])
    }

    @Test func narrationLowersTheSounds() {
        let (ambient, output, _) = makeService()
        ambient.toggle(.waves)
        ambient.setVolume(0.8, for: .waves)
        ambient.setDucked(true)
        #expect(abs((output.playing[.waves] ?? 0) - 0.8 * AmbientSoundService.duckFactor) < 0.001)
        ambient.setDucked(false)
        #expect(output.playing[.waves] == 0.8)
    }

    @Test func theMixIsRemembered() {
        let (ambient, _, defaults) = makeService()
        ambient.toggle(.wind)
        ambient.setVolume(0.3, for: .wind)
        ambient.pause()
        let again = AmbientSoundService(output: SilentAmbientOutput(), defaults: defaults)
        #expect(again.contains(.wind))
        #expect(abs(again.volume(of: .wind) - 0.3) < 0.001)
        #expect(!again.isPlaying, "Nothing plays until asked")
    }

    @Test func pausingClearsTheTimer() {
        let (ambient, _, _) = makeService()
        ambient.toggle(.pad)
        ambient.setTimer(minutes: 30)
        #expect(ambient.timerEndsAt != nil)
        ambient.pause()
        #expect(ambient.timerEndsAt == nil)
    }

    @Test func everySoundIsBundled() {
        for sound in AmbientSound.allCases {
            #expect(sound.url != nil, "ambient-\(sound.rawValue).m4a is in the app")
        }
    }
}
