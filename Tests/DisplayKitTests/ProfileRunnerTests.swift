import Foundation
import Testing
@testable import DisplayKit

@Suite struct ProfileRunnerTests {

    private let STUDIO = "STUDIO-UUID"
    private let DELL1  = "DELL1-UUID"
    private let DELL2  = "DELL2-UUID"
    private let LG_TV  = "LGTV-UUID"

    private func standardConfig() -> AspaceConfig {
        AspaceConfig(profiles: [
            "treadmill": .init(disable: [STUDIO, DELL1, DELL2]),
            "desk":      .init(disable: [LG_TV], main: STUDIO),
        ])
    }

    // MARK: - Happy paths

    @Test func treadmillProfileEnablesTVAndDisablesDesk() throws {
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        try ProfileRunner.run(profile: "treadmill", config: standardConfig(), backend: backend)

        #expect(backend.online == [LG_TV])
        #expect(backend.ops.contains(.disable(STUDIO)))
        #expect(backend.ops.contains(.disable(DELL1)))
        #expect(backend.ops.contains(.disable(DELL2)))
        // Even though the profile declares no `main`, the lone surviving display
        // is promoted so its origin is normalized to (0,0).
        #expect(backend.ops.contains(.setMain(LG_TV)),
                "sole surviving display should auto-become main")
    }

    @Test func soleSurvivorBecomesMainEvenWhenSomeTargetsAreOffline() throws {
        // Real-world shape: the profile would enable the TV plus a stale
        // registry "ghost" that is no longer connected, while disabling the
        // desk displays. Only the TV actually comes online, so it must be the
        // one promoted to main.
        let GHOST = "GHOST-UUID"
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV, GHOST]
        )
        backend.enableFailures = [GHOST] // ghost cannot be enabled (not connected)

        try ProfileRunner.run(
            profile: "treadmill",
            config: AspaceConfig(profiles: [
                "treadmill": .init(disable: [STUDIO, DELL1, DELL2]),
            ]),
            backend: backend,
            warn: { _ in }
        )

        #expect(backend.online == [LG_TV])
        #expect(backend.ops.contains(.setMain(LG_TV)))
    }

    @Test func soleSurvivorIsPromotedEvenWhenItLagsComingOnline() throws {
        // The real bug: the TV is enabled but takes a few seconds to report
        // online, so it is absent from listDisplays() right after enabling.
        // The survivor must still be derived from the plan (not listDisplays),
        // and setMain must wait for it — otherwise the lone TV is left without a
        // main (stranded cursor / cropped desktop).
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2],   // TV is OFF at the start
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        backend.lagOnlinePolls = [LG_TV: 3]   // TV appears online only after polling

        var applied = false
        try ProfileRunner.run(
            profile: "treadmill",
            config: standardConfig(),
            backend: backend,
            sleep: { _ in applied = true }    // no real delay; just proves it ran
        )

        #expect(applied)
        #expect(backend.online == [LG_TV], "only the TV should remain enabled")
        #expect(backend.ops.contains(.setMain(LG_TV)),
                "the lagging sole survivor must still be promoted to main")
    }

    @Test func soleSurvivorThatNeverComesOnlineLeavesDisplaysEnabled() throws {
        // If the lone survivor never comes online (TV unplugged / dead HDMI),
        // don't tear down the working displays — a stranded, empty session is
        // worse than not switching.
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        backend.lagOnlinePolls = [LG_TV: 1000]   // never appears within the wait

        var warnings: [String] = []
        try ProfileRunner.run(
            profile: "treadmill",
            config: standardConfig(),
            backend: backend,
            warn: { warnings.append($0) }
        )

        #expect(backend.online == [STUDIO, DELL1, DELL2], "current displays must stay enabled")
        #expect(!backend.ops.contains(where: {
            if case .disable = $0 { return true } else { return false }
        }), "nothing should be disabled when the survivor never arrives")
        #expect(warnings.contains(where: { $0.contains("never came online") }))
    }

    @Test func setMainRetriesThroughTransientFailures() throws {
        // CGCompleteDisplayConfiguration can transiently fail (CGError 1001)
        // while the display system settles; setMain should retry and succeed
        // rather than abort the whole switch.
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        backend.mainFailuresRemaining = [LG_TV: 2]   // fails twice, then succeeds

        try ProfileRunner.run(profile: "treadmill", config: standardConfig(), backend: backend)

        #expect(backend.ops.contains(.setMain(LG_TV)),
                "setMain should succeed after retrying transient failures")
    }

    @Test func soleSurvivorPromotedBeforeItDropsDuringDisable() throws {
        // The real failure mode: disabling the desk monitors briefly knocks the
        // TV offline. Because setMain runs before the disables, it still takes.
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        backend.dropOnDisable = [STUDIO: [LG_TV]]   // disabling Studio drops the TV

        try ProfileRunner.run(profile: "treadmill", config: standardConfig(), backend: backend)

        #expect(backend.ops.contains(.setMain(LG_TV)),
                "the survivor must be promoted before a disable can drop it")
    }

    @Test func noAutoMainWhenMultipleDisplaysSurvive() throws {
        // Disabling only the TV leaves three displays on and no `main` declared,
        // so the runner must not pick one arbitrarily.
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        try ProfileRunner.run(
            profile: "tvoff",
            config: AspaceConfig(profiles: ["tvoff": .init(disable: [LG_TV])]),
            backend: backend
        )

        #expect(backend.online == [STUDIO, DELL1, DELL2])
        #expect(!backend.ops.contains(where: {
            if case .setMain = $0 { return true } else { return false }
        }), "no main should be set when several displays remain")
    }

    @Test func declaredMainWinsOverSoleSurvivor() throws {
        // desk leaves three displays and declares STUDIO as main; the auto-main
        // path must not override an explicit declaration.
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        try ProfileRunner.run(profile: "desk", config: standardConfig(), backend: backend)

        #expect(backend.ops.contains(.setMain(STUDIO)))
        #expect(!backend.ops.contains(.setMain(LG_TV)))
    }

    @Test func soleSurvivorIsPromotedBeforeDisablingOtherDisplays() throws {
        // The lone survivor is set main while it is still online, before the
        // others are torn down: disabling them can briefly knock a TV offline,
        // so promoting first guarantees setMain takes effect.
        let backend = FakeBackend(
            online: [STUDIO, DELL1, DELL2, LG_TV],
            known:  [STUDIO, DELL1, DELL2, LG_TV]
        )
        try ProfileRunner.run(profile: "treadmill", config: standardConfig(), backend: backend)

        let setMain = backend.ops.firstIndex {
            if case .setMain = $0 { return true } else { return false }
        }
        let firstDisable = backend.ops.firstIndex {
            if case .disable = $0 { return true } else { return false }
        }
        #expect(setMain != nil && firstDisable != nil)
        #expect(setMain! < firstDisable!, "sole survivor must be promoted before disabling the others")
    }

    @Test func declaredMainIsSetAfterDisabling() throws {
        // With a declared main (desk), the outgoing display is disabled first
        // (while still main, keeping it warm), then the new main is set.
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        try ProfileRunner.run(profile: "desk", config: standardConfig(), backend: backend)

        let setMain = backend.ops.firstIndex { if case .setMain = $0 { return true } else { return false } }
        let disable = backend.ops.firstIndex { if case .disable = $0 { return true } else { return false } }
        #expect(setMain != nil && disable != nil)
        #expect(disable! < setMain!, "declared main is set after disabling the outgoing display")
    }

    @Test func planPreviewsWithoutMutating() {
        let backend = FakeBackend(online: [STUDIO, DELL1, DELL2], known: [STUDIO, DELL1, DELL2, LG_TV])
        let plan = ProfileRunner.plan(profile: "treadmill", config: standardConfig(), backend: backend)

        #expect(plan?.toDisable.sorted() == [DELL1, DELL2, STUDIO].sorted())
        #expect(plan?.toEnable == [LG_TV])
        #expect(plan?.effectiveMain == LG_TV, "treadmill leaves only the TV -> predicted sole-survivor main")
        #expect(backend.ops.isEmpty, "a dry-run plan must not touch any display")
    }

    @Test func planUsesDeclaredMainAndReportsNothingForUnknownProfile() {
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        let plan = ProfileRunner.plan(profile: "desk", config: standardConfig(), backend: backend)
        #expect(plan?.toDisable == [LG_TV])
        #expect(plan?.effectiveMain == STUDIO)
        #expect(backend.ops.isEmpty)

        #expect(ProfileRunner.plan(profile: "nope", config: standardConfig(), backend: backend) == nil)
    }

    @Test func soleSurvivingDisplayHelper() {
        #expect(ProfileRunner.soleSurvivingDisplay(online: ["A", "B"], toDisable: ["A"]) == "B")
        #expect(ProfileRunner.soleSurvivingDisplay(online: ["A", "B"], toDisable: []) == nil)
        #expect(ProfileRunner.soleSurvivingDisplay(online: ["A"], toDisable: ["A"]) == nil)
        #expect(ProfileRunner.soleSurvivingDisplay(online: [], toDisable: []) == nil)
    }

    @Test func deskProfileSetsMainAndDisablesTV() throws {
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        try ProfileRunner.run(profile: "desk", config: standardConfig(), backend: backend)

        #expect(backend.online == [STUDIO, DELL1, DELL2])
        #expect(backend.ops.contains(.setMain(STUDIO)))
        #expect(backend.ops.contains(.disable(LG_TV)))
    }

    @Test func allProfileEnablesEverythingKnown() throws {
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        try ProfileRunner.run(
            profile: AspaceConfig.allProfileName,
            config: AspaceConfig(profiles: [:]),
            backend: backend
        )
        #expect(backend.online == [STUDIO, DELL1, DELL2, LG_TV])
    }

    // MARK: - Safety net

    @Test func refuseProfileThatWouldDisableEverything() {
        let backend = FakeBackend(online: [STUDIO], known: [STUDIO])
        let config = AspaceConfig(profiles: [
            "kill": .init(disable: [STUDIO]),
        ])

        #expect(throws: ProfileRunner.RunError.self) {
            try ProfileRunner.run(profile: "kill", config: config, backend: backend)
        }
        #expect(backend.ops.isEmpty, "nothing should be mutated when safety net trips")
    }

    @Test func profileNotFoundThrows() {
        let backend = FakeBackend(online: [STUDIO], known: [STUDIO])
        #expect(throws: ProfileRunner.RunError.self) {
            try ProfileRunner.run(
                profile: "nonexistent",
                config: AspaceConfig(profiles: [:]),
                backend: backend
            )
        }
    }

    // MARK: - Skip + warn behavior (non-destructive)

    @Test func cachedOnlyEnableFailureIsSkippedNotPropagated() throws {
        // Studio + DELLs are cached but not online (e.g., user is traveling
        // with only the LG TV connected). Enable will fail in the backend
        // because we mark those UUIDs to fail.
        let backend = FakeBackend(online: [LG_TV], known: [STUDIO, DELL1, DELL2, LG_TV])
        backend.enableFailures = [STUDIO, DELL1, DELL2]

        var warnings: [String] = []
        try ProfileRunner.run(
            profile: "desk",
            config: standardConfig(),
            backend: backend,
            warn: { warnings.append($0) }
        )

        // None of the failing enables should have been recorded as completed.
        #expect(!backend.ops.contains(.enable(STUDIO)))
        let notConnectedWarnings = warnings.filter { $0.contains("not currently connected") }.count
        #expect(notConnectedWarnings == 4, "expected 3 enable warnings + 1 main warning, got \(warnings)")
    }

    @Test func failedSetMainWarnsAndContinues() throws {
        // Studio is cached but enable fails (stale id), so it never comes
        // online; setMain then can't find it and runner should warn instead
        // of throwing.
        let backend = FakeBackend(online: [LG_TV], known: [LG_TV, STUDIO])
        backend.enableFailures = [STUDIO]

        var warnings: [String] = []
        try ProfileRunner.run(
            profile: "desk",
            config: AspaceConfig(profiles: [
                "desk": .init(disable: [LG_TV], main: STUDIO),
            ]),
            backend: backend,
            warn: { warnings.append($0) }
        )

        #expect(warnings.contains(where: { $0.contains("cannot set main") }))
    }

    @Test func liveDisplayEnableFailurePropagates() {
        // Studio is online but enable fails — that's a real bug, not stale
        // cache, so it must throw.
        let backend = FakeBackend(online: [STUDIO, LG_TV], known: [STUDIO, LG_TV])
        backend.enableFailures = [STUDIO]

        #expect(throws: ProfileRunner.RunError.self) {
            try ProfileRunner.run(
                profile: AspaceConfig.allProfileName,
                config: AspaceConfig(profiles: [:]),
                backend: backend
            )
        }
    }
}
