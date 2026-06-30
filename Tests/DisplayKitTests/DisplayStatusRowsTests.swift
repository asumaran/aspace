import Foundation
import Testing
@testable import DisplayKit

@Suite struct DisplayStatusRowsTests {

    private func online(
        _ uuid: String,
        name: String? = nil,
        isEnabled: Bool = true,
        isMain: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(
            id: 0,
            uuid: uuid,
            name: name ?? uuid,
            isEnabled: isEnabled,
            isMain: isMain,
            bounds: .zero
        )
    }

    @Test func onlineDisplaysBecomeRowsMainFirstThenByName() {
        let rows = DisplayKit.displayStatusRows(
            online: [
                online("AAA", name: "Zenith"),
                online("BBB", name: "Apex", isMain: true),
                online("CCC", name: "Middle"),
            ],
            configuredUUIDs: [],
            registryNames: [:]
        )

        #expect(rows.map(\.name) == ["Apex", "Middle", "Zenith"])
        #expect(rows.allSatisfy { $0.isOnline })
        #expect(rows.first?.isMain == true)
    }

    @Test func inactiveOnlineDisplayIsNotActiveButStillOnline() {
        let rows = DisplayKit.displayStatusRows(
            online: [online("AAA", name: "Mirror", isEnabled: false)],
            configuredUUIDs: [],
            registryNames: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].isOnline)
        #expect(rows[0].isActive == false)
    }

    @Test func configuredOfflineDisplayAppearsNamedFromRegistry() {
        let rows = DisplayKit.displayStatusRows(
            online: [online("AAA", name: "Studio Display", isMain: true)],
            configuredUUIDs: ["BBB"],
            registryNames: ["BBB": "LG TV SSCR2"]
        )

        #expect(rows.map(\.name) == ["Studio Display", "LG TV SSCR2"])
        let offline = rows.last
        #expect(offline?.isOnline == false)
        #expect(offline?.isActive == false)
    }

    @Test func configuredOfflineDisplayWithoutNameIsSkipped() {
        let rows = DisplayKit.displayStatusRows(
            online: [],
            configuredUUIDs: ["AAA", "BBB"],
            registryNames: ["AAA": "", /* BBB has no entry */]
        )

        #expect(rows.isEmpty)
    }

    @Test func onlineDisplayInConfigIsNotDuplicatedAsOffline() {
        let rows = DisplayKit.displayStatusRows(
            online: [online("AAA", name: "Studio Display")],
            configuredUUIDs: ["AAA"],
            registryNames: ["AAA": "Studio Display"]
        )

        #expect(rows.count == 1)
        #expect(rows[0].isOnline)
    }

    @Test func matchingIsCaseInsensitive() {
        // Config references lowercase; online + registry use uppercase.
        let rows = DisplayKit.displayStatusRows(
            online: [online("AAAA-1111", name: "Built-in")],
            configuredUUIDs: ["aaaa-1111", "bbbb-2222"],
            registryNames: ["BBBB-2222": "DELL U2723QE"]
        )

        // The online one is not duplicated; the offline one is surfaced once.
        #expect(rows.count == 2)
        #expect(rows.filter { $0.isOnline }.map(\.name) == ["Built-in"])
        #expect(rows.filter { !$0.isOnline }.map(\.name) == ["DELL U2723QE"])
    }

    @Test func registryEntriesNotInConfigAreNotShown() {
        // A "ghost" the registry has seen but the user never configured.
        let rows = DisplayKit.displayStatusRows(
            online: [online("AAA", name: "Studio Display")],
            configuredUUIDs: ["AAA"],
            registryNames: ["AAA": "Studio Display", "GHOST": "Old Monitor"]
        )

        #expect(rows.map(\.name) == ["Studio Display"])
    }

    @Test func duplicateConfiguredUUIDsYieldOneOfflineRow() {
        let rows = DisplayKit.displayStatusRows(
            online: [],
            configuredUUIDs: ["BBB", "bbb", "BBB"],
            registryNames: ["BBB": "LG TV SSCR2"]
        )

        #expect(rows.count == 1)
        #expect(rows[0].uuid == "BBB")
    }
}
