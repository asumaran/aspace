import Foundation

/// User-supplied configuration for the menu bar app and the CLI's high-level
/// profile commands. Lives at `~/.config/aspace/config.json`.
///
/// Each profile lists the displays that should be active. Anything known to
/// the system but not listed gets disconnected when the profile is applied.
///
/// The built-in `"all"` profile (always present, no config needed) enables
/// every known display and disables nothing — use it as the "back to normal"
/// fallback.
///
/// Example:
/// ```json
/// {
///   "profiles": {
///     "treadmill": {
///       "active": ["6B111247-..."]
///     },
///     "desk": {
///       "active": ["CD233C7A-...", "A98DE3E9-...", "204E366C-..."],
///       "main":    "CD233C7A-..."
///     }
///   }
/// }
/// ```
public struct AspaceConfig: Codable {
    public struct Profile: Codable {
        public let active: [String]
        public let main: String?

        public init(active: [String], main: String? = nil) {
            self.active = active
            self.main = main
        }
    }

    public let profiles: [String: Profile]

    public init(profiles: [String: Profile]) {
        self.profiles = profiles
    }

    /// Name of the built-in "everything on" profile.
    public static let allProfileName = "all"

    public static let storeURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aspace/config.json")
    }()

    public static func load() throws -> AspaceConfig {
        let data = try Data(contentsOf: storeURL)
        return try JSONDecoder().decode(AspaceConfig.self, from: data)
    }

    public static func loadOrEmpty() -> AspaceConfig {
        (try? load()) ?? AspaceConfig(profiles: [:])
    }
}
