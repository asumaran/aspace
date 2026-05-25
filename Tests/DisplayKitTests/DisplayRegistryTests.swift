import Foundation
import Testing
@testable import DisplayKit

@Suite struct DisplayRegistryTests {

    @Test func roundtripPreservesEntriesAndSchema() throws {
        var reg = DisplayRegistry()
        reg.record(uuid: "UUID-1", displayID: 2, name: "Studio Display")
        reg.record(uuid: "UUID-2", displayID: 4, name: "LG TV")

        let data = try JSONEncoder().encode(reg)
        let decoded = try JSONDecoder().decode(DisplayRegistry.self, from: data)

        #expect(decoded.schemaVersion == DisplayRegistry.currentSchemaVersion)
        #expect(decoded.entries["UUID-1"]?.displayID == 2)
        #expect(decoded.entries["UUID-1"]?.name == "Studio Display")
        #expect(decoded.entries["UUID-2"]?.name == "LG TV")
    }

    @Test func legacyFileWithoutSchemaVersionLoads() throws {
        let json = #"""
        {
            "entries": {
                "UUID-1": {
                    "displayID": 2,
                    "name": "Studio",
                    "lastSeen": 700000000
                }
            }
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DisplayRegistry.self, from: json)
        #expect(decoded.schemaVersion == DisplayRegistry.currentSchemaVersion)
        #expect(decoded.entries["UUID-1"]?.displayID == 2)
    }

    @Test func recordPreservesExistingNameWhenNotProvided() {
        var reg = DisplayRegistry()
        reg.record(uuid: "UUID-1", displayID: 2, name: "Studio Display")
        reg.record(uuid: "UUID-1", displayID: 2)  // no name provided

        #expect(reg.entries["UUID-1"]?.name == "Studio Display")
    }

    @Test func uuidLookupIsCaseInsensitive() {
        var reg = DisplayRegistry()
        reg.record(uuid: "abc-123", displayID: 7)
        #expect(reg.lookup(uuid: "ABC-123") == 7)
        #expect(reg.lookup(uuid: "abc-123") == 7)
        #expect(reg.lookup(uuid: "other") == nil)
    }
}
