import Foundation
import Testing
@testable import DisplayKit

/// Covers the post-apply watchdog: after a profile switch, a TV can drop its
/// HDMI link and re-enumerate under a different hardware UUID, leaving the
/// desktop on a display nothing manages. `stabilize` watches for that and
/// adopts the lone replacement as main.
@Suite struct StabilizationTests {

    private let TV     = "TV-UUID"
    private let NEW_TV = "NEWTV-UUID"
    private let A      = "A-UUID"
    private let B      = "B-UUID"

    // MARK: - Candidate rule (pure)

    @Test func candidateIsTheLoneReplacement() {
        #expect(ProfileRunner.stabilizationCandidate(expectedMain: TV, online: [NEW_TV]) == NEW_TV)
    }

    @Test func noCandidateWhileExpectedMainIsOnline() {
        #expect(ProfileRunner.stabilizationCandidate(expectedMain: TV, online: [TV]) == nil)
        #expect(ProfileRunner.stabilizationCandidate(expectedMain: TV, online: [TV, NEW_TV]) == nil)
    }

    @Test func noCandidateWithZeroOrSeveralSurvivors() {
        #expect(ProfileRunner.stabilizationCandidate(expectedMain: TV, online: []) == nil)
        #expect(ProfileRunner.stabilizationCandidate(expectedMain: TV, online: [A, B]) == nil)
    }

    // MARK: - Watch loop

    @Test func adoptsReenumeratedReplacementAsMain() {
        // The incident shape: the expected main never comes back, and a
        // display under a brand-new UUID shows up alone a couple of polls in.
        let backend = FakeBackend(online: [], known: [TV])
        var polls = 0
        ProfileRunner.stabilize(
            expectedMain: TV,
            backend: backend,
            sleep: { _ in
                polls += 1
                if polls == 2 {
                    backend.online = [NEW_TV]
                    backend.known.insert(NEW_TV)
                }
            },
            warn: { _ in }
        )

        #expect(backend.ops.contains(.setMain(NEW_TV)))
        #expect(backend.ops.contains(.warpCursor), "the cursor must be recovered onto the new main")
    }

    @Test func adoptionRetriesTransientSetMainFailures() {
        // CGCompleteDisplayConfiguration fails transiently while the display
        // system settles; the adoption must retry instead of giving up.
        let backend = FakeBackend(online: [], known: [TV])
        backend.mainFailuresRemaining = [NEW_TV: 2]
        var polls = 0
        ProfileRunner.stabilize(
            expectedMain: TV,
            backend: backend,
            sleep: { _ in
                polls += 1
                if polls == 1 {
                    backend.online = [self.NEW_TV]
                    backend.known.insert(self.NEW_TV)
                }
            },
            warn: { _ in }
        )
        #expect(backend.ops.contains(.setMain(NEW_TV)))
        #expect(backend.main == NEW_TV)
    }

    @Test func cursorIsReWarpedOnceTheAdoptedMainSettles() {
        // Warping at adoption time can race the re-enumeration and land
        // nowhere (main still mid-transaction), so a second warp must happen
        // when the watch ends on a settled topology.
        let backend = FakeBackend(online: [], known: [TV])
        var polls = 0
        ProfileRunner.stabilize(
            expectedMain: TV,
            backend: backend,
            sleep: { _ in
                polls += 1
                if polls == 1 {
                    backend.online = [self.NEW_TV]
                    backend.known.insert(self.NEW_TV)
                }
            },
            warn: { _ in }
        )
        let warps = backend.ops.filter { $0 == .warpCursor }.count
        #expect(warps == 2, "one warp at adoption, one on the settled topology")
    }

    @Test func replacementMustSurviveTwoPolls() {
        // A display that flashes online for a single poll is mid-teardown
        // churn, not a replacement — promoting it would throw an extra
        // reconfiguration into the volatile window.
        let backend = FakeBackend(online: [NEW_TV], known: [TV, NEW_TV])
        var polls = 0
        ProfileRunner.stabilize(
            expectedMain: TV,
            backend: backend,
            sleep: { _ in
                polls += 1
                if polls == 1 { backend.online = [] }   // gone before the second sighting
            },
            warn: { _ in }
        )

        #expect(!backend.ops.contains(.setMain(NEW_TV)))
    }

    @Test func stableMainEndsTheWatchWithoutChanges() {
        let backend = FakeBackend(online: [TV], known: [TV])
        var sleeps = 0
        ProfileRunner.stabilize(expectedMain: TV, backend: backend, sleep: { _ in sleeps += 1 })

        #expect(backend.ops.isEmpty, "a stable topology needs no correction")
        #expect(sleeps < 20, "the watch must end early once stable, not run the full window")
    }

