import Foundation

/// User-supplied configuration for the menu bar app and the CLI's high-level
/// mode commands. Lives at `~/.config/aspace/config.json`.
///
/// Example:
/// ```json
/// {
///   "modes": {
///     "treadmill": {
///       "enable":  ["6B111247-..."],
///       "disable": ["CD233C7A-...", "A98DE3E9-...", "204E366C-..."]
///     },
///     "desk": {
///       "enable":  ["CD233C7A-...", "A98DE3E9-...", "204E366C-..."],
///       "disable": ["6B111247-..."],
///       "main":     "CD233C7A-..."
///     }
///   }
/// }
/// ```
public struct AspaceConfig: Codable {
    public struct Mode: Codable {
        public let enable: [String]
        public let disable: [String]
        public let main: String?

        public init(enable: [String] = [], disable: [String] = [], main: String? = nil) {
            self.enable = enable
            self.disable = disable
            self.main = main
        }
    }

    public let modes: [String: Mode]

    public init(modes: [String: Mode]) {
        self.modes = modes
    }

    public static let storeURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aspace/config.json")
    }()

    public static func load() throws -> AspaceConfig {
        let data = try Data(contentsOf: storeURL)
        return try JSONDecoder().decode(AspaceConfig.self, from: data)
    }

    public static func loadOrEmpty() -> AspaceConfig {
        (try? load()) ?? AspaceConfig(modes: [:])
    }
}
