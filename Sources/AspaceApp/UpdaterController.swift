import SwiftUI
import Sparkle

/// Thin SwiftUI-friendly wrapper around Sparkle's standard updater. Owns
/// the `SPUStandardUpdaterController` so its lifetime matches the App, and
/// exposes a `canCheckForUpdates` flag that views can bind to in order to
/// disable the menu item while a check is in flight.
@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
