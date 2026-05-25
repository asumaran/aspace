import Foundation

/// User-supplied configuration for the menu bar app and the CLI's high-level
/// profile commands. Lives at `~/.config/aspace/config.json`.
///
/// Each profile lists the displays that should be DISCONNECTED. Everything
/// else known to the system stays on (or gets turned back on). This is an
/// "allow by default" model on purpose — adding a new monitor or making a
/// typo in a UUID can never accidentally take all your screens offline.
///
/// The built-in `"all"` profile (always present, no config needed) disables
/// nothing — use it as the "reconnect everything" command.
///
/// Example:
/// ```json
/// {
///   "profiles": {
///     "treadmill": {
///       "disable": ["CD233C7A-...", "A98DE3E9-...", "204E366C-..."]
///     },
///     "desk": {
///       "disable": ["6B111247-..."],
///       "main":     "CD233C7A-..."
///     }
///   }
/// }
/// ```
public struct AspaceConfig: Codable {
    public struct Profile: Codable {
        public let disable: [String]
        public let main: String?

        public init(disable: [String] = [], main: String? = nil) {
            self.disable = disable
            self.main = main
        }
    }

    /// Bumped when the on-disk shape changes in an incompatible way.
    /// Files without this field are treated as schema 1.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profiles: [String: Profile]

    public init(profiles: [String: Profile], schemaVersion: Int = AspaceConfig.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AspaceConfig.currentSchemaVersion
        self.profiles = try c.decodeIfPresent([String: Profile].self, forKey: .profiles) ?? [:]
    }

    /// Name of the built-in "disconnect nothing" profile.
    public static let allProfileName = "all"

    public static let storeURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aspace/config.json")
    }()

    public enum LoadError: Error, CustomStringConvertible {
        case unsupportedSchema(found: Int, supported: Int)

        public var description: String {
            switch self {
            case .unsupportedSchema(let found, let supported):
                return "config.json schemaVersion \(found) is newer than this aspace build supports (\(supported)). Update aspace."
            }
        }
    }

    public static func load() throws -> AspaceConfig {
        let data = try Data(contentsOf: storeURL)
        let cfg = try JSONDecoder().decode(AspaceConfig.self, from: data)
        if cfg.schemaVersion > currentSchemaVersion {
            throw LoadError.unsupportedSchema(found: cfg.schemaVersion, supported: currentSchemaVersion)
        }
        return cfg
    }

    public static func loadOrEmpty() -> AspaceConfig {
        (try? load()) ?? AspaceConfig(profiles: [:])
    }
}
