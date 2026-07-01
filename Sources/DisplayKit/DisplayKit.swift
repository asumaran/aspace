import Foundation
import CoreGraphics
import AppKit
import IOKit
import IOKit.graphics

public enum DisplayKitError: Error, CustomStringConvertible {
    case displayNotFound(String)
    case beginConfigFailed(CGError)
    case operationFailed(String, CGError)
    case modeNotAvailable(uuid: String, spec: String)

    public var description: String {
        switch self {
        case .displayNotFound(let uuid):
            return "Display not found: \(uuid)"
        case .beginConfigFailed(let err):
            return "CGBeginDisplayConfiguration failed (CGError \(err.rawValue))"
        case .operationFailed(let op, let err):
            return "\(op) failed (CGError \(err.rawValue))"
        case .modeNotAvailable(let uuid, let spec):
            return "No \(spec) display mode available for \(uuid)"
        }
    }
}

/// A single display mode in value form. `pointWidth/Height` is the "looks
/// like" size shown in System Settings; `pixelWidth/Height` is the framebuffer
/// resolution. The `ref` handle is the live CoreGraphics mode used to apply it
/// and is nil in synthetic (test) instances — the matcher never reads it.
public struct DisplayMode: Equatable {
    public let pointWidth: Int
    public let pointHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshHz: Double
    public let isSafe: Bool
    let ref: CGDisplayMode?

    /// True for retina modes (framebuffer at least 2x the point size).
    public var isHiDPI: Bool { pointWidth > 0 && pixelWidth / pointWidth >= 2 }

    public init(pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int,
                refreshHz: Double, isSafe: Bool) {
        self.init(pointWidth: pointWidth, pointHeight: pointHeight,
                  pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                  refreshHz: refreshHz, isSafe: isSafe, ref: nil)
    }

    init(pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int,
         refreshHz: Double, isSafe: Bool, ref: CGDisplayMode?) {
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.isSafe = isSafe
        self.ref = ref
    }

    public static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
        lhs.pointWidth == rhs.pointWidth && lhs.pointHeight == rhs.pointHeight
            && lhs.pixelWidth == rhs.pixelWidth && lhs.pixelHeight == rhs.pixelHeight
            && lhs.refreshHz == rhs.refreshHz && lhs.isSafe == rhs.isSafe
    }
}

