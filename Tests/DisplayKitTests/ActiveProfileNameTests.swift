import Foundation
import Testing
@testable import DisplayKit

@Suite struct ActiveProfileNameTests {

    private let STUDIO = "CD233C7A-STUDIO"
    private let DELL1  = "204E366C-DELL1"
    private let DELL2  = "A98DE3E9-DELL2"
    private let BUILTIN = "37D8832A-BUILTIN"
    private let TV     = "6B111247-LGTV"
    private let GHOST  = "1A25C1B7-GHOST"

    private func config() -> AspaceConfig {
        AspaceConfig(
            profiles: [
                "treadmill": .init(disable: [STUDIO, DELL1, DELL2, BUILTIN]),
                "desk":      .init(disable: [TV], main: STUDIO),
            ],
            resolutions: [
                "cozy": [STUDIO: .init(pointWidth: 2560, pointHeight: 1440)],
            ]
        )
    }

    @Test func matchesTreadmillWhenOnlyTVOnline() {
        let name = DisplayKit.activeProfileName(online: [TV], config: config())
        #expect(name == "treadmill")
    }

    @Test func matchesDeskWhenEverythingButTVOnline() {
        let name = DisplayKit.activeProfileName(
            online: [STUDIO, DELL1, DELL2, BUILTIN], config: config()
        )
        #expect(name == "desk")
    }

    @Test func ghostOfflineDisplayDoesNotForceCustom() {
        // The registry "ghost" is offline but not referenced by any profile, so
        // it must be ignored: treadmill (only the TV on) still matches even
        // though GHOST is also offline.
        let name = DisplayKit.activeProfileName(online: [TV], config: config())
        #expect(name == "treadmill", "an unmanaged offline display must not break matching")
    }

    @Test func extraOnlineGhostDoesNotBreakMatch() {
        // A connected display that no profile manages is likewise ignored.
        let name = DisplayKit.activeProfileName(online: [TV, GHOST], config: config())
        #expect(name == "treadmill")
    }

    @Test func allWhenEveryManagedDisplayOnline() {
        let name = DisplayKit.activeProfileName(
            online: [STUDIO, DELL1, DELL2, BUILTIN, TV], config: config()
        )
        #expect(name == AspaceConfig.allProfileName)
    }

    @Test func matchesDeskWithBuiltinOffClamshell() {
        // Desk monitors on, TV and the built-in both off (laptop lid closed):
        // the unmanaged built-in being off must not force "custom" — desk still
        // matches because everything desk disables (the TV) is off.
        let name = DisplayKit.activeProfileName(online: [STUDIO, DELL1, DELL2], config: config())
        #expect(name == "desk")
    }

    @Test func customWhenADisabledDisplayIsStillOn() {
        // A display a profile disables (the TV for desk) is still online, so no
        // profile matches — genuinely custom.
        let name = DisplayKit.activeProfileName(online: [STUDIO, TV], config: config())
        #expect(name == nil)
    }

    @Test func mostSpecificProfileWins() {
        // Two candidates whose disabled sets are both offline: the one that
        // disables more displays is the better explanation.
        let cfg = AspaceConfig(profiles: [
            "one": .init(disable: [TV]),
            "two": .init(disable: [TV, BUILTIN]),
        ])
        // Only TV off -> only "one" qualifies.
        #expect(DisplayKit.activeProfileName(online: [STUDIO, DELL1, DELL2, BUILTIN], config: cfg) == "one")
        // TV and built-in off -> both qualify, "two" is more specific.
        #expect(DisplayKit.activeProfileName(online: [STUDIO, DELL1, DELL2], config: cfg) == "two")
    }

    @Test func nilWhenNoProfilesDefined() {
        let empty = AspaceConfig(profiles: [:])
        #expect(DisplayKit.activeProfileName(online: [TV], config: empty) == nil)
    }

    @Test func matchingIsCaseInsensitive() {
        let name = DisplayKit.activeProfileName(online: [TV.lowercased()], config: config())
        #expect(name == "treadmill")
    }
}
