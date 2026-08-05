import SwiftUI

/// The menu bar item and its dropdown are AppKit (`StatusMenuController`),
/// not a SwiftUI `MenuBarExtra` — see that class for why. The SwiftUI App
/// only hosts the app lifecycle; the empty Settings scene is the standard
/// placeholder for an agent app with no windows.
@main
struct AspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = StatusMenuController(model: AspaceModel(), updater: UpdaterController())
    }
}
