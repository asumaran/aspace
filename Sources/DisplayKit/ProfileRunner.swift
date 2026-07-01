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
    /// sleep function so tests (via `@testable import`) can avoid touching
    /// CoreGraphics and skip the real wall-clock delays.
    static func run(
        profile name: String,
        config: AspaceConfig,
        backend: DisplayBackend,
        sleep sleepFn: (TimeInterval) -> Void = { _ in },
        warn: (String) -> Void = { msg in
            AspaceLog.profile.warning("\(msg, privacy: .public)")
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
        AspaceLog.profile.notice("""
            plan profile='\(name, privacy: .public)' \
            online=[\(liveUUIDs.sorted().joined(separator: ","), privacy: .public)] \
            toEnable=[\(toEnable.sorted().joined(separator: ","), privacy: .public)] \
            toDisable=[\(toDisable.sorted().joined(separator: ","), privacy: .public)] \
            declaredMain=\(mainUUID ?? "-", privacy: .public)
            """)

        for uuid in toEnable {
            do {
                try backend.setEnabled(uuid: uuid, enabled: true)
                AspaceLog.profile.notice("enable \(uuid, privacy: .public): ok")
            } catch {
                if liveUUIDs.contains(uuid) {
                    AspaceLog.profile.error("enable \(uuid, privacy: .public): failed while online: \(String(describing: error), privacy: .public)")
                    throw RunError.operation("enable \(uuid)", error)
                }
                warn("skipped enable of \(uuid): not currently connected")
            }
        }

        sleepFn(1.0)

        // Resolve the main display from the pre-disable state: an explicit
        // `main` wins; otherwise, if `toDisable` would leave exactly one display
        // on, that sole survivor is promoted. Survivors are measured against
        // what is actually online after the enable phase, so offline registry
        // entries (ghosts that could not be enabled) never count.
        let liveAfterEnable = Set(backend.listDisplays().map { $0.uuid.uppercased() })
        let effectiveMain = mainUUID ?? soleSurvivingDisplay(online: liveAfterEnable, toDisable: toDisable)
        AspaceLog.profile.notice("""
            after-enable online=[\(liveAfterEnable.sorted().joined(separator: ","), privacy: .public)] \
            effectiveMain=\(effectiveMain ?? "-", privacy: .public)
            """)

        // Disable the unwanted displays BEFORE setting main. Collapsing to the
        // final topology first lets the surviving display settle into its own
        // native mode; only then do we re-home its origin. Calling setMain while
        // the other (e.g. retina) displays were still on can leave a lone TV in
        // an inherited oversized scaled mode, rendering the desktop too large
        // and cropped.
        for uuid in toDisable where known.contains(uuid) {
            do {
                try backend.setEnabled(uuid: uuid, enabled: false)
                AspaceLog.profile.notice("disable \(uuid, privacy: .public): ok")
            }
            catch {
                AspaceLog.profile.error("disable \(uuid, privacy: .public): failed: \(String(describing: error), privacy: .public)")
                throw RunError.operation("disable \(uuid)", error)
            }
        }

        // Now assign main / re-home the origin to (0,0). macOS makes a lone
        // display main implicitly, but only `setMain` normalizes its origin, so
        // the cursor and menu bar stay reachable.
        if let effectiveMain {
            sleepFn(0.5)
            do {
                try backend.setMain(uuid: effectiveMain)
                AspaceLog.profile.notice("setMain \(effectiveMain, privacy: .public): ok")
            } catch DisplayKitError.displayNotFound {
                warn("cannot set main display \(effectiveMain): not currently connected (profile applied without setting main)")
            } catch {
                AspaceLog.profile.error("setMain \(effectiveMain, privacy: .public): failed: \(String(describing: error), privacy: .public)")
                throw RunError.operation("main \(effectiveMain)", error)
            }
        }

        AspaceLog.profile.notice("profile '\(name, privacy: .public)' applied")
    }

    /// Pure prune logic that works on an in-memory registry. Internal so
    /// tests (via `@testable import`) can drive it without touching disk;
    /// production callers go through the disk-loading overload above.
    @discardableResult
    static func prune(olderThanDays days: Int, in registry: inout DisplayRegistry, now: Date) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        let stale = registry.entries.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        for uuid in stale { registry.remove(uuid: uuid) }
        return stale
    }

    // MARK: - Helpers

    /// The single display that would remain enabled after `toDisable` is applied
    /// to the currently-online set, or nil when zero or several survive. Lets a
    /// single-display profile auto-assign main — and thus normalize the origin
    /// to (0,0) — without the user declaring it. Both sets must be uppercased.
    static func soleSurvivingDisplay(online: Set<String>, toDisable: Set<String>) -> String? {
        let survivors = online.subtracting(toDisable)
        return survivors.count == 1 ? survivors.first : nil
    }

    private static func liveSleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
