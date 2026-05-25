import Foundation
import Testing
@testable import DisplayKit

@Suite struct PruneTests {

    @Test func pruneRemovesEntriesOlderThanCutoff() {
        let now = Date(timeIntervalSince1970: 800_000_000)
        let fresh = now.addingTimeInterval(-5 * 86400)        // 5 days old
        let stale = now.addingTimeInterval(-60 * 86400)       // 60 days old

        var reg = DisplayRegistry()
        reg.entries["FRESH"] = .init(displayID: 1, name: "Fresh", lastSeen: fresh)
        reg.entries["STALE"] = .init(displayID: 2, name: "Stale", lastSeen: stale)

        let pruned = ProfileRunner.prune(olderThanDays: 30, in: &reg, now: now)

        #expect(pruned == ["STALE"])
        #expect(reg.entries["FRESH"] != nil)
        #expect(reg.entries["STALE"] == nil)
    }

    @Test func pruneZeroDaysClearsEverythingStrictlyOlderThanNow() {
        let now = Date(timeIntervalSince1970: 800_000_000)
        var reg = DisplayRegistry()
        // 1 second old — strictly less than now with days=0
        reg.entries["A"] = .init(displayID: 1, name: nil, lastSeen: now.addingTimeInterval(-1))
        reg.entries["B"] = .init(displayID: 2, name: nil, lastSeen: now)

        let pruned = ProfileRunner.prune(olderThanDays: 0, in: &reg, now: now)

        #expect(Set(pruned) == ["A"])
        #expect(reg.entries["B"] != nil)
    }

    @Test func pruneReturnsEmptyWhenEverythingIsFresh() {
        let now = Date()
        var reg = DisplayRegistry()
        reg.entries["A"] = .init(displayID: 1, name: nil, lastSeen: now)

        let pruned = ProfileRunner.prune(olderThanDays: 30, in: &reg, now: now)
        #expect(pruned.isEmpty)
        #expect(reg.entries.count == 1)
    }
}
