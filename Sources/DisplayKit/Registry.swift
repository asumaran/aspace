import Foundation
import CoreGraphics

/// Persistent cache that survives `aspace` CLI invocations within the same
/// login session. Lets us re-enable a display by UUID even after CG has
/// marked it offline and forgotten its CGDirectDisplayID.
///
/// We deliberately use `CGConfigureOption.forSession` for the enable/disable
/// op, so on reboot every display comes back online and stale cache entries
/// become harmless — they just get overwritten on the next live observation.
struct DisplayRegistry: Codable {
    /// Bumped when the on-disk shape changes in an incompatible way.
    /// Files without this field are treated as schema 1.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [String: Entry]

    struct Entry: Codable, Equatable {
        let displayID: UInt32
        let name: String?
        let lastSeen: Date
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
    }

    init(schemaVersion: Int = currentSchemaVersion, entries: [String: Entry] = [:]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        self.entries = try c.decodeIfPresent([String: Entry].self, forKey: .entries) ?? [:]
    }

    static let storeURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("displays.json")
    }()

    static func load() -> DisplayRegistry {
        guard let data = try? Data(contentsOf: storeURL),
              let reg = try? JSONDecoder().decode(DisplayRegistry.self, from: data) else {
            return DisplayRegistry()
        }
        if reg.schemaVersion > currentSchemaVersion {
            return DisplayRegistry()
        }
        return reg
    }

    func save() {
        if let existing = try? Data(contentsOf: Self.storeURL),
           let decoded = try? JSONDecoder().decode(DisplayRegistry.self, from: existing),
           decoded.schemaVersion > Self.currentSchemaVersion {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    mutating func record(uuid: String, displayID: CGDirectDisplayID, name: String? = nil) {
        let key = uuid.uppercased()
        let existing = entries[key]
        entries[key] = Entry(
            displayID: UInt32(displayID),
            name: name ?? existing?.name,
            lastSeen: Date()
        )
    }

    mutating func remove(uuid: String) {
        entries.removeValue(forKey: uuid.uppercased())
    }

    func lookup(uuid: String) -> CGDirectDisplayID? {
        guard let entry = entries[uuid.uppercased()] else { return nil }
        return CGDirectDisplayID(entry.displayID)
    }
}
