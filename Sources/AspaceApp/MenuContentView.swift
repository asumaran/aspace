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

        Divider()

        Text("Displays")
        ForEach(model.displays, id: \.uuid) { display in
            Text(displayLabel(display))
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

    private func displayLabel(_ display: DisplayInfo) -> String {
        let mark = display.isEnabled ? "●" : "○"
        let main = display.isMain ? " (main)" : ""
        return "  \(mark) \(display.name)\(main)"
    }
}
