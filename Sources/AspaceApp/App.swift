import SwiftUI
import DisplayKit

@main
struct AspaceApp: App {
    @StateObject private var model = AspaceModel()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model, updater: updater)
        } label: {
            Image(systemName: model.statusSymbolName)
                .help(model.statusTooltip)
        }
        .menuBarExtraStyle(.menu)
    }
}
