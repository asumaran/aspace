import Foundation
import Testing
@testable import DisplayKit

@Suite struct AudioRunnerTests {

    private let tv         = AudioOutputDevice(uid: "TV-UID", name: "LG TV")
    private let headphones = AudioOutputDevice(uid: "HP-UID", name: "External Headphones")
    private let speakers   = AudioOutputDevice(uid: "SP-UID", name: "MacBook Pro Speakers")

    private var allDevices: [AudioOutputDevice] { [tv, headphones, speakers] }

    // MARK: - Matching

    @Test func exactMatchIsCaseInsensitive() {
        #expect(AudioRunner.match(name: "lg tv", in: allDevices) == .found(tv))
        #expect(AudioRunner.match(name: "EXTERNAL HEADPHONES", in: allDevices) == .found(headphones))
    }

    @Test func uniqueSubstringMatches() {
        #expect(AudioRunner.match(name: "headphones", in: allDevices) == .found(headphones))
        #expect(AudioRunner.match(name: "tv", in: allDevices) == .found(tv))
    }

    @Test func ambiguousSubstringIsRejected() {
        let airpods = AudioOutputDevice(uid: "AP-UID", name: "AirPods Pro")
        let airpodsMax = AudioOutputDevice(uid: "APM-UID", name: "AirPods Max")
        let match = AudioRunner.match(name: "airpods", in: allDevices + [airpods, airpodsMax])
        #expect(match == .ambiguous(["AirPods Max", "AirPods Pro"]))
    }

    @Test func exactMatchWinsOverSubstringAmbiguity() {
        // "AirPods Pro" is a substring of nothing else here, but "AirPods"
        // exactly names one device even though it is a substring of two.
        let airpods = AudioOutputDevice(uid: "AP-UID", name: "AirPods")
        let airpodsMax = AudioOutputDevice(uid: "APM-UID", name: "AirPods Max")
        #expect(AudioRunner.match(name: "airpods", in: [airpods, airpodsMax]) == .found(airpods))
    }

    @Test func unknownNameIsNotFound() {
        #expect(AudioRunner.match(name: "Studio Display", in: allDevices) == .notFound)
    }

    // MARK: - Run

    @Test func runSetsMatchedDeviceAsDefault() throws {
        let backend = FakeAudioBackend(devices: allDevices, defaultUID: speakers.uid)
        try AudioRunner.run(deviceNamed: "lg tv", backend: backend, warn: { _ in })
        #expect(backend.setOps == [tv.uid])
        #expect(backend.defaultUID == tv.uid)
    }

    @Test func runSkipsWhenAlreadyDefault() throws {
        let backend = FakeAudioBackend(devices: allDevices, defaultUID: tv.uid)
        try AudioRunner.run(deviceNamed: "LG TV", backend: backend, warn: { _ in })
        #expect(backend.setOps.isEmpty, "no reconfiguration when the device is already default")
    }

    @Test func runWaitsForLateAppearingDevice() throws {
        // The TV's audio device registers with CoreAudio only after a few
        // polls, like a real HDMI link coming up after a profile switch.
        let backend = FakeAudioBackend(devices: [speakers], defaultUID: speakers.uid)
        backend.lateDevices = [(tv, 3)]

        var slept = 0.0
        try AudioRunner.run(
            deviceNamed: "LG TV",
            backend: backend,
            sleep: { slept += $0 },
            warn: { _ in }
        )

        #expect(backend.setOps == [tv.uid])
        #expect(slept > 0, "the runner must have waited for the device")
    }

    @Test func runWarnsAndGivesUpWhenDeviceNeverAppears() throws {
        let backend = FakeAudioBackend(devices: [speakers], defaultUID: speakers.uid)
        var warning: String?
        try AudioRunner.run(
            deviceNamed: "LG TV",
            backend: backend,
            timeout: 2.0,
            sleep: { _ in },
            warn: { warning = $0 }
        )
        #expect(backend.setOps.isEmpty)
        #expect(warning?.contains("not found") == true)
    }

