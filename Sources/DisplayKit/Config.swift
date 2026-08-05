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
/// `resolutions` is an independent axis: each named preset maps display UUIDs
/// to a target resolution and is applied without touching connections or the
/// main display, so you can flip the same monitors between layouts.
///
/// Example:
/// ```json
/// {
///   "profiles": {
///     "treadmill": {
///       "disable": ["CD233C7A-...", "A98DE3E9-...", "204E366C-..."],
///       "audioOutput": "LG TV"
///     },
///     "desk": {
///       "disable": ["6B111247-..."],
///       "main":     "CD233C7A-...",
///       "audioOutput": "External Headphones"
///     }
///   },
///   "resolutions": {
///     "cozy":     { "CD233C7A-...": "2560x1440", "A98DE3E9-...": "2560x1440" },
///     "spacious": { "CD233C7A-...": "3200x1800", "A98DE3E9-...": "3200x1800" }
///   }
/// }
/// ```
public struct AspaceConfig: Codable {
    /// A desired resolution for a display, expressed as a point size ("looks
    /// like" size in System Settings), e.g. `"2560x1440"`. Serialized as a
    /// plain JSON string so configs stay readable; the runner resolves it to a
    /// concrete display mode at apply time (preferring HiDPI, higher refresh,
    /// safe modes). Modeled as a type so a richer object form can be added
    /// later without breaking existing string-based configs.
    public struct ModeSpec: Codable, Equatable {
        public let pointWidth: Int
        public let pointHeight: Int

        public init(pointWidth: Int, pointHeight: Int) {
            self.pointWidth = pointWidth
            self.pointHeight = pointHeight
        }

        public enum ParseError: Error, CustomStringConvertible {
            case malformed(String)
            public var description: String {
                switch self {
                case .malformed(let s):
                    return "Invalid resolution \"\(s)\": expected \"WIDTHxHEIGHT\" (e.g. \"2560x1440\")"
                }
            }
        }

        public init(string: String) throws {
            let parts = string.lowercased().split(separator: "x", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let h = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  w > 0, h > 0 else {
                throw ParseError.malformed(string)
            }
            self.pointWidth = w
            self.pointHeight = h
        }

        public var stringValue: String { "\(pointWidth)x\(pointHeight)" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            try self.init(string: try c.decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(stringValue)
        }
    }

    public struct Profile: Codable {
        public let disable: [String]
        public let main: String?
        /// Audio output device to make the system default after applying the
        /// profile, matched against the device names from `aspace audio-outputs`
        /// (case-insensitive; a substring works when it matches one device).
        /// Optional — profiles without it leave the audio output untouched.
        public let audioOutput: String?

        public init(disable: [String] = [], main: String? = nil, audioOutput: String? = nil) {
            self.disable = disable
            self.main = main
            self.audioOutput = audioOutput
        }
    }

    /// A named resolution preset: a target resolution per display UUID, applied
    /// independently of any profile (it never connects/disconnects displays or
    /// changes the main). Lets you flip the same set of monitors between, say,
    /// a "cozy" larger-text layout and a "spacious" smaller-text one.
    public typealias ResolutionPreset = [String: ModeSpec]

    /// Bumped when the on-disk shape changes in an incompatible way.
    /// Files without this field are treated as schema 1.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profiles: [String: Profile]
    public let resolutions: [String: ResolutionPreset]

    public init(
        profiles: [String: Profile],
        resolutions: [String: ResolutionPreset] = [:],
        schemaVersion: Int = AspaceConfig.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.resolutions = resolutions
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case resolutions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AspaceConfig.currentSchemaVersion
        self.profiles = try c.decodeIfPresent([String: Profile].self, forKey: .profiles) ?? [:]
        self.resolutions = try c.decodeIfPresent([String: ResolutionPreset].self, forKey: .resolutions) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(profiles, forKey: .profiles)
        if !resolutions.isEmpty {
            try c.encode(resolutions, forKey: .resolutions)
        }
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

    /// Every display UUID this config references — across profiles (`disable`
    /// targets and `main`) and resolution presets. Lets callers surface
    /// known-but-offline displays the user actually manages, without pulling in
    /// unrelated entries from the persistent registry. Uppercased so matching is
    /// case-insensitive.
    public var referencedDisplayUUIDs: Set<String> {
        var uuids = Set<String>()
        for profile in profiles.values {
            for uuid in profile.disable { uuids.insert(uuid.uppercased()) }
            if let main = profile.main { uuids.insert(main.uppercased()) }
        }
        for preset in resolutions.values {
            for uuid in preset.keys { uuids.insert(uuid.uppercased()) }
        }
        return uuids
    }

    /// Writes the config to `storeURL`, creating the parent directory if
    /// needed. Pretty-printed with sorted keys for stable, hand-editable diffs.
    public func save() throws {
        let dir = Self.storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.storeURL, options: .atomic)
    }
}
