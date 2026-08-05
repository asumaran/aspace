import AppKit
import Combine
import DisplayKit

/// AppKit shell for the menu bar dropdown: owns the `NSStatusItem` and builds
/// the `NSMenu` directly instead of going through SwiftUI's `MenuBarExtra`.
///
/// The deciding reason is the option-revealed diagnostics: Finder-style
/// items that appear while Option is held and vanish when it is released,
/// live, with the menu open. SwiftUI builds a `.menu`-style MenuBarExtra's
/// items once per open and never restructures them during tracking, so that
/// behavior is unreachable there; an AppKit menu updates in place (the
/// diagnostic items are always present and just flip `isHidden`). AppKit
/// also gives the truly native section headers and checkmark states the menu
/// uses. All behavior still lives in `AspaceModel` — this class only
/// translates model state into menu items.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AspaceModel
    private let updater: UpdaterController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(model: AspaceModel, updater: UpdaterController) {
        self.model = model
        self.updater = updater
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // Keep the icon in sync with the active profile (the model refreshes
        // itself on display reconfiguration events).
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)
        updateStatusButton()
    }

    private func updateStatusButton() {
        statusItem.button?.image = NSImage(
            systemSymbolName: model.statusSymbolName,
            accessibilityDescription: "aspace"
        )
        statusItem.button?.toolTip = model.statusTooltip
    }

    // MARK: - NSMenuDelegate

    // Known cosmetic quirk, accepted deliberately: when Option reveals the
    // diagnostic items and rows shift, AppKit keeps the highlight glued to
    // the previously-highlighted item until the pointer moves a pixel,
    // whereas Finder re-resolves the row under the pointer immediately.
    // Matching Finder requires re-posting a synthetic mouse-moved event,
    // and injecting events (CGEvent.post) makes macOS demand Accessibility
    // permission — far too heavy a price for highlight polish.
    func menuWillOpen(_ menu: NSMenu) {
        model.refresh()
        rebuild()
    }

    // MARK: - Menu construction

    private func rebuild() {
        menu.removeAllItems()

        if let warning = model.versionMismatchMessage {
            menu.addItem(actionItem(warning) { [model] in model.showVersionMismatchAlert() })
            menu.addItem(.separator())
        }

        addHeader("Profiles")
        for name in model.availableProfileNames where name != AspaceConfig.allProfileName {
            let item = actionItem(name) { [model] in model.applyProfile(name) }
            item.state = model.activeProfile == name ? .on : .off
            menu.addItem(item)
        }
        if model.config.profiles.isEmpty {
            menu.addItem(actionItem("(Edit config.json to add profiles)") { [model] in
                model.openConfigFile()
            })
        }

        // The built-in "all" profile reads as an action, not another profile
        // — keep it out of the profiles group so it can't be confused for one.
        menu.addItem(.separator())
        let reconnect = actionItem("Reconnect all displays") { [model] in
            model.applyProfile(AspaceConfig.allProfileName)
        }
        reconnect.state = model.activeProfile == AspaceConfig.allProfileName ? .on : .off
        menu.addItem(reconnect)

        let resolutions = model.availableResolutionNames
        if !resolutions.isEmpty {
            menu.addItem(.separator())
            addHeader("Resolutions")
            for name in resolutions {
                let item = actionItem(name) { [model] in model.applyResolution(name) }
                item.state = model.activeResolution == name ? .on : .off
                item.isEnabled = model.isResolutionApplicable(name)
                menu.addItem(item)
            }

        }

        menu.addItem(.separator())
        if !resolutions.isEmpty {
            let restore = actionItem("Restore resolution after switch") { [model] in
                model.setRestoreResolutionEnabled(!model.restoreResolutionEnabled)
            }
            restore.state = model.restoreResolutionEnabled ? .on : .off
            menu.addItem(restore)
        }
        let stabilize = actionItem("Stabilize display after switch") { [model] in
            model.setStabilizationEnabled(!model.stabilizationEnabled)
        }
        stabilize.state = model.stabilizationEnabled ? .on : .off
        menu.addItem(stabilize)

        menu.addItem(.separator())
        addDiagnostics()
        menu.addItem(actionItem("Edit Config…") { [model] in model.openConfigFile() })

        menu.addItem(.separator())
        let check = actionItem("Check for Updates…") { [updater] in updater.checkForUpdates() }
        check.isEnabled = updater.canCheckForUpdates
        menu.addItem(check)
        menu.addItem(actionItem("About aspace (\(AspaceVersion.current))") { [model] in model.showAbout() })
        let quit = actionItem("Quit aspace") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Add an item that only shows while Option is held, rendered by the
    /// native alternate-item machinery (glitch-free, exactly Finder's Go >
    /// "Library"): a hidden base item whose Option alternate is the real
    /// item. The pair folds into one slot; without Option the slot shows the
    /// base — which is hidden, so nothing — and holding Option swaps the
    /// alternate in, with the menu system driving the relayout and the
    /// highlight. Toggling `isHidden` by hand mid-track instead repaints
    /// badly (blanked titles, misaligned highlight); the alternate path is
    /// the one AppKit actually supports.
    private func addOptionRevealed(title: String, submenu: NSMenu) {
        let base = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        base.isHidden = true
        base.keyEquivalentModifierMask = []
        menu.addItem(base)

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isAlternate = true
        item.keyEquivalentModifierMask = [.option]
        item.submenu = submenu
        menu.addItem(item)
    }

    /// Diagnostic detail: which displays are online (with the UUIDs the
    /// config is written in) and what each profile would configure. Clicking
    /// a display row copies its UUID — menus offer no text selection, so
    /// copy is the useful "read". The items are always in the menu but
    /// hidden unless Option is held.
    private func addDiagnostics() {
        let displaysMenu = NSMenu()
        displaysMenu.autoenablesItems = false
        for row in model.displayRows {
            displaysMenu.addItem(actionItem(displayLabel(row)) { [model] in
                model.copyToClipboard(row.uuid)
            })
        }
        addOptionRevealed(title: "Displays", submenu: displaysMenu)

        guard !model.config.profiles.isEmpty else { return }
        let detailsMenu = NSMenu()
        detailsMenu.autoenablesItems = false
        for name in model.availableProfileNames {
            guard let summary = model.profileSummary(name) else { continue }
            let profileItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let rowsMenu = NSMenu()
            rowsMenu.autoenablesItems = false
            for row in summary.rows {
                rowsMenu.addItem(actionItem(summaryLabel(row)) { [model] in
                    model.copyToClipboard(row.uuid)
                })
            }
            if let audio = summary.audioOutput {
                rowsMenu.addItem(.separator())
                let audioItem = NSMenuItem(title: "Audio: \(audio)", action: nil, keyEquivalent: "")
                audioItem.isEnabled = false
                rowsMenu.addItem(audioItem)
            }
            profileItem.submenu = rowsMenu
            detailsMenu.addItem(profileItem)
        }
        addOptionRevealed(title: "Profile Details", submenu: detailsMenu)
    }

    // MARK: - Helpers

    private func addHeader(_ title: String) {
        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: title))
        } else {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func actionItem(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        ActionMenuItem(title, handler: handler)
    }

    private func summaryLabel(_ row: ProfileSummary.Row) -> String {
        let mark = row.enabled ? "🟢" : "⚪️"
        let main = row.isMain ? " (main)" : ""
        return "\(mark) \(row.name)\(main)  [\(row.uuid)]"
    }

    private func displayLabel(_ row: DisplayKit.DisplayStatusRow) -> String {
        let mark = row.isActive ? "🟢" : "⚪️"
        let main = row.isMain ? " (main)" : ""
        return "\(mark) \(row.name)\(main)  [\(row.uuid)]"
    }
}

/// NSMenuItem that runs a closure — avoids scattering target/selector pairs.
/// Main-actor isolated: menus are built and their actions invoked on the
/// main thread.
@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func invoke() {
        handler()
    }
}
