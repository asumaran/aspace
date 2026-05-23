import Foundation
import CoreGraphics

/// Applies a profile by name. Built-in `"all"` enables every UUID we have ever
/// observed (from `DisplayRegistry`) and disables nothing. Named profiles in
/// the config enable everything in `active` and disable every other known
/// UUID, then optionally set the main display.
public enum ProfileRunner {
    public enum RunError: Error, CustomStringConvertible {
        case profileNotFound(String)
        case operation(String, Error)

        public var description: String {
            switch self {
            case .profileNotFound(let name):
                return "Profile not found in config: \(name)"
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
        // 1) Figure out which UUIDs should end up active and which off.
        let known = knownUUIDs()
        let toActivate: Set<String>
        let mainUUID: String?

        if name == AspaceConfig.allProfileName {
            toActivate = known
            mainUUID = nil
        } else if let profile = config.profiles[name] {
            toActivate = Set(profile.active.map { $0.uppercased() })
            mainUUID = profile.main
        } else {
            throw RunError.profileNotFound(name)
        }

        let toDeactivate = known.subtracting(toActivate)

        // 2) Enable first so we never end up with zero active displays.
        for uuid in toActivate {
            do { try DisplayKit.setEnabled(uuid: uuid, enabled: true) }
            catch { throw RunError.operation("enable \(uuid)", error) }
        }

        // Let the system register the newly enabled displays before we
        // reassign the main one and pull the rug from under the rest.
        Thread.sleep(forTimeInterval: 1.0)

        if let mainUUID = mainUUID {
            do { try DisplayKit.setMain(uuid: mainUUID) }
            catch { throw RunError.operation("main \(mainUUID)", error) }
            Thread.sleep(forTimeInterval: 0.5)
        }

        for uuid in toDeactivate {
            do { try DisplayKit.setEnabled(uuid: uuid, enabled: false) }
            catch { throw RunError.operation("disable \(uuid)", error) }
        }
    }

    /// Every UUID we've ever observed (currently online or cached from a
    /// previous session). The cache is also refreshed as a side effect of
    /// calling `DisplayKit.listDisplays`, so this stays accurate over time.
    private static func knownUUIDs() -> Set<String> {
        let live = Set(DisplayKit.listDisplays().map { $0.uuid.uppercased() })
        let cached = Set(DisplayRegistry.load().entries.keys.map { $0.uppercased() })
        return live.union(cached)
    }
}
