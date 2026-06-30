import Foundation
import Testing
@testable import DisplayKit

@Suite struct ResolutionStateTests {

    private let STUDIO = "STUDIO-UUID"
    private let DELL1  = "DELL1-UUID"
    private let TV     = "TV-UUID"

    private func resolutions() -> [String: AspaceConfig.ResolutionPreset] {
        [
            "cozy": [
                STUDIO: .init(pointWidth: 2560, pointHeight: 1440),
                DELL1:  .init(pointWidth: 2560, pointHeight: 1440),
            ],
            "spacious": [
                STUDIO: .init(pointWidth: 3200, pointHeight: 1800),
                DELL1:  .init(pointWidth: 3200, pointHeight: 1800),
            ],
            "tv-big": [
                TV: .init(pointWidth: 1920, pointHeight: 1080),
            ],
        ]
    }

    // MARK: - applicablePresets

    @Test func deskPresetsApplicableWhenDeskMonitorsOnline() {
        let applicable = ResolutionState.applicablePresets(
            online: [STUDIO, DELL1], in: resolutions()
        )
        #expect(applicable == ["cozy", "spacious"])
    }

    @Test func tvPresetApplicableOnlyWhenTVOnline() {
        let applicable = ResolutionState.applicablePresets(online: [TV], in: resolutions())
        #expect(applicable == ["tv-big"])
    }

    @Test func presetApplicableIfAnySingleDisplayOnline() {
        // Only one of cozy's two displays is connected — still applicable.
        let applicable = ResolutionState.applicablePresets(online: [DELL1], in: resolutions())
        #expect(applicable.contains("cozy"))
        #expect(applicable.contains("spacious"))
    }

    @Test func noPresetsApplicableWhenNothingOnline() {
        #expect(ResolutionState.applicablePresets(online: [], in: resolutions()).isEmpty)
    }

    @Test func applicabilityIsCaseInsensitive() {
        let applicable = ResolutionState.applicablePresets(
            online: [STUDIO.lowercased()], in: resolutions()
        )
        #expect(applicable.contains("cozy"))
    }

    // MARK: - activePreset

    @Test func detectsActivePresetWhenAllOnlineDisplaysMatch() {
        let current: [String: AspaceConfig.ModeSpec] = [
            STUDIO: .init(pointWidth: 2560, pointHeight: 1440),
            DELL1:  .init(pointWidth: 2560, pointHeight: 1440),
        ]
        #expect(ResolutionState.activePreset(current: current, in: resolutions()) == "cozy")
    }

    @Test func noActivePresetWhenSizesAreMixed() {
        let current: [String: AspaceConfig.ModeSpec] = [
            STUDIO: .init(pointWidth: 2560, pointHeight: 1440),
            DELL1:  .init(pointWidth: 3200, pointHeight: 1800),
        ]
        #expect(ResolutionState.activePreset(current: current, in: resolutions()) == nil)
    }

    @Test func ignoresOfflineDisplaysWhenMatching() {
        // Only STUDIO is connected and it's at the cozy size; cozy still active
        // even though DELL1 (also in the preset) is offline.
        let current: [String: AspaceConfig.ModeSpec] = [
            STUDIO: .init(pointWidth: 2560, pointHeight: 1440),
        ]
        #expect(ResolutionState.activePreset(current: current, in: resolutions()) == "cozy")
    }

    @Test func noActivePresetWhenNoListedDisplayOnline() {
        let current: [String: AspaceConfig.ModeSpec] = [
            "OTHER-UUID": .init(pointWidth: 2560, pointHeight: 1440),
        ]
        #expect(ResolutionState.activePreset(current: current, in: resolutions()) == nil)
    }
}
