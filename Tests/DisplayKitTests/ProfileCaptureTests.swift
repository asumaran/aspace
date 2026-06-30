import Foundation
import Testing
@testable import DisplayKit

@Suite struct ProfileCaptureTests {

    @Test func profileRecordsMainAndDisabledDisplays() {
        let profile = ProfileCapture.profile(mainUUID: "STUDIO", off: ["TV", "AUX"])
        #expect(profile.main == "STUDIO")
        #expect(profile.disable == ["AUX", "TV"]) // sorted
    }

    @Test func emptyProfileSnapshot() {
        let profile = ProfileCapture.profile(mainUUID: nil, off: [])
        #expect(profile.disable.isEmpty)
        #expect(profile.main == nil)
    }

    @Test func resolutionPresetRecordsEachDisplayMode() {
        let preset = ProfileCapture.resolutionPreset(active: [
            .init(uuid: "STUDIO", mode: .init(pointWidth: 2560, pointHeight: 1440)),
            .init(uuid: "DELL", mode: .init(pointWidth: 3200, pointHeight: 1800)),
        ])
        #expect(preset["STUDIO"] == .init(pointWidth: 2560, pointHeight: 1440))
        #expect(preset["DELL"] == .init(pointWidth: 3200, pointHeight: 1800))
    }

    @Test func emptyResolutionPreset() {
        #expect(ProfileCapture.resolutionPreset(active: []).isEmpty)
    }
}
