import Testing
@testable import Kaset

@MainActor
struct AmbientBackdropStrengthTests {
    @Test("Strength is clamped to the slider range")
    func clampsToRange() {
        let range = SettingsManager.ambientBackdropStrengthRange
        #expect(SettingsManager.clampAmbientBackdropStrength(-3) == range.lowerBound)
        #expect(SettingsManager.clampAmbientBackdropStrength(99) == range.upperBound)
        #expect(SettingsManager.clampAmbientBackdropStrength(1.25) == 1.25)
    }

    @Test("Non-finite strength falls back to the default")
    func nonFiniteFallsBackToDefault() {
        #expect(SettingsManager.clampAmbientBackdropStrength(.nan) == SettingsManager.ambientBackdropStrengthDefault)
        #expect(SettingsManager.clampAmbientBackdropStrength(.infinity) == SettingsManager.ambientBackdropStrengthDefault)
    }
}
