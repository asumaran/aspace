import Foundation

/// Pure queries the menu bar app uses to reflect resolution presets in the UI:
/// which preset (if any) is currently active, and which presets are applicable
/// to the displays that are connected right now. Kept here, value-based and
/// free of CoreGraphics, so it is unit-testable; the app supplies the live
/// snapshot.
public enum ResolutionState {
    /// Names of presets that target at least one currently-online display.
    /// A preset whose displays are all offline (e.g. the desk presets while on
    /// the treadmill profile) is not applicable — applying it would be a no-op.
    public static func applicablePresets(
        online: Set<String>,
        in resolutions: [String: AspaceConfig.ResolutionPreset]
    ) -> Set<String> {
        let on = Set(online.map { $0.uppercased() })
        var result: Set<String> = []
        for (name, preset) in resolutions where preset.keys.contains(where: { on.contains($0.uppercased()) }) {
            result.insert(name)
        }
        return result
    }

    /// The preset whose every currently-online display already sits at its
    /// target resolution, or nil if none does. `current` maps each online
    /// display's UUID to its present point size. Offline displays in a preset
    /// are ignored, so a preset still reads as active with a monitor unplugged.
    /// Presets are checked in name order so the result is deterministic when
    /// more than one would match.
    public static func activePreset(
        current: [String: AspaceConfig.ModeSpec],
        in resolutions: [String: AspaceConfig.ResolutionPreset]
    ) -> String? {
        let cur = Dictionary(uniqueKeysWithValues: current.map { ($0.key.uppercased(), $0.value) })
        for name in resolutions.keys.sorted() {
            guard let preset = resolutions[name] else { continue }
            var anyOnline = false
            var allMatch = true
            for (uuid, spec) in preset {
                guard let c = cur[uuid.uppercased()] else { continue }
                anyOnline = true
                if c != spec { allMatch = false; break }
            }
            if anyOnline && allMatch { return name }
        }
        return nil
    }
}