    @Test func givesUpQuietlyWhenNothingReplacesTheMain() {
        // Expected main gone and nothing shows up: non-destructive means the
        // watchdog does nothing rather than inventing a change.
        let backend = FakeBackend(online: [], known: [TV])
        var sleeps = 0
        ProfileRunner.stabilize(expectedMain: TV, backend: backend, sleep: { _ in sleeps += 1 }, warn: { _ in })

        #expect(backend.ops.isEmpty)
        #expect(sleeps == 20, "watched the full window before giving up")
    }

    @Test func severalSurvivorsAreLeftAlone() {
        // Multi-display topologies have no unambiguous replacement; guessing
        // a main there could fight the user's arrangement.
        let backend = FakeBackend(online: [A, B], known: [TV, A, B])
        ProfileRunner.stabilize(expectedMain: TV, backend: backend, warn: { _ in })
        #expect(backend.ops.isEmpty)
    }

    // MARK: - Restoring a lost main after an aborted switch

    @Test func abortedSwitchRestoresTheStolenMain() throws {
        // The live incident: treadmill soft-enables the TV, the TV never comes
        // online (cold HDMI link), and that phantom enable steals main-ness
        // into the void. The abort must put main back on the display that had
        // it, or the whole session is left without a main (broken menus).
        let STUDIO = "STUDIO-UUID"
        let backend = FakeBackend(online: [STUDIO], known: [STUDIO, TV])
        backend.main = STUDIO
        backend.mainLostOnEnable = [TV]
        backend.lagOnlinePolls = [TV: Int.max]   // enabled, but never shows up

        try ProfileRunner.run(
            profile: "treadmill",
            config: AspaceConfig(profiles: ["treadmill": .init(disable: [STUDIO])]),
            backend: backend,
            warn: { _ in }
        )

        #expect(backend.online == [STUDIO], "abort leaves the current displays enabled")
        #expect(backend.main == STUDIO, "the stolen main must be restored")
    }

    @Test func restoreMainPrefersThePreviousMain() {
        let backend = FakeBackend(online: [A, B])
        ProfileRunner.restoreMainIfLost(previousMain: B, backend: backend, warn: { _ in })
        #expect(backend.main == B)
    }

    @Test func restoreMainFallsBackToAnyOnlineDisplay() {
        // The previous main is offline (it was the display being switched
        // away from); any online display beats leaving the system mainless.
        let backend = FakeBackend(online: [A, B])
        ProfileRunner.restoreMainIfLost(previousMain: TV, backend: backend, warn: { _ in })
        #expect(backend.main != nil)
    }

    @Test func restoreMainLeavesAnExistingMainAlone() {
        let backend = FakeBackend(online: [A, B])
        backend.main = A
        ProfileRunner.restoreMainIfLost(previousMain: B, backend: backend, warn: { _ in })
        #expect(backend.main == A)
        #expect(backend.ops.isEmpty)
    }

    @Test func restoreMainDoesNothingWithNoDisplaysOnline() {
        let backend = FakeBackend(online: [])
        ProfileRunner.restoreMainIfLost(previousMain: TV, backend: backend, warn: { _ in })
        #expect(backend.ops.isEmpty)
    }

    @Test func noExpectedMainMeansNoWatch() {
        let backend = FakeBackend(online: [A, B], known: [A, B])
        var sleeps = 0
        ProfileRunner.stabilize(expectedMain: nil, backend: backend, sleep: { _ in sleeps += 1 })
        #expect(sleeps == 0, "without an anchor there is nothing to guard")
    }

    @Test func keepsWatchingAfterAdoptingTheReplacement() {
        // The TV can re-enumerate more than once while the link settles; the
        // watchdog re-anchors on the adopted display and keeps guarding it.
        let backend = FakeBackend(online: [], known: [TV])
        let SECOND = "SECOND-UUID"
        var polls = 0
        ProfileRunner.stabilize(
            expectedMain: TV,
            backend: backend,
            sleep: { _ in
                polls += 1
                if polls == 1 { backend.online = [self.NEW_TV]; backend.known.insert(self.NEW_TV) }
                if polls == 5 { backend.online = [SECOND]; backend.known.insert(SECOND) }
            },
            warn: { _ in }
        )

        #expect(backend.ops.contains(.setMain(NEW_TV)))
        #expect(backend.ops.contains(.setMain(SECOND)), "the adopted main is guarded too")
    }
}
