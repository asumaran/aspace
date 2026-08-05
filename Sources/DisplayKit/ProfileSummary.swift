import Foundation

/// Read-only description of what a profile would configure — which displays
/// it leaves on or turns off, which one becomes main, and the audio output it
/// routes to. Derived purely from the config plus the display rows the menu
/// already shows, so the menu bar app can render a per-profile summary without
/// touching CoreGraphics or CoreAudio.
public enum ProfileSummary {
    public struct Row: Equatable {
        public let uuid: String
        public let name: String
        /// Whether the profile keeps this display on.
        public let enabled: Bool
        /// Whether the profile would make this display the main one: its
        /// declared `main`, or the sole display it leaves enabled.
        public let isMain: Bool

        public init(uuid: String, name: String, enabled: Bool, isMain: Bool) {
            self.uuid = uuid
            self.name = name
            self.enabled = enabled
            self.isMain = isMain
        }
    }

    public struct Summary: Equatable {
        public let rows: [Row]
        public let audioOutput: String?

        public init(rows: [Row], audioOutput: String?) {
            self.rows = rows
            self.audioOutput = audioOutput
        }
    }

    /// Summarize a profile against the displays the menu knows about (online
    /// plus config-referenced offline ones). Returns nil for a profile that is
    /// not in the config; the built-in "all" profile summarizes as everything
    /// on. Rows keep the incoming order, displays kept on listed first.
    public static func summarize(
        profile name: String,
        config: AspaceConfig,
        displays: [DisplayKit.DisplayStatusRow]
    ) -> Summary? {
        let disable: Set<String>
        let declaredMain: String?
        let audioOutput: String?
        if name == AspaceConfig.allProfileName {
            disable = []
            declaredMain = nil
            audioOutput = nil
        } else if let profile = config.profiles[name] {
            disable = Set(profile.disable.map { $0.uppercased() })
            declaredMain = profile.main?.uppercased()
            audioOutput = profile.audioOutput
        } else {
            return nil
        }

        let enabledUUIDs = displays.map { $0.uuid.uppercased() }.filter { !disable.contains($0) }
        let mainUUID = declaredMain ?? (enabledUUIDs.count == 1 ? enabledUUIDs.first : nil)

        let rows = displays.map { display in
            let uuid = display.uuid.uppercased()
            let enabled = !disable.contains(uuid)
            return Row(
                uuid: display.uuid,
                name: display.name,
                enabled: enabled,
                isMain: enabled && uuid == mainUUID
            )
        }
        let ordered = rows.filter { $0.enabled } + rows.filter { !$0.enabled }
        return Summary(rows: ordered, audioOutput: audioOutput)
    }
}