    @Test func runWarnsOnAmbiguousNameWithoutChangingOutput() throws {
        let airpods = AudioOutputDevice(uid: "AP-UID", name: "AirPods Pro")
        let airpodsMax = AudioOutputDevice(uid: "APM-UID", name: "AirPods Max")
        let backend = FakeAudioBackend(devices: [airpods, airpodsMax], defaultUID: airpods.uid)
        var warning: String?
        try AudioRunner.run(
            deviceNamed: "airpods",
            backend: backend,
            sleep: { _ in },
            warn: { warning = $0 }
        )
        #expect(backend.setOps.isEmpty)
        #expect(warning?.contains("ambiguous") == true)
    }

    // MARK: - Profile integration

    private let STUDIO = "STUDIO-UUID"
    private let LG_TV_DISPLAY = "LGTV-UUID"

    private func configWithAudio() -> AspaceConfig {
        AspaceConfig(profiles: [
            "treadmill": .init(disable: [STUDIO], audioOutput: "LG TV"),
            "desk":      .init(disable: [LG_TV_DISPLAY], main: STUDIO, audioOutput: "External Headphones"),
            "mute-less": .init(disable: [LG_TV_DISPLAY], main: STUDIO),
        ])
    }

    @Test func profileSwitchAppliesItsAudioOutput() throws {
        let display = FakeBackend(online: [STUDIO, LG_TV_DISPLAY])
        let audio = FakeAudioBackend(devices: allDevices, defaultUID: headphones.uid)

        try ProfileRunner.run(
            profile: "treadmill",
            config: configWithAudio(),
            backend: display,
            audio: audio
        )

        #expect(audio.setOps == [tv.uid])
    }

    @Test func profileWithoutAudioOutputLeavesAudioUntouched() throws {
        let display = FakeBackend(online: [STUDIO, LG_TV_DISPLAY])
        let audio = FakeAudioBackend(devices: allDevices, defaultUID: tv.uid)

        try ProfileRunner.run(
            profile: "mute-less",
            config: configWithAudio(),
            backend: display,
            audio: audio
        )

        #expect(audio.setOps.isEmpty)
    }

    @Test func missingAudioDeviceWarnsButProfileStillApplies() throws {
        let display = FakeBackend(online: [STUDIO, LG_TV_DISPLAY])
        let audio = FakeAudioBackend(devices: [speakers], defaultUID: speakers.uid)
        var warnings: [String] = []

        try ProfileRunner.run(
            profile: "desk",
            config: configWithAudio(),
            backend: display,
            audio: audio,
            warn: { warnings.append($0) }
        )

        #expect(display.online == [STUDIO], "the topology change must not be affected")
        #expect(audio.setOps.isEmpty)
        #expect(warnings.contains { $0.contains("External Headphones") })
    }

    @Test func audioSetFailureWarnsInsteadOfFailingTheProfile() throws {
        let display = FakeBackend(online: [STUDIO, LG_TV_DISPLAY])
        let audio = FakeAudioBackend(devices: allDevices, defaultUID: headphones.uid)
        audio.setFailures = [tv.uid]
        var warnings: [String] = []

        try ProfileRunner.run(
            profile: "treadmill",
            config: configWithAudio(),
            backend: display,
            audio: audio,
            warn: { warnings.append($0) }
        )

        #expect(display.online == [LG_TV_DISPLAY], "displays switched fine")
        #expect(warnings.contains { $0.contains("LG TV") })
    }

    @Test func planReportsTheProfilesAudioOutput() {
        let display = FakeBackend(online: [STUDIO, LG_TV_DISPLAY])
        let plan = ProfileRunner.plan(profile: "treadmill", config: configWithAudio(), backend: display)
        #expect(plan?.audioOutput == "LG TV")

        let silent = ProfileRunner.plan(profile: "mute-less", config: configWithAudio(), backend: display)
        #expect(silent?.audioOutput == nil)
    }
}
