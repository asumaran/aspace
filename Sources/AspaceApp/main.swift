import Foundation
import AppKit
import CoreGraphics
import DisplayKit

// MARK: - Display reconfiguration callback (trampolines into the delegate)

private func displayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        (NSApp.delegate as? AppDelegate)?.refresh()
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.autoenablesItems = false
        statusItem.menu = menu

        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
    }

    // MARK: - State

    private struct State {
        let config: AspaceConfig
        let displays: [DisplayInfo]
        let activeProfile: String?
        let cliVersion: String?
    }

    private func currentState() -> State {
        let config = AspaceConfig.loadOrEmpty()
        let displays = DisplayKit.listDisplays()
        let activeProfile = detectActiveProfile(displays: displays, config: config)
        return State(
            config: config,
            displays: displays,
            activeProfile: activeProfile,
            cliVersion: detectCLIVersion()
        )
    }

    /// Locates an `aspace` CLI in the usual install paths and asks it for
    /// its version. Returns nil if no CLI is found or if the call fails.
    private func detectCLIVersion() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/aspace").path,
            "/opt/homebrew/bin/aspace",
            "/usr/local/bin/aspace",
        ]
        let binary = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let binary = binary else { return nil }

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

    /// A profile matches when the displays it lists as `disable` are exactly
    /// the ones currently offline / disabled (among everything aspace knows
    /// about). The built-in "all" matches when nothing known is offline.
    private func detectActiveProfile(displays: [DisplayInfo], config: AspaceConfig) -> String? {
        let known = DisplayKit.allKnownUUIDs()
        let online = Set(displays.map { $0.uuid.uppercased() })
        let offline = known.subtracting(online)

        for (name, profile) in config.profiles {
            let configured = Set(profile.disable.map { $0.uppercased() }).intersection(known)
            if configured == offline { return name }
        }

        if offline.isEmpty && !known.isEmpty {
            return AspaceConfig.allProfileName
        }
        return nil
    }

    // MARK: - Rendering

    func refresh() {
        let state = currentState()
        renderStatusIcon(activeProfile: state.activeProfile)
        renderMenu(state: state)
    }

    private func renderStatusIcon(activeProfile: String?) {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch activeProfile {
        case "treadmill":                   symbolName = "figure.walk"
        case "desk":                        symbolName = "display"
        case AspaceConfig.allProfileName:   symbolName = "display.2"
        default:                            symbolName = "rectangle.on.rectangle.slash"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "aspace")
        image?.isTemplate = true
        button.image = image
        button.toolTip = activeProfile.map { "aspace — \($0)" } ?? "aspace"
    }

    private func renderMenu(state: State) {
        menu.removeAllItems()

        // Version mismatch warning (only when CLI version differs from app)
        if let cli = state.cliVersion, cli != AspaceVersion.current {
            let warning = NSMenuItem(
                title: "CLI version mismatch — click for details",
                action: #selector(showVersionMismatch),
                keyEquivalent: ""
            )
            warning.target = self
            warning.representedObject = cli
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        // Current profile header
        let header = NSMenuItem(
            title: "Profile: \(state.activeProfile ?? "custom")",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // Profile switches
        let profileNames = ProfileRunner.availableProfileNames(config: state.config)
        for name in profileNames {
            let title = name == AspaceConfig.allProfileName
                ? "Reconnect all displays"
                : "Switch to \(name)"
            let item = NSMenuItem(title: title, action: #selector(runProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            if state.activeProfile == name {
                item.state = .on
            }
            menu.addItem(item)
        }

        if state.config.profiles.isEmpty {
            let item = NSMenuItem(title: "(Edit config.json to add profiles)", action: #selector(openConfigDir), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Display list
        let displaysHeader = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        displaysHeader.isEnabled = false
        menu.addItem(displaysHeader)
        for d in state.displays {
            let mark = d.isEnabled ? "●" : "○"
            let mainTag = d.isMain ? " (main)" : ""
            let line = "  \(mark) \(d.name)\(mainTag)"
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let configItem = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigDir), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About aspace (\(AspaceVersion.current))",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit aspace", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func runProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let config = AspaceConfig.loadOrEmpty()
        do {
            try ProfileRunner.run(profile: name, config: config)
        } catch {
            presentError("Failed to apply profile '\(name)': \(error)")
        }
        // refresh() will also be triggered by the display reconfiguration
        // callback, but call it explicitly in case the callback is delayed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func openConfigDir() {
        let dir = AspaceConfig.storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "aspace error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "aspace \(AspaceVersion.current)"
        alert.informativeText = "https://github.com/asumaran/aspace"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showVersionMismatch(_ sender: NSMenuItem) {
        guard let cli = sender.representedObject as? String else { return }
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
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
