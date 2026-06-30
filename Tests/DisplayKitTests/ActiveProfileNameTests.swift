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

    @Test func customWhenTopologyMatchesNoProfile() {
        // TV and BUILTIN both off (e.g. laptop lid closed on the desk setup):
        // matches neither desk (expects only TV off) nor treadmill.
        let name = DisplayKit.activeProfileName(online: [STUDIO, DELL1, DELL2], config: config())
        #expect(name == nil)
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
