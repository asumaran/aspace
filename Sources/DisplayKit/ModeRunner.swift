import Foundation
import CoreGraphics

/// Applies a named mode from `AspaceConfig`: enable / disable the listed
/// displays in the order that keeps you from ever ending up with zero
/// active displays (enable first, then disable), then optionally set the
/// chosen main display.
public enum ModeRunner {
    public enum RunError: Error, CustomStringConvertible {
        case modeNotFound(String)
        case operation(String, Error)

        public var description: String {
            switch self {
            case .modeNotFound(let name):
                return "Mode not found in config: \(name)"
            case .operation(let what, let err):
                return "\(what): \(err)"
            }
        }
    }

    public static func run(mode name: String, config: AspaceConfig) throws {
        guard let mode = config.modes[name] else {
            throw RunError.modeNotFound(name)
        }

        for uuid in mode.enable {
            do { try DisplayKit.setEnabled(uuid: uuid, enabled: true) }
            catch { throw RunError.operation("enable \(uuid)", error) }
        }

        // Give the system a moment to register newly enabled displays before
        // we set the main one and pull the rug from under the rest.
        Thread.sleep(forTimeInterval: 1.0)

        if let mainUUID = mode.main {
            do { try DisplayKit.setMain(uuid: mainUUID) }
            catch { throw RunError.operation("main \(mainUUID)", error) }
            Thread.sleep(forTimeInterval: 0.5)
        }

        for uuid in mode.disable {
            do { try DisplayKit.setEnabled(uuid: uuid, enabled: false) }
            catch { throw RunError.operation("disable \(uuid)", error) }
        }
    }
}
