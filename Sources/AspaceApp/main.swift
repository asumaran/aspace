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
        let activeMode: String?
    }

    private func currentState() -> State {
        let config = AspaceConfig.loadOrEmpty()
        let displays = DisplayKit.listDisplays()
        let activeMode = detectActiveMode(displays: displays, config: config)
        return State(config: config, displays: displays, activeMode: activeMode)
    }

    /// A mode is "active" when every UUID it expects enabled is enabled AND
    /// every UUID it expects disabled is offline / disabled.
    private func detectActiveMode(displays: [DisplayInfo], config: AspaceConfig) -> String? {
        let enabledUUIDs = Set(displays.filter { $0.isEnabled }.map { $0.uuid.uppercased() })

        for (name, mode) in config.modes {
            let mustOn = Set(mode.enable.map { $0.uppercased() })
            let mustOff = Set(mode.disable.map { $0.uppercased() })
            if mustOn.isSubset(of: enabledUUIDs) && enabledUUIDs.isDisjoint(with: mustOff) {
                return name
            }
        }
        return nil
    }

    // MARK: - Rendering

    func refresh() {
        let state = currentState()
        renderStatusIcon(activeMode: state.activeMode)
        renderMenu(state: state)
    }

    private func renderStatusIcon(activeMode: String?) {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch activeMode {
        case "treadmill": symbolName = "figure.walk"
        case "desk":      symbolName = "display"
        default:          symbolName = "display.2"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "aspace")
        image?.isTemplate = true
        button.image = image
        button.toolTip = activeMode.map { "aspace — \($0)" } ?? "aspace"
    }

    private func renderMenu(state: State) {
        menu.removeAllItems()

        // Current mode header
        let header = NSMenuItem(
            title: "Mode: \(state.activeMode ?? "custom")",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // Mode switches
        if state.config.modes.isEmpty {
            let item = NSMenuItem(title: "No modes configured", action: #selector(openConfigDir), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            for name in state.config.modes.keys.sorted() {
                let title = "Switch to \(name)"
                let item = NSMenuItem(title: title, action: #selector(runMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                if state.activeMode == name {
                    item.state = .on
                }
                menu.addItem(item)
            }
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

        let quit = NSMenuItem(title: "Quit aspace", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func runMode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let config = AspaceConfig.loadOrEmpty()
        do {
            try ModeRunner.run(mode: name, config: config)
        } catch {
            presentError("Failed to apply mode '\(name)': \(error)")
        }
        // refresh() will be triggered by the display reconfiguration callback,
        // but call it explicitly too in case the callback is delayed.
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
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
