import Foundation
import AppKit
import CoreGraphics
import DisplayKit

/// View-model for the menu bar app. Holds the displays / config snapshot
/// that the menu renders against, listens to CoreGraphics display
/// reconfiguration events, and exposes intent methods (`applyProfile`,
/// `openConfigFolder`, etc.) that the view calls.
@MainActor
final class AspaceModel: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    /// Online displays plus config-referenced displays that are offline now,
    /// for the menu's "Displays" section. Derived from `displays` + `config`.
    @Published private(set) var displayRows: [DisplayKit.DisplayStatusRow] = []
    @Published private(set) var config: AspaceConfig = AspaceConfig(profiles: [:])
    @Published private(set) var activeProfile: String?
    @Published private(set) var activeResolution: String?
    @Published private(set) var cliVersion: String?

    /// The most recently active resolution preset. Profiles only change
    /// topology, and macOS brings re-enabled displays back at inconsistent
    /// default modes, so switching back to `desk` loses the preset. We remember
    /// the last active preset and re-assert it after a profile switch (see
    /// `scheduleResolutionRestore`). Persisted; only ever set to a real preset,
    /// so it carries across a `treadmill` state that matches none.
    @Published private(set) var lastResolution: String?
    private static let lastResolutionKey = "aspace.lastResolution"
    private var resolutionRestoreTask: Task<Void, Never>?

    init() {
        lastResolution = UserDefaults.standard.string(forKey: Self.lastResolutionKey)
        registerForDisplayChanges()
        refresh()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Derived state

    /// SF Symbol name for the menu bar icon, picked from the active profile.
    var statusSymbolName: String {
        switch activeProfile {
        case "treadmill":                   return "figure.walk"
        case "desk":                        return "display"
        case AspaceConfig.allProfileName:   return "display.2"
        default:                            return "rectangle.on.rectangle.slash"
        }
    }

    var statusTooltip: String {
        activeProfile.map { "aspace — \($0)" } ?? "aspace"
    }

    var availableProfileNames: [String] {
        ProfileRunner.availableProfileNames(config: config)
    }

    var availableResolutionNames: [String] {
        ResolutionRunner.availablePresetNames(config: config)
    }

    /// A preset applies when at least one of its displays is currently
    /// connected. The menu dims presets that target only offline displays
    /// (e.g. the desk presets while on the treadmill profile), since applying
    /// them would be a no-op.
    func isResolutionApplicable(_ name: String) -> Bool {
        let online = Set(displays.filter { $0.isEnabled }.map { $0.uuid })
        return ResolutionState.applicablePresets(online: online, in: config.resolutions).contains(name)
    }

    var versionMismatchMessage: String? {
        guard let cli = cliVersion, cli != AspaceVersion.current else { return nil }
        return "CLI version mismatch — click for details"
    }

    // MARK: - Actions

    func refresh() {
        config = AspaceConfig.loadOrEmpty()
        displays = DisplayKit.listDisplays()
        displayRows = DisplayKit.displayStatus(online: displays, config: config)
        activeProfile = Self.detectActiveProfile(displays: displays, config: config)
        activeResolution = Self.detectActiveResolution(displays: displays, config: config)
        if let active = activeResolution { rememberResolution(active) }
        cliVersion = Self.detectCLIVersion()
        logTopology()
    }

    private func rememberResolution(_ name: String) {
        guard name != lastResolution else { return }
        lastResolution = name
        UserDefaults.standard.set(name, forKey: Self.lastResolutionKey)
    }

    private var lastTopologySignature: String?

    /// Per-display snapshot of the settled state (it runs from `refresh`, after
    /// the apply delay). Read-only — never reconfigures — so it is safe to emit
    /// even right after a topology change. Deduplicated: macOS fires many
    /// reconfiguration callbacks per switch, so it only logs when the topology
    /// actually changed. Read it with `Scripts/logs.sh`.
    private func logTopology() {
        var rows: [String] = []
        var signature = "\(activeProfile ?? "custom")/\(activeResolution ?? "custom")"
        for d in displays {
            let mode = DisplayKit.currentMode(uuid: d.uuid)
            let res = mode.map { "\($0.pointWidth)x\($0.pointHeight)" } ?? "?"
            signature += "|\(d.uuid):\(d.isMain):\(d.isEnabled):\(res)"
            rows.append("  \(d.isMain ? "*" : "-") \(d.name) [\(d.uuid)] enabled=\(d.isEnabled) mode=\(res)")
        }
        guard signature != lastTopologySignature else { return }
        lastTopologySignature = signature

        AspaceLog.app.notice("""
            topology: profile=\(self.activeProfile ?? "custom", privacy: .public) \
            resolution=\(self.activeResolution ?? "custom", privacy: .public) \
            online=\(self.displays.count)
            """)
        for row in rows {
            AspaceLog.app.notice("\(row, privacy: .public)")
        }
    }

    func applyProfile(_ name: String) {
        AspaceLog.app.notice("applyProfile '\(name, privacy: .public)' requested")
        do {
            try ProfileRunner.run(profile: name, config: config)
        } catch {
            presentError("Failed to apply profile '\(name)': \(error)")
        }
        scheduleResolutionRestore(afterProfile: name)
        // The reconfig callback will fire and refresh, but call it explicitly
        // in case the callback is delayed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    /// After a profile switch, re-assert the last resolution preset so returning
    /// to a topology (e.g. `desk`) also restores the resolution you had. Safe by
    /// construction: it does nothing when the profile disables the preset's
    /// displays (e.g. `treadmill` turning the desk monitors off), and it defers
    /// the `setMode` until those displays are back online and settled — never
    /// touching them in the volatile window right after a topology change, which
    /// is what destabilized an earlier, eager version.
    private func scheduleResolutionRestore(afterProfile profileName: String) {
        resolutionRestoreTask?.cancel()
        guard let preset = lastResolution,
              let spec = config.resolutions[preset], !spec.isEmpty else { return }
        let targets = Set(spec.keys.map { $0.uppercased() })
        let disabled = Set((config.profiles[profileName]?.disable ?? []).map { $0.uppercased() })
        guard targets.isDisjoint(with: disabled) else {
            AspaceLog.app.notice("resolution restore '\(preset, privacy: .public)': skipped (profile '\(profileName, privacy: .public)' disables its displays)")
            return
        }

        resolutionRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait for every target display to come back online (a re-enabled
            // display can lag), then settle briefly before touching modes.
            var waited = 0.0
            while waited < 6.0 {
                let online = Set(DisplayKit.listDisplays().map { $0.uuid.uppercased() })
                if targets.isSubset(of: online) { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 0.5
            }
            if Task.isCancelled { return }
            let online = Set(DisplayKit.listDisplays().map { $0.uuid.uppercased() })
            guard targets.isSubset(of: online) else {
                AspaceLog.app.notice("resolution restore '\(preset, privacy: .public)': skipped (targets not all online after \(waited, privacy: .public)s)")
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            AspaceLog.app.notice("resolution restore '\(preset, privacy: .public)': reapplying")
            do {
                try ResolutionRunner.run(preset: preset, config: self.config)
            } catch {
                AspaceLog.app.error("resolution restore '\(preset, privacy: .public)' failed: \(String(describing: error), privacy: .public)")
            }
            self.refresh()
        }
    }

    func applyResolution(_ name: String) {
        AspaceLog.app.notice("applyResolution '\(name, privacy: .public)' requested")
        do {
            try ResolutionRunner.run(preset: name, config: config)
            rememberResolution(name)
        } catch {
            presentError("Failed to apply resolution preset '\(name)': \(error)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func openConfigFolder() {
        let dir = AspaceConfig.storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "aspace \(AspaceVersion.current)"
        alert.informativeText = "https://github.com/asumaran/aspace"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showVersionMismatchAlert() {
        guard let cli = cliVersion else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "aspace CLI / App version mismatch"
        alert.informativeText = """
            App:  \(AspaceVersion.current)
            CLI:  \(cli)

            Both should be the same version to guarantee compatibility on
            the shared files in ~/.config/aspace. Reinstall the older one
            or update both to the same release.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Internals

    private func presentError(_ message: String) {
        AspaceLog.app.error("\(message, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "aspace error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func registerForDisplayChanges() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, opaque)
    }

    /// A profile matches when the displays it lists as `disable` are exactly
    /// the ones currently offline / disabled. The built-in "all" matches when
    /// every managed display is online. Delegates to the tested pure helper,
    /// which ignores unmanaged registry "ghosts" so they can't force "custom".
    private static func detectActiveProfile(displays: [DisplayInfo], config: AspaceConfig) -> String? {
        let online = Set(displays.map { $0.uuid.uppercased() })
        return DisplayKit.activeProfileName(online: online, config: config)
    }

    /// A preset is active when every display it lists that is currently online
    /// is already at the preset's resolution. Offline displays in the preset
    /// are ignored so a preset still reads as active with a monitor unplugged.
    private static func detectActiveResolution(displays: [DisplayInfo], config: AspaceConfig) -> String? {
        var current: [String: AspaceConfig.ModeSpec] = [:]
        for d in displays where d.isEnabled {
            if let m = DisplayKit.currentMode(uuid: d.uuid) {
                current[d.uuid] = AspaceConfig.ModeSpec(pointWidth: m.pointWidth, pointHeight: m.pointHeight)
            }
        }
        return ResolutionState.activePreset(current: current, in: config.resolutions)
    }

    /// Probe the `aspace` CLI in the usual install paths and ask for its
    /// version. Used to surface mismatches in the menu.
    private static func detectCLIVersion() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/aspace").path,
            "/opt/homebrew/bin/aspace",
            "/usr/local/bin/aspace",
        ]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["version"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let v = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty ?? true) ? nil : v
        } catch {
            return nil
        }
    }
}

// MARK: - C callback trampoline

/// CoreGraphics calls this from an arbitrary queue when the display layout
/// changes (display attached/detached, mirroring change, resolution change,
/// etc.). We hop to the main actor and refresh the model.
private func displayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    AspaceLog.app.notice("reconfig event: display=\(display) flags=0x\(String(flags.rawValue, radix: 16), privacy: .public)")
    let model = Unmanaged<AspaceModel>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor in
        model.refresh()
    }
}
