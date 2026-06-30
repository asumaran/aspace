import Foundation

/// Applies a named resolution preset: sets each listed display to its target
/// resolution. Unlike `ProfileRunner`, it never connects/disconnects displays
/// or changes the main — it only changes scaling on monitors that are already
/// on, so flipping presets mid-session is fast and flicker-free.
///
/// A display that is offline, or that doesn't support the requested
/// resolution, is skipped with a warning rather than aborting the whole
/// preset, mirroring `ProfileRunner`'s non-destructive philosophy.
public enum ResolutionRunner {
    public enum RunError: Error, CustomStringConvertible {
        case presetNotFound(String)
        case operation(String, Error)

        public var description: String {
            switch self {
            case .presetNotFound(let name):
                return "Resolution preset not found in config: \(name)"
            case .operation(let what, let err):
                return "\(what): \(err)"
            }
        }
    }

    public static func availablePresetNames(config: AspaceConfig) -> [String] {
        config.resolutions.keys.sorted()
    }

    /// Production entry point — uses the real CoreGraphics backend.
    public static func run(preset name: String, config: AspaceConfig) throws {
        try run(preset: name, config: config, backend: LiveDisplayBackend())
    }

    // MARK: - Test seam

    static func run(
        preset name: String,
        config: AspaceConfig,
        backend: DisplayBackend,
        warn: (String) -> Void = { msg in
            AspaceLog.profile.warning("\(msg, privacy: .public)")
            FileHandle.standardError.write(Data("aspace: \(msg)\n".utf8))
        }
    ) throws {
        guard let preset = config.resolutions[name] else {
            throw RunError.presetNotFound(name)
        }
        AspaceLog.profile.info("Applying resolution preset '\(name, privacy: .public)'")

        for (rawUUID, spec) in preset {
            let uuid = rawUUID.uppercased()
            do {
                try backend.setMode(uuid: uuid, spec: spec)
            } catch DisplayKitError.displayNotFound {
                warn("skipped resolution \(spec.stringValue) for \(uuid): not currently connected")
            } catch DisplayKitError.modeNotAvailable {
                warn("skipped resolution \(spec.stringValue) for \(uuid): mode not available on this display")
            } catch {
                throw RunError.operation("set mode \(uuid)", error)
            }
        }

        AspaceLog.profile.info("Resolution preset '\(name, privacy: .public)' applied")
    }
}
