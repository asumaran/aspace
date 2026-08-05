import Foundation
import Testing
@testable import DisplayKit

@Suite struct AspaceConfigTests {

    @Test func roundtripPreservesProfilesAndSchema() throws {
        let original = AspaceConfig(profiles: [
            "treadmill": .init(disable: ["AAA", "BBB"]),
            "desk":      .init(disable: ["CCC"], main: "DDD"),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AspaceConfig.self, from: data)

        #expect(decoded.schemaVersion == AspaceConfig.currentSchemaVersion)
        #expect(decoded.profiles["treadmill"]?.disable == ["AAA", "BBB"])
        #expect(decoded.profiles["desk"]?.main == "DDD")
    }

    @Test func profileAudioOutputRoundtripsAndDefaultsToNil() throws {
        let original = AspaceConfig(profiles: [
            "treadmill": .init(disable: ["AAA"], audioOutput: "LG TV"),
            "desk":      .init(disable: ["BBB"], main: "CCC"),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AspaceConfig.self, from: data)

        #expect(decoded.profiles["treadmill"]?.audioOutput == "LG TV")
        #expect(decoded.profiles["desk"]?.audioOutput == nil)
        // Profiles without an audioOutput must not serialize the key at all,
        // so existing hand-edited configs keep their shape: only the treadmill
        // profile mentions it.
        let json = String(data: data, encoding: .utf8)!
        #expect(json.components(separatedBy: "audioOutput").count == 2)
    }

    @Test func legacyFileWithoutSchemaVersionLoadsAsCurrent() throws {
        let json = #"""
        { "profiles": { "test": { "disable": [] } } }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AspaceConfig.self, from: json)
        #expect(decoded.schemaVersion == AspaceConfig.currentSchemaVersion)
        #expect(decoded.profiles["test"] != nil)
    }

    @Test func futureSchemaIsDecodedAsIsButMarkedNewer() throws {
        let json = #"""
        { "schemaVersion": 999, "profiles": {} }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AspaceConfig.self, from: json)
        #expect(decoded.schemaVersion == 999)
        #expect(decoded.schemaVersion > AspaceConfig.currentSchemaVersion)
    }
}
