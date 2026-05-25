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

    /// Operations recorded in the order the runner invoked them.
    private(set) var ops: [Op] = []

    init(online: Set<String> = [], known: Set<String>? = nil) {
        self.online = online
        self.known = known ?? online
    }

    func listDisplays() -> [DisplayInfo] {
        online.sorted().map { uuid in
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
            online.insert(key)
            known.insert(key)
        } else {
            online.remove(key)
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
}
