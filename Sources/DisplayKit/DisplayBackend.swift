import Foundation

/// Surface area `ProfileRunner` needs from the display layer. Factored out
/// so tests (via `@testable import DisplayKit`) can substitute a fake
/// instead of poking real CoreGraphics state.
/// A single enable/disable request, batched with others so the backend can
/// apply them in one display reconfiguration.
struct EnableChange: Equatable {
    let uuid: String
    let enabled: Bool
}

protocol DisplayBackend {
    func listDisplays() -> [DisplayInfo]
    func allKnownUUIDs() -> Set<String>
    func setEnabled(uuid: String, enabled: Bool) throws
    /// Apply several enable/disable changes, coalescing them into as few
    /// display reconfigurations as possible (one flicker instead of one per
    /// display). Returns the UUIDs that did not apply — either not currently
    /// connectable, or a display that reported a configuration error — so the
    /// caller decides skip-vs-fatal. Never throws for a per-display failure.
    func setEnabledBatch(_ changes: [EnableChange]) -> [String]
    func setMain(uuid: String) throws
    func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws
    /// Move the pointer onto the current main display. Recovers a cursor that
    /// was stranded off-screen after collapsing to a single display.
    func warpCursorToMainDisplay()
}

extension DisplayBackend {
    // Cursor warping is a pure side effect with nothing to assert, so tests get
    // a no-op by default.
    func warpCursorToMainDisplay() {}

    /// Default: apply each change on its own. Preserves the exact
    /// skip-vs-fatal semantics of the one-at-a-time path (a per-display failure
    /// becomes an entry in the returned list, never an early abort). The live
    /// backend overrides this to coalesce the changes into a single
    /// CoreGraphics transaction; the fake backend inherits this loop so tests
    /// exercise the same policy.
    func setEnabledBatch(_ changes: [EnableChange]) -> [String] {
        var failed: [String] = []
        for change in changes {
            do {
                try setEnabled(uuid: change.uuid, enabled: change.enabled)
            } catch {
                failed.append(change.uuid.uppercased())
            }
        }
        return failed
    }
}

/// Production backend that delegates to `DisplayKit`'s real CoreGraphics
/// implementations.
struct LiveDisplayBackend: DisplayBackend {
    func listDisplays() -> [DisplayInfo] { DisplayKit.listDisplays() }
    func allKnownUUIDs() -> Set<String> { DisplayKit.allKnownUUIDs() }
    func setEnabled(uuid: String, enabled: Bool) throws {
        try DisplayKit.setEnabled(uuid: uuid, enabled: enabled)
    }
    func setEnabledBatch(_ changes: [EnableChange]) -> [String] {
        let requests = changes.map { (uuid: $0.uuid, enabled: $0.enabled) }
        do {
            // Fast path: one transaction, one reconfiguration. Returns the
            // UUIDs with no resolvable display id (not connected).
            return try DisplayKit.setEnabled(requests)
        } catch {
            // A display in the batch reported a configuration error, which
            // cancels the whole transaction. Fall back to one-at-a-time so a
            // single offline ghost doesn't sink the rest of the switch, and the
            // caller learns exactly which UUIDs failed.
            var failed: [String] = []
            for change in changes {
                do {
                    failed.append(contentsOf: try DisplayKit.setEnabled([(change.uuid, change.enabled)]))
                } catch {
                    failed.append(change.uuid.uppercased())
                }
            }
            return failed
        }
    }
    func setMain(uuid: String) throws { try DisplayKit.setMain(uuid: uuid) }
    func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws {
        try DisplayKit.setMode(uuid: uuid, spec: spec)
    }
    func warpCursorToMainDisplay() { DisplayKit.warpCursorToMainDisplay() }
}
