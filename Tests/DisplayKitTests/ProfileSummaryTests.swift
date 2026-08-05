import Foundation
import Testing
@testable import DisplayKit

@Suite struct ProfileSummaryTests {

    private let STUDIO = "STUDIO-UUID"
    private let DELL   = "DELL-UUID"
    private let LG_TV  = "LGTV-UUID"

    private func config() -> AspaceConfig {
        AspaceConfig(profiles: [
            "treadmill": .init(disable: [STUDIO, DELL], audioOutput: "LG TV"),
            "desk":      .init(disable: [LG_TV], main: STUDIO, audioOutput: "External Headphones"),
            "quiet":     .init(disable: [LG_TV]),
        ])
    }

    private func rows() -> [DisplayKit.DisplayStatusRow] {
        [
            .init(uuid: STUDIO, name: "Studio Display", connection: .online(isEnabled: true, isMain: true)),
            .init(uuid: DELL, name: "DELL U2723QE", connection: .online(isEnabled: true, isMain: false)),
            .init(uuid: LG_TV, name: "LG TV SSCR2", connection: .offline),
        ]
    }

    @Test func profileMarksKeptAndDisabledDisplays() throws {
        let summary = try #require(ProfileSummary.summarize(profile: "desk", config: config(), displays: rows()))

        #expect(summary.rows.map { $0.uuid } == [STUDIO, DELL, LG_TV], "kept displays listed first")
        #expect(summary.rows.map { $0.enabled } == [true, true, false])
        #expect(summary.audioOutput == "External Headphones")
    }

    @Test func declaredMainIsFlagged() throws {
        let summary = try #require(ProfileSummary.summarize(profile: "desk", config: config(), displays: rows()))
        #expect(summary.rows.first { $0.uuid == STUDIO }?.isMain == true)
        #expect(summary.rows.filter { $0.isMain }.count == 1)
    }

    @Test func soleSurvivorIsFlaggedAsMainWithoutDeclaration() throws {
        let summary = try #require(ProfileSummary.summarize(profile: "treadmill", config: config(), displays: rows()))
        #expect(summary.rows.first?.uuid == LG_TV)
        #expect(summary.rows.first?.isMain == true, "the only display left on reads as main")
        #expect(summary.audioOutput == "LG TV")
    }

    @Test func profileWithoutAudioOutputHasNilAudio() throws {
        let summary = try #require(ProfileSummary.summarize(profile: "quiet", config: config(), displays: rows()))
        #expect(summary.audioOutput == nil)
    }

    @Test func builtInAllEnablesEverythingWithNoAudio() throws {
        let summary = try #require(ProfileSummary.summarize(
            profile: AspaceConfig.allProfileName, config: config(), displays: rows()
        ))
        #expect(summary.rows.allSatisfy { $0.enabled })
        #expect(summary.rows.allSatisfy { !$0.isMain }, "several displays stay on -> no predicted main")
        #expect(summary.audioOutput == nil)
    }

    @Test func unknownProfileReturnsNil() {
        #expect(ProfileSummary.summarize(profile: "nope", config: config(), displays: rows()) == nil)
    }

    @Test func disableMatchingIsCaseInsensitive() throws {
        let cfg = AspaceConfig(profiles: [
            "p": .init(disable: [STUDIO.lowercased()]),
        ])
        let summary = try #require(ProfileSummary.summarize(profile: "p", config: cfg, displays: rows()))
        #expect(summary.rows.first { $0.uuid == STUDIO }?.enabled == false)
    }
}
