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

    public static func run(profile name: String, config: AspaceConfig) throws {
        let known = DisplayKit.allKnownUUIDs()
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

        // Safety net: never end up with zero enabled displays.
        if !known.isEmpty && toEnable.isEmpty {
            throw RunError.wouldDisableEverything(name)
        }

        // Snapshot of which UUIDs are currently online so we can distinguish
        // a real failure (display IS online but enable was rejected) from
        // a cached-only attempt (display isn't currently connected).
        let liveUUIDs = Set(DisplayKit.listDisplays().map { $0.uuid.uppercased() })

        // Enable first so we never have a moment with zero active displays.
        for uuid in toEnable {
            do {
                try DisplayKit.setEnabled(uuid: uuid, enabled: true)
            } catch {
                if liveUUIDs.contains(uuid) {
                    // Currently online display refused to be (re)enabled —
                    // surface the failure to the caller.
                    throw RunError.operation("enable \(uuid)", error)
                }
                // Cached-only entry whose displayID no longer maps to live
                // hardware. Could be a phantom (transient AirPlay/Sidecar)
                // or a real display that's temporarily disconnected and
                // will come back later. We don't have a reliable way to
                // tell the difference, so keep the entry and skip — a user
                // can `aspace prune` to clean up old phantoms manually.
                warn("skipped enable of \(uuid): not currently connected")
            }
        }

        Thread.sleep(forTimeInterval: 1.0)

        if let mainUUID = mainUUID {
            do {
                try DisplayKit.setMain(uuid: mainUUID)
            } catch DisplayKitError.displayNotFound {
                warn("cannot set main display \(mainUUID): not currently connected (profile applied without setting main)")
            } catch {
                throw RunError.operation("main \(mainUUID)", error)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        for uuid in toDisable where known.contains(uuid) {
            do { try DisplayKit.setEnabled(uuid: uuid, enabled: false) }
            catch { throw RunError.operation("disable \(uuid)", error) }
        }
    }

    /// Removes registry entries that have not been observed in `days` days.
    /// Returns the UUIDs that were pruned.
    @discardableResult
    public static func prune(olderThanDays days: Int) -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var registry = DisplayRegistry.load()
        let stale = registry.entries.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        for uuid in stale { registry.remove(uuid: uuid) }
        registry.save()
        return stale
    }

    private static func warn(_ msg: String) {
        FileHandle.standardError.write(Data("aspace: \(msg)\n".utf8))
    }
}
