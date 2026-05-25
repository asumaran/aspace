import Foundation

/// Surface area `ProfileRunner` (and anything else higher-level) needs from
/// the display layer. Factored out so tests can substitute a fake instead
/// of poking real CoreGraphics state.
public protocol DisplayBackend {
    func listDisplays() -> [DisplayInfo]
    func allKnownUUIDs() -> Set<String>
    func setEnabled(uuid: String, enabled: Bool) throws
    func setMain(uuid: String) throws
}

/// Production backend that delegates to `DisplayKit`'s real CoreGraphics
/// implementations.
public struct LiveDisplayBackend: DisplayBackend {
    public init() {}
    public func listDisplays() -> [DisplayInfo] { DisplayKit.listDisplays() }
    public func allKnownUUIDs() -> Set<String> { DisplayKit.allKnownUUIDs() }
    public func setEnabled(uuid: String, enabled: Bool) throws {
        try DisplayKit.setEnabled(uuid: uuid, enabled: enabled)
    }
    public func setMain(uuid: String) throws { try DisplayKit.setMain(uuid: uuid) }
}
