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

    /// What applying a profile *would* do, computed read-only against the live
    /// topology — nothing is enabled, disabled, or re-homed. Lets you preview a
    /// switch (`aspace profile <name> --dry-run`) without risking the display
    /// layout, which is invaluable when a flaky display makes live testing
    /// expensive.
    public struct Plan: Equatable {
        public let profile: String
        public let onlineNow: [String]
        public let toEnable: [String]
        public let toDisable: [String]
        public let declaredMain: String?
        /// The main we predict will end up set: the declared main, or the sole
        /// surviving display if the switch leaves exactly one on.
        public let effectiveMain: String?
    }

    public static func plan(profile name: String, config: AspaceConfig) -> Plan? {
        plan(profile: name, config: config, backend: LiveDisplayBackend())
    }

    static func plan(profile name: String, config: AspaceConfig, backend: DisplayBackend) -> Plan? {
        let known = backend.allKnownUUIDs()
        let toDisable: Set<String>
        let declaredMain: String?
        if name == AspaceConfig.allProfileName {
            toDisable = []
            declaredMain = nil
        } else if let profile = config.profiles[name] {
            toDisable = Set(profile.disable.map { $0.uppercased() })
            declaredMain = profile.main?.uppercased()
        } else {
            return nil
        }
        let toEnable = known.subtracting(toDisable)
        let online = Set(backend.listDisplays().map { $0.uuid.uppercased() })
        // Predict which of the enable targets will actually be on: the currently
        // online ones plus the displays the config manages (so a stale registry
        // "ghost" that can't really come online doesn't skew the survivor).
        let willBeOnline = toEnable.intersection(online.union(config.referencedDisplayUUIDs))
        let effectiveMain = declaredMain ?? soleSurvivingDisplay(online: willBeOnline, toDisable: toDisable)
        return Plan(
            profile: name,
            onlineNow: online.sorted(),
            toEnable: toEnable.sorted(),
            toDisable: toDisable.sorted(),
            declaredMain: declaredMain,
            effectiveMain: effectiveMain
        )
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

        var skippedEnable = Set<String>()
        for uuid in toEnable {
            do {
                try backend.setEnabled(uuid: uuid, enabled: true)
                AspaceLog.profile.notice("enable \(uuid, privacy: .public): ok")
            } catch {
                if liveUUIDs.contains(uuid) {
                    AspaceLog.profile.error("enable \(uuid, privacy: .public): failed while online: \(String(describing: error), privacy: .public)")
                    throw RunError.operation("enable \(uuid)", error)
                }
                skippedEnable.insert(uuid)
                warn("skipped enable of \(uuid): not currently connected")
            }
        }

        sleepFn(1.0)

        // Resolve which display should be main. An explicit `main` wins;
        // otherwise, if exactly one display will end up enabled, promote that
        // sole survivor. The survivor set is derived from the PLAN — the kept
        // displays minus the ones that could not be enabled — NOT from a fresh
        // listDisplays(): a just-enabled display (a TV over HDMI especially) can
        // take several seconds to report online, and reading listDisplays() here
        // would show the survivor as absent, so it would never get promoted,
        // leaving a lone display un-normalized (stranded cursor, cropped desktop).
        let willBeOnline = toEnable.subtracting(skippedEnable)
        let effectiveMain = mainUUID ?? soleSurvivingDisplay(online: willBeOnline, toDisable: toDisable)
        AspaceLog.profile.notice("""
            after-enable willBeOnline=[\(willBeOnline.sorted().joined(separator: ","), privacy: .public)] \
            effectiveMain=\(effectiveMain ?? "-", privacy: .public) declaredMain=\(mainUUID != nil)
            """)

        // Set main, waiting for the target to actually come online first. A
        // freshly-enabled TV can lag several seconds over HDMI; setMain on an
        // offline display is a no-op, which is what left a lone TV un-normalized
        // (stranded cursor / cropped desktop). Polling listDisplays() only reads
        // state, so it is safe in this window.
        func promoteMain() {
            guard let effectiveMain else { return }
            var waited = 0.0
            while waited < 6.0
                && !backend.listDisplays().contains(where: { $0.uuid.uppercased() == effectiveMain }) {
                sleepFn(0.5)
                waited += 0.5
            }
            AspaceLog.profile.notice("setMain \(effectiveMain, privacy: .public): waited \(waited, privacy: .public)s for online")
            // Retry setMain: CGCompleteDisplayConfiguration can transiently fail
            // (CGError 1001) while the display system is still settling from the
            // enables/disables. A failed setMain is not fatal to the topology
            // change — warn and move on (the cursor warp still recovers the
            // pointer) rather than aborting the whole switch with an error.
            for attempt in 1...3 {
                do {
                    try backend.setMain(uuid: effectiveMain)
                    AspaceLog.profile.notice("setMain \(effectiveMain, privacy: .public): ok")
                    return
                } catch DisplayKitError.displayNotFound {
                    warn("cannot set main display \(effectiveMain): not currently connected (profile applied without setting main)")
                    return
                } catch {
                    AspaceLog.profile.error("setMain \(effectiveMain, privacy: .public): attempt \(attempt) failed: \(String(describing: error), privacy: .public)")
                    if attempt < 3 { sleepFn(0.5) }
                }
            }
            warn("could not set main display \(effectiveMain) after retries (profile applied without setting main)")
        }

        func disableUnwanted() throws {
            for uuid in toDisable where known.contains(uuid) {
                do {
                    try backend.setEnabled(uuid: uuid, enabled: false)
                    AspaceLog.profile.notice("disable \(uuid, privacy: .public): ok")
                } catch {
                    AspaceLog.profile.error("disable \(uuid, privacy: .public): failed: \(String(describing: error), privacy: .public)")
                    throw RunError.operation("disable \(uuid)", error)
                }
            }
        }

        // A sole survivor (no declared main) must be online before we touch
        // anything; if it never arrives, abort and leave the current displays
        // enabled rather than stranding the session (non-destructive).
        if mainUUID == nil, let survivor = effectiveMain {
            var waited = 0.0
            while waited < 8.0
                && !backend.listDisplays().contains(where: { $0.uuid.uppercased() == survivor }) {
                sleepFn(0.5)
                waited += 0.5
            }
            guard backend.listDisplays().contains(where: { $0.uuid.uppercased() == survivor }) else {
                AspaceLog.profile.error("survivor \(survivor, privacy: .public): never came online after \(waited, privacy: .public)s; leaving current displays enabled")
                warn("profile '\(name)': the target display never came online; left the current displays enabled")
                return
            }
            AspaceLog.profile.notice("survivor \(survivor, privacy: .public): online after \(waited, privacy: .public)s")
        }

        if mainUUID != nil {
            // Declared main (e.g. `desk`): disable the others FIRST, then set the
            // new main. Disabling the outgoing main display (the TV, which is
            // main coming from `treadmill`) while it is still main keeps its HDMI
            // link warm so soft-enable can wake it again later; promoting a new
            // main first leaves the TV cold and un-wakeable.
            try disableUnwanted()
            promoteMain()
        } else {
            // Sole survivor (e.g. `treadmill`): set main on the already-online
            // survivor BEFORE disabling the others. Disabling them can briefly
            // knock a TV offline, so doing setMain first guarantees it takes; the
            // survivor then returns as the sole main display, cursor and menu bar
            // intact. setMain only re-homes the origin, never the mode, so order
            // here does not affect resolution.
            promoteMain()
            try disableUnwanted()
            // Collapsing to one display can leave the pointer stranded off the
            // remaining screen (frozen cursor, error beeps); move it onto the
            // new sole display.
            backend.warpCursorToMainDisplay()
            AspaceLog.profile.notice("warped cursor onto main display")
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
