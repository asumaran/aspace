import Foundation
import CoreGraphics

/// Applies a profile by name. A profile lists which UUIDs to DISABLE; every
/// other known display gets (or stays) enabled. Built-in `"all"` disables
/// nothing.
///
/// Safety net: the runner refuses to apply a profile that would leave zero
/// displays enabled. Forgetting to list a UUID or making a typo therefore
/// just leaves more screens on than intended — it cannot black everything
/// out by accident.
public enum ProfileRunner {
    public enum RunError: Error, CustomStringConvertible {
        case profileNotFound(String)
        case wouldDisableEverything(String)
        case operation(String, Error)

        public var description: String {
            switch self {
            case .profileNotFound(let name):
                return "Profile not found in config: \(name)"
            case .wouldDisableEverything(let name):
                return "Refusing to apply profile '\(name)': it would leave zero displays enabled"
            case .operation(let what, let err):
                return "\(what): \(err)"
            }
        }
    }

    public static func availableProfileNames(config: AspaceConfig) -> [String] {
        let userDefined = config.profiles.keys.sorted()
        return userDefined + [AspaceConfig.allProfileName]
    }

    /// Public production entry point — uses the real CoreGraphics backend
    /// and sleeps briefly between phases to let macOS settle.
    public static func run(profile name: String, config: AspaceConfig) throws {
        try run(profile: name, config: config, backend: LiveDisplayBackend(), sleep: liveSleep)
    }

    /// Removes registry entries that have not been observed in `days` days.
    /// Returns the UUIDs that were pruned.
    @discardableResult
    public static func prune(olderThanDays days: Int) -> [String] {
        var registry = DisplayRegistry.load()
        let pruned = prune(olderThanDays: days, in: &registry, now: Date())
        registry.save()
        return pruned
    }

    // MARK: - Test seams

    /// Same logic as the production `run`, but with a pluggable backend and
    /// sleep function so tests can avoid CoreGraphics and avoid the real
    /// wall-clock delays.
    public static func run(
        profile name: String,
        config: AspaceConfig,
        backend: DisplayBackend,
        sleep sleepFn: (TimeInterval) -> Void = { _ in },
        warn: (String) -> Void = { msg in
            FileHandle.standardError.write(Data("aspace: \(msg)\n".utf8))
        }
    ) throws {
        let known = backend.allKnownUUIDs()
        let toDisable: Set<String>
        let mainUUID: String?

        if name == AspaceConfig.allProfileName {
            toDisable = []
            mainUUID = nil
        } else if let profile = config.profiles[name] {
            toDisable = Set(profile.disable.map { $0.uppercased() })
            mainUUID = profile.main
        } else {
            throw RunError.profileNotFound(name)
        }

        let toEnable = known.subtracting(toDisable)

        if !known.isEmpty && toEnable.isEmpty {
            throw RunError.wouldDisableEverything(name)
        }

        let liveUUIDs = Set(backend.listDisplays().map { $0.uuid.uppercased() })

        for uuid in toEnable {
            do {
                try backend.setEnabled(uuid: uuid, enabled: true)
            } catch {
                if liveUUIDs.contains(uuid) {
                    throw RunError.operation("enable \(uuid)", error)
                }
                warn("skipped enable of \(uuid): not currently connected")
            }
        }

        sleepFn(1.0)

        if let mainUUID = mainUUID {
            do {
                try backend.setMain(uuid: mainUUID)
            } catch DisplayKitError.displayNotFound {
                warn("cannot set main display \(mainUUID): not currently connected (profile applied without setting main)")
            } catch {
                throw RunError.operation("main \(mainUUID)", error)
            }
            sleepFn(0.5)
        }

        for uuid in toDisable where known.contains(uuid) {
            do { try backend.setEnabled(uuid: uuid, enabled: false) }
            catch { throw RunError.operation("disable \(uuid)", error) }
        }
    }

    /// Pure prune logic that works on an in-memory registry. Useful for
    /// tests; production callers go through the disk-loading overload above.
    @discardableResult
    public static func prune(olderThanDays days: Int, in registry: inout DisplayRegistry, now: Date) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        let stale = registry.entries.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        for uuid in stale { registry.remove(uuid: uuid) }
        return stale
    }

    // MARK: - Helpers

    private static func liveSleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
