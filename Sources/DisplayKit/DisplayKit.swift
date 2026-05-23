import Foundation
import CoreGraphics
import AppKit
import IOKit
import IOKit.graphics

public enum DisplayKitError: Error, CustomStringConvertible {
    case displayNotFound(String)
    case beginConfigFailed(CGError)
    case operationFailed(String, CGError)

    public var description: String {
        switch self {
        case .displayNotFound(let uuid):
            return "Display not found: \(uuid)"
        case .beginConfigFailed(let err):
            return "CGBeginDisplayConfiguration failed (CGError \(err.rawValue))"
        case .operationFailed(let op, let err):
            return "\(op) failed (CGError \(err.rawValue))"
        }
    }
}

public struct DisplayInfo: Equatable {
    public let id: CGDirectDisplayID
    public let uuid: String
    public let name: String
    public let isEnabled: Bool
    public let isMain: Bool
    public let bounds: CGRect
}

public enum DisplayKit {

    // MARK: - Listing

    /// All displays the system currently sees as online. Disconnected displays
    /// only appear in the persistent registry, not here. Side effect: refreshes
    /// the on-disk UUID→displayID cache for every observed display.
    public static func listDisplays() -> [DisplayInfo] {
        let displays = onlineDisplayIDs().compactMap { id -> DisplayInfo? in
            guard let uuid = uuidString(for: id) else { return nil }
            return DisplayInfo(
                id: id,
                uuid: uuid,
                name: displayName(for: id),
                isEnabled: CGDisplayIsActive(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                bounds: CGDisplayBounds(id)
            )
        }
        var registry = DisplayRegistry.load()
        for d in displays { registry.record(uuid: d.uuid, displayID: d.id) }
        registry.save()
        return displays
    }

    public static func display(forUUID uuid: String) -> DisplayInfo? {
        let target = uuid.uppercased()
        return listDisplays().first { $0.uuid.uppercased() == target }
    }

    // MARK: - Mutations

    /// Connect or disconnect a display by UUID. No-op if the display is
    /// already in the requested state. Caches the displayID before disabling
    /// so a later `enable` can find the (now offline) display.
    public static func setEnabled(uuid: String, enabled: Bool) throws {
        var registry = DisplayRegistry.load()

        let targetID: CGDirectDisplayID
        let isCurrentlyOnline: Bool
        if let live = displayID(forUUID: uuid) {
            targetID = live
            isCurrentlyOnline = true
            registry.record(uuid: uuid, displayID: live)
            registry.save()
        } else if let cached = registry.lookup(uuid: uuid) {
            targetID = cached
            isCurrentlyOnline = false
        } else {
            throw DisplayKitError.displayNotFound(uuid)
        }

        // Skip no-op transitions; CG returns an illegal-argument error if the
        // resulting configuration would not change anything.
        if enabled && isCurrentlyOnline && CGDisplayIsActive(targetID) != 0 { return }
        if !enabled && !isCurrentlyOnline { return }

        try inDisplayConfiguration { config in
            let err = CGSConfigureDisplayEnabled(config, targetID, enabled)
            guard err == .success else {
                throw DisplayKitError.operationFailed("CGSConfigureDisplayEnabled(\(enabled))", err)
            }
        }
    }

    /// Make a display the primary by shifting all displays so the target lands at (0,0).
    public static func setMain(uuid: String) throws {
        guard let targetID = displayID(forUUID: uuid) else {
            throw DisplayKitError.displayNotFound(uuid)
        }
        if CGDisplayIsMain(targetID) != 0 { return }

        let targetBounds = CGDisplayBounds(targetID)
        let dx = -Int32(targetBounds.origin.x)
        let dy = -Int32(targetBounds.origin.y)

        try inDisplayConfiguration { config in
            for id in onlineDisplayIDs() where CGDisplayIsActive(id) != 0 {
                let bounds = CGDisplayBounds(id)
                let newX = Int32(bounds.origin.x) + dx
                let newY = Int32(bounds.origin.y) + dy
                let err = CGConfigureDisplayOrigin(config, id, newX, newY)
                if err != .success {
                    throw DisplayKitError.operationFailed("CGConfigureDisplayOrigin", err)
                }
            }
        }
    }

    // MARK: - Internals

    /// Runs a closure inside a begin/complete display configuration transaction.
    /// On thrown errors the configuration is cancelled.
    private static func inDisplayConfiguration(_ body: (CGDisplayConfigRef) throws -> Void) throws {
        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let config = configRef else {
            throw DisplayKitError.beginConfigFailed(beginErr)
        }

        do {
            try body(config)
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeErr == .success else {
            throw DisplayKitError.operationFailed("CGCompleteDisplayConfiguration", completeErr)
        }
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cf) as String?
    }

    private static func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        let target = uuid.uppercased()
        for id in onlineDisplayIDs() where uuidString(for: id)?.uppercased() == target {
            return id
        }
        return nil
    }

    /// Display name via NSScreen.localizedName — works reliably on Apple Silicon
    /// macOS where the older IODisplayConnect class is no longer populated.
    private static func displayName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[key] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == displayID {
                return screen.localizedName
            }
        }
        return "Unknown"
    }
}