/// Picks the concrete display mode that best satisfies a desired point size.
/// A single point size (e.g. 2560x1440) maps to several modes that differ in
/// scaling (HiDPI vs 1:1), refresh rate, and IOKit flags; this resolves that
/// ambiguity deterministically. Pure and value-based so it is unit-testable
/// without touching CoreGraphics.
public enum DisplayModeMatcher {
    /// Best match for `spec`, or nil if no mode has that point size.
    /// Preference order: HiDPI over 1:1, higher refresh, then safe modes.
    public static func best(for spec: AspaceConfig.ModeSpec, in modes: [DisplayMode]) -> DisplayMode? {
        let candidates = modes.filter {
            $0.pointWidth == spec.pointWidth && $0.pointHeight == spec.pointHeight
        }
        // `max(by:)` keeps the greatest element; the closure returns true when
        // `a` is the worse (lesser) of the two.
        return candidates.max { a, b in
            if a.isHiDPI != b.isHiDPI { return !a.isHiDPI }
            if a.refreshHz != b.refreshHz { return a.refreshHz < b.refreshHz }
            if a.isSafe != b.isSafe { return !a.isSafe }
            return false
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
        for d in displays { registry.record(uuid: d.uuid, displayID: d.id, name: d.name) }
        registry.save()
        return displays
    }

    public static func display(forUUID uuid: String) -> DisplayInfo? {
        let target = uuid.uppercased()
        return listDisplays().first { $0.uuid.uppercased() == target }
    }

    // MARK: - Display status (menu)

    /// One row of the menu's "Displays" section: a display that is either online
    /// now or known-but-disconnected. `🟢`/`⚪️` in the UI map to `isActive`.
    public struct DisplayStatusRow: Equatable {
        public enum Connection: Equatable {
            /// Reported online by CoreGraphics. `isEnabled` is false for the rare
            /// online-but-inactive case (e.g. mirrored), which still shows ⚪️.
            case online(isEnabled: Bool, isMain: Bool)
            /// Not online now; surfaced from the registry because the user's
            /// config references it.
            case offline
        }

        public let uuid: String
        public let name: String
        public let connection: Connection

        public init(uuid: String, name: String, connection: Connection) {
            self.uuid = uuid
            self.name = name
            self.connection = connection
        }

        /// True only for an online display that is actively driving pixels.
        public var isActive: Bool {
            if case .online(let isEnabled, _) = connection { return isEnabled }
            return false
        }

        public var isMain: Bool {
            if case .online(_, let isMain) = connection { return isMain }
            return false
        }

        public var isOnline: Bool {
            if case .online = connection { return true }
            return false
        }
    }

    /// Builds the menu's "Displays" list: every currently-online display, plus
    /// any display referenced by the user's config that is offline right now, so
    /// known-but-disconnected screens still appear. Offline rows are named from
    /// the registry; an offline display with no recorded name is skipped (we'd
    /// have nothing meaningful to show). Order: online first (main, then by
    /// name), then offline by name. Pure — callers supply the inputs.
    public static func displayStatusRows(
        online: [DisplayInfo],
        configuredUUIDs: [String],
        registryNames: [String: String]
    ) -> [DisplayStatusRow] {
        let onlineUUIDs = Set(online.map { $0.uuid.uppercased() })

        let onlineRows = online.map { d in
            DisplayStatusRow(
                uuid: d.uuid,
                name: d.name,
                connection: .online(isEnabled: d.isEnabled, isMain: d.isMain)
            )
        }

        var seen = Set<String>()
        var offlineRows: [DisplayStatusRow] = []
        for raw in configuredUUIDs {
            let key = raw.uppercased()
            if onlineUUIDs.contains(key) { continue }
            guard seen.insert(key).inserted else { continue }
            guard let name = registryNames[key], !name.isEmpty else { continue }
            offlineRows.append(DisplayStatusRow(uuid: key, name: name, connection: .offline))
        }

        let sortedOnline = onlineRows.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let sortedOffline = offlineRows.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return sortedOnline + sortedOffline
    }

    /// Convenience wrapper over `displayStatusRows` that pulls names from the
    /// persistent registry. Takes an already-fetched `online` list to avoid a
    /// second CoreGraphics round-trip.
    public static func displayStatus(online: [DisplayInfo], config: AspaceConfig) -> [DisplayStatusRow] {
        let registry = DisplayRegistry.load()
        var registryNames: [String: String] = [:]
        for (uuid, entry) in registry.entries {
            if let name = entry.name, !name.isEmpty {
                registryNames[uuid.uppercased()] = name
            }
        }
        return displayStatusRows(
            online: online,
            configuredUUIDs: Array(config.referencedDisplayUUIDs),
            registryNames: registryNames
        )
    }

    /// Name of the profile whose topology matches `online`, or nil ("custom")
    /// when none does. The comparison universe is the union of every profile's
    /// `disable` list — the displays profiles actually toggle — NOT every UUID
    /// the registry has ever seen. That way a display that is offline but
    /// unmanaged (a stale registry "ghost", or one referenced only by a
    /// resolution preset) can't prevent a match.
    ///
    /// A profile is a candidate when none of the displays it disables are still
    /// online (all of its `disable` set is offline). Extra offline displays it
    /// does not manage — e.g. a clamshelled built-in — do not disqualify it, so
    /// `desk` still reads as `desk` with the laptop lid closed. Among candidates
    /// the most specific wins (the one disabling the most displays best explains
    /// the offline set). A profile whose disabled displays are actually still on
    /// never matches. The built-in "all" matches when every universe display is
    /// online. Pure.
    public static func activeProfileName(online: Set<String>, config: AspaceConfig) -> String? {
        var universe = Set<String>()
        for profile in config.profiles.values {
            for uuid in profile.disable { universe.insert(uuid.uppercased()) }
        }
        guard !universe.isEmpty else { return nil }

        let onlineUpper = Set(online.map { $0.uppercased() })
        let offline = universe.subtracting(onlineUpper)

        var best: (name: String, disabledCount: Int)?
        for name in config.profiles.keys.sorted() {
            let disabled = Set((config.profiles[name]?.disable ?? []).map { $0.uppercased() })
            guard !disabled.isEmpty, disabled.isSubset(of: offline) else { continue }
            if best == nil || disabled.count > best!.disabledCount {
                best = (name, disabled.count)
            }
        }
        if let best { return best.name }
        if offline.isEmpty {
            return AspaceConfig.allProfileName
        }
        return nil
    }

    /// All UUIDs aspace has ever observed (currently online plus anything
    /// cached from a previous session). Useful for callers that need to
    /// reason about disabled / disconnected displays.
    public static func allKnownUUIDs() -> Set<String> {
        let live = Set(listDisplays().map { $0.uuid.uppercased() })
        let cached = Set(DisplayRegistry.load().entries.keys.map { $0.uppercased() })
        return live.union(cached)
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
            registry.record(uuid: uuid, displayID: live, name: displayName(for: live))
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

    /// Warp the pointer to the center of the current main display. Collapsing to
    /// a single display can leave the cursor stranded at a coordinate that no
    /// longer maps to any active screen (frozen pointer, error beeps on
    /// keypress); moving it onto the display recovers it.
    public static func warpCursorToMainDisplay() {
        let mainID = CGMainDisplayID()
        let bounds = CGDisplayBounds(mainID)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CGWarpMouseCursorPosition(center)
        // Re-couple the hardware mouse to the on-screen cursor; a warp alone can
        // leave them dissociated.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Display modes

    /// The mode a display is currently running, or nil if the UUID is not
    /// online.
    public static func currentMode(uuid: String) -> DisplayMode? {
        guard let id = displayID(forUUID: uuid),
              let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return makeDisplayMode(mode)
    }

    /// Every mode the given display reports, in CoreGraphics' order. Empty if
    /// the UUID is not currently online.
    public static func modes(uuid: String) -> [DisplayMode] {
        guard let id = displayID(forUUID: uuid) else { return [] }
        return allModes(for: id)
    }

    /// Switches a display to the best mode matching the requested point size.
    /// Throws `displayNotFound` if the UUID is offline and `modeNotAvailable`
    /// if the panel reports no mode at that size. No-op if already there.
    public static func setMode(uuid: String, spec: AspaceConfig.ModeSpec) throws {
        guard let id = displayID(forUUID: uuid) else {
            throw DisplayKitError.displayNotFound(uuid)
        }
        let modes = allModes(for: id)
        guard let chosen = DisplayModeMatcher.best(for: spec, in: modes), let ref = chosen.ref else {
            throw DisplayKitError.modeNotAvailable(uuid: uuid, spec: spec.stringValue)
        }
        if let current = CGDisplayCopyDisplayMode(id),
           current.width == ref.width, current.height == ref.height,
           current.pixelWidth == ref.pixelWidth, current.pixelHeight == ref.pixelHeight,
           current.refreshRate == ref.refreshRate {
            return
        }
        try inDisplayConfiguration { config in
            let err = CGConfigureDisplayWithDisplayMode(config, id, ref, nil)
            guard err == .success else {
                throw DisplayKitError.operationFailed("CGConfigureDisplayWithDisplayMode", err)
            }
        }
    }

    /// kDisplayModeSafeFlag from <IOKit/graphics/IOGraphicsTypes.h>.
    private static let safeModeFlag: UInt32 = 0x2

    private static func makeDisplayMode(_ m: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            pointWidth: m.width,
            pointHeight: m.height,
            pixelWidth: m.pixelWidth,
            pixelHeight: m.pixelHeight,
            refreshHz: m.refreshRate,
            isSafe: (m.ioFlags & safeModeFlag) != 0,
            ref: m
        )
    }

    private static func allModes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue!] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }
        return raw.map(makeDisplayMode)
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
