import Foundation
import CoreGraphics
@testable import DisplayKit

/// In-memory `DisplayBackend` used to drive ProfileRunner without touching
/// real CoreGraphics state. Tracks every mutation so tests can assert on
/// the exact sequence the runner executed.
final class FakeBackend: DisplayBackend {
    enum Op: Equatable {
        case enable(String)
        case disable(String)
        case setMain(String)
        case setMode(String, String)
    }

    enum Failure: Error, Equatable {
        case enableShouldFail(String)
        case mainShouldFail(String)
    }

    /// UUIDs the backend reports as currently online (in `listDisplays`).
    var online: Set<String>

    /// UUIDs aspace has observed at some point — superset of `online`.
    var known: Set<String>

    /// UUIDs whose enable call should throw (simulates stale cached id).
    var enableFailures: Set<String> = []

    /// If non-nil, setMain throws this error for the given UUID.
    var mainFailure: (uuid: String, error: Error)?

    /// UUIDs whose setMode call reports the mode as unavailable.
    var modeUnavailable: Set<String> = []

    /// UUIDs that, once enabled, only appear online after being polled by
    /// `listDisplays()` this many times (simulates a display that lags coming
    /// online, e.g. a TV negotiating over HDMI).
    var lagOnlinePolls: [String: Int] = [:]
    private var lagPending: [String: Int] = [:]

    /// Operations recorded in the order the runner invoked them.
    private(set) var ops: [Op] = []

    init(online: Set<String> = [], known: Set<String>? = nil) {
        self.online = online
        self.known = known ?? online
    }

    func listDisplays() -> [DisplayInfo] {
        for (uuid, remaining) in lagPending {
            if remaining <= 0 {
                online.insert(uuid)
                lagPending[uuid] = nil
            } else {
                lagPending[uuid] = remaining - 1
            }
        }
        return online.sorted().map { uuid in
            DisplayInfo(
                id: 0,
                uuid: uuid,
                name: uuid,
                isEnabled: true,
                isMain: false,
                bounds: .zero
            )
        }
    }

    func allKnownUUIDs() -> Set<String> {
        known
    }

    func setEnabled(uuid: String, enabled: Bool) throws {
        let key = uuid.uppercased()
        if enableFailures.contains(key) {
            throw Failure.enableShouldFail(key)
        }
        ops.append(enabled ? .enable(key) : .disable(key))
        if enabled {
            known.insert(key)
            if let polls = lagOnlinePolls[key] {
                lagPending[key] = polls          // not online until polled enough
            } else {
                online.insert(key)
            }
        } else {
            online.remove(key)
            lagPending[key] = nil
        }
    }

    func setMain(uuid: String) throws {
        let key = uuid.uppercased()
        if let failure = mainFailure, failure.uuid.uppercased() == key {
            throw failure.error
        }
        if !online.contains(key) {
            throw DisplayKitError.displayNotFound(key)
        }
        ops.append(.setMain(key))
    }

    func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws {
        let key = uuid.uppercased()
        if !online.contains(key) {
            throw DisplayKitError.displayNotFound(key)
        }
        if modeUnavailable.contains(key) {
            throw DisplayKitError.modeNotAvailable(uuid: key, spec: spec.stringValue)
        }
        ops.append(.setMode(key, spec.stringValue))
    }
}
