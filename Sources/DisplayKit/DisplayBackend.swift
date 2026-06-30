import Foundation

/// Surface area `ProfileRunner` needs from the display layer. Factored out
/// so tests (via `@testable import DisplayKit`) can substitute a fake
/// instead of poking real CoreGraphics state.
protocol DisplayBackend {
    func listDisplays() -> [DisplayInfo]
    func allKnownUUIDs() -> Set<String>
    func setEnabled(uuid: String, enabled: Bool) throws
    func setMain(uuid: String) throws
    func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws
}

/// Production backend that delegates to `DisplayKit`'s real CoreGraphics
/// implementations.
struct LiveDisplayBackend: DisplayBackend {
    func listDisplays() -> [DisplayInfo] { DisplayKit.listDisplays() }
    func allKnownUUIDs() -> Set<String> { DisplayKit.allKnownUUIDs() }
    func setEnabled(uuid: String, enabled: Bool) throws {
        try DisplayKit.setEnabled(uuid: uuid, enabled: enabled)
    }
    func setMain(uuid: String) throws { try DisplayKit.setMain(uuid: uuid) }
    func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws {
        try DisplayKit.setMode(uuid: uuid, spec: spec)
    }
}
