import Foundation

/// Builds config entries from a snapshot of the current display arrangement,
/// so the CLI's capture commands can record "the way things are right now"
/// without the user hand-writing UUIDs or resolutions.
///
/// Pure and value-based: the CLI gathers the live snapshot from CoreGraphics
/// and hands it here, keeping the mapping logic unit-testable.
public enum ProfileCapture {
    /// A single currently-on display with its current resolution.
    public struct ActiveDisplay {
        public let uuid: String
        public let mode: AspaceConfig.ModeSpec
        public init(uuid: String, mode: AspaceConfig.ModeSpec) {
            self.uuid = uuid
            self.mode = mode
        }
    }

    /// Assemble a topology profile: `mainUUID` is the current primary, and
    /// `off` are known displays that are currently disabled — they become the
    /// profile's `disable` list so the arrangement round-trips.
    public static func profile(mainUUID: String?, off: [String]) -> AspaceConfig.Profile {
        AspaceConfig.Profile(disable: off.sorted(), main: mainUUID)
    }

    /// Assemble a resolution preset from the on displays' current resolutions.
    public static func resolutionPreset(active: [ActiveDisplay]) -> AspaceConfig.ResolutionPreset {
        var preset: AspaceConfig.ResolutionPreset = [:]
        for display in active {
            preset[display.uuid] = display.mode
        }
        return preset
    }
}
