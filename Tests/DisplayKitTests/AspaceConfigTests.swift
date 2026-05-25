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
