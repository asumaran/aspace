import SwiftUI
import DisplayKit

/// Contents of the menu bar dropdown. Pure rendering — all behavior lives
/// in `AspaceModel`.
struct MenuContentView: View {
    @ObservedObject var model: AspaceModel
    @ObservedObject var updater: UpdaterController

    var body: some View {
        if let warning = model.versionMismatchMessage {
            Button(warning) {
                model.showVersionMismatchAlert()
            }
            Divider()
        }

        Text("Profile: \(model.activeProfile ?? "custom")")

        Divider()

        ForEach(model.availableProfileNames, id: \.self) { name in
            Button(profileLabel(name)) {
                model.applyProfile(name)
            }
        }

        if model.config.profiles.isEmpty {
            Button("(Edit config.json to add profiles)") {
                model.openConfigFolder()
            }
        }

        if !model.availableResolutionNames.isEmpty {
            Divider()
            Text("Resolution: \(model.activeResolution ?? "custom")")
            ForEach(model.availableResolutionNames, id: \.self) { name in
                Button(resolutionLabel(name)) {
                    model.applyResolution(name)
                }
                .disabled(!model.isResolutionApplicable(name))
            }
        }

        Divider()

        Menu("Displays") {
            ForEach(model.displayRows, id: \.uuid) { row in
                Text(displayLabel(row))
            }
        }

        Divider()

        Button("Refresh") { model.refresh() }
            .keyboardShortcut("r")

        Button("Open Config Folder") { model.openConfigFolder() }

        Divider()

        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)

        Button("About aspace (\(AspaceVersion.current))") { model.showAbout() }

        Button("Quit aspace") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func profileLabel(_ name: String) -> String {
        let prefix = (model.activeProfile == name) ? "✓ " : "   "
        let display = (name == AspaceConfig.allProfileName)
            ? "Reconnect all displays"
            : "Switch to \(name)"
        return prefix + display
    }

    private func resolutionLabel(_ name: String) -> String {
        let prefix = (model.activeResolution == name) ? "✓ " : "   "
        return prefix + name
    }

    private func displayLabel(_ row: DisplayKit.DisplayStatusRow) -> String {
        let mark = row.isActive ? "🟢" : "⚪️"
        let main = row.isMain ? " (main)" : ""
        return "\(mark) \(row.name)\(main)"
    }
}
