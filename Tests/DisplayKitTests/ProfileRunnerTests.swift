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
        #expect(!backend.ops.contains(where: {
            if case .setMain = $0 { return true } else { return false }
        }), "treadmill profile has no main declared")
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
