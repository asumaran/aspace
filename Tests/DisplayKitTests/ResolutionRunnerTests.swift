import Foundation
import Testing
@testable import DisplayKit

@Suite struct ResolutionRunnerTests {

    private let STUDIO = "STUDIO-UUID"
    private let DELL1  = "DELL1-UUID"
    private let DELL2  = "DELL2-UUID"

    private func config() -> AspaceConfig {
        AspaceConfig(profiles: [:], resolutions: [
            "cozy": [
                STUDIO: .init(pointWidth: 2560, pointHeight: 1440),
                DELL1:  .init(pointWidth: 2560, pointHeight: 1440),
                DELL2:  .init(pointWidth: 2560, pointHeight: 1440),
            ],
            "spacious": [
                STUDIO: .init(pointWidth: 3200, pointHeight: 1800),
                DELL1:  .init(pointWidth: 3200, pointHeight: 1800),
                DELL2:  .init(pointWidth: 3200, pointHeight: 1800),
            ],
        ])
    }

    @Test func appliesModeToEveryListedDisplay() throws {
        let backend = FakeBackend(online: [STUDIO, DELL1, DELL2], known: [STUDIO, DELL1, DELL2])
        try ResolutionRunner.run(preset: "spacious", config: config(), backend: backend)

        #expect(backend.ops.contains(.setMode(STUDIO, "3200x1800")))
        #expect(backend.ops.contains(.setMode(DELL1, "3200x1800")))
        #expect(backend.ops.contains(.setMode(DELL2, "3200x1800")))
    }

    @Test func neverTouchesConnectionsOrMain() throws {
        let backend = FakeBackend(online: [STUDIO, DELL1, DELL2], known: [STUDIO, DELL1, DELL2])
        try ResolutionRunner.run(preset: "cozy", config: config(), backend: backend)

        let onlyModes = backend.ops.allSatisfy {
            if case .setMode = $0 { return true } else { return false }
        }
        #expect(onlyModes, "resolution preset must not enable/disable or set main")
    }

    @Test func offlineDisplayIsSkippedWithWarning() throws {
        // Only one monitor connected; the preset lists three.
        let backend = FakeBackend(online: [STUDIO], known: [STUDIO, DELL1, DELL2])

        var warnings: [String] = []
        try ResolutionRunner.run(preset: "cozy", config: config(), backend: backend, warn: { warnings.append($0) })

        #expect(backend.ops.contains(.setMode(STUDIO, "2560x1440")))
        #expect(warnings.contains(where: { $0.contains("not currently connected") && $0.contains(DELL1) }))
        #expect(warnings.contains(where: { $0.contains("not currently connected") && $0.contains(DELL2) }))
    }

    @Test func unavailableModeWarnsAndContinues() throws {
        let backend = FakeBackend(online: [STUDIO, DELL1, DELL2], known: [STUDIO, DELL1, DELL2])
        backend.modeUnavailable = [DELL2]

        var warnings: [String] = []
        try ResolutionRunner.run(preset: "spacious", config: config(), backend: backend, warn: { warnings.append($0) })

        #expect(backend.ops.contains(.setMode(STUDIO, "3200x1800")))
        #expect(!backend.ops.contains(.setMode(DELL2, "3200x1800")))
        #expect(warnings.contains(where: { $0.contains("mode not available") && $0.contains(DELL2) }))
    }

    @Test func unknownPresetThrows() {
        let backend = FakeBackend(online: [STUDIO], known: [STUDIO])
        #expect(throws: ResolutionRunner.RunError.self) {
            try ResolutionRunner.run(preset: "nope", config: config(), backend: backend)
        }
    }
}
