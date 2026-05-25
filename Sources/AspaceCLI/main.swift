import ArgumentParser
import DisplayKit
import Foundation

@main
struct Aspace: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aspace",
        abstract: "Minimal display connection control for macOS.",
        version: AspaceVersion.current,
        subcommands: [
            List.self,
            Enable.self,
            Disable.self,
            Main.self,
            Profile.self,
            Profiles.self,
            Prune.self,
            IsEnabled.self,
            IsMain.self,
            Version.self,
        ],
        defaultSubcommand: List.self
    )
}

// MARK: - Subcommands

extension Aspace {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List displays (UUID, id, enabled, main, name)."
        )

        func run() throws {
            let displays = DisplayKit.listDisplays()
            print("\(pad("UUID", 38)) \(pad("ID", 8)) \(pad("ENABLED", 8)) \(pad("MAIN", 6)) NAME")
            for d in displays {
                let enabled = d.isEnabled ? "on" : "off"
                let main = d.isMain ? "true" : "false"
                print("\(pad(d.uuid, 38)) \(pad(String(d.id), 8)) \(pad(enabled, 8)) \(pad(main, 6)) \(d.name)")
            }
        }
    }

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enable",
            abstract: "Reconnect a display by UUID."
        )

        @Argument(help: "Display UUID from `aspace list`.")
        var uuid: String

        func run() throws {
            try DisplayKit.setEnabled(uuid: uuid, enabled: true)
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "disable",
            abstract: "Disconnect a display by UUID."
        )

        @Argument(help: "Display UUID from `aspace list`.")
        var uuid: String

        func run() throws {
            try DisplayKit.setEnabled(uuid: uuid, enabled: false)
        }
    }

    struct Main: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "main",
            abstract: "Make a display the primary display."
        )

        @Argument(help: "Display UUID from `aspace list`.")
        var uuid: String

        func run() throws {
            try DisplayKit.setMain(uuid: uuid)
        }
    }

    struct Profile: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "profile",
            abstract: """
                Apply a profile from ~/.config/aspace/config.json. \
                Use "all" for the built-in "everything on" profile.
                """
        )

        @Argument(help: "Profile name.")
        var name: String

        func run() throws {
            let config = AspaceConfig.loadOrEmpty()
            try ProfileRunner.run(profile: name, config: config)
        }
    }

    struct Profiles: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "profiles",
            abstract: "List available profile names."
        )

        func run() throws {
            let config = AspaceConfig.loadOrEmpty()
            for name in ProfileRunner.availableProfileNames(config: config) {
                print(name)
            }
        }
    }

    struct Prune: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove registry entries unseen for N days."
        )

        @Argument(help: "Age threshold in days (default 30). Use 0 to drop every offline entry.")
        var days: Int = 30

        func run() throws {
            // Refresh registry first so currently-online displays bump
            // their lastSeen and aren't accidentally pruned.
            _ = DisplayKit.listDisplays()
            let removed = ProfileRunner.prune(olderThanDays: days)
            if removed.isEmpty {
                print("Nothing to prune (no entries older than \(days) days).")
            } else {
                print("Pruned \(removed.count) entr\(removed.count == 1 ? "y" : "ies"):")
                for uuid in removed { print("  \(uuid)") }
            }
        }
    }

    struct IsEnabled: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "is-enabled",
            abstract: "Print \"on\" if the display is enabled, \"off\" otherwise."
        )

        @Argument(help: "Display UUID.")
        var uuid: String

        func run() throws {
            let enabled = DisplayKit.display(forUUID: uuid)?.isEnabled ?? false
            print(enabled ? "on" : "off")
        }
    }

    struct IsMain: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "is-main",
            abstract: "Print \"true\" if the display is the main one, \"false\" otherwise."
        )

        @Argument(help: "Display UUID.")
        var uuid: String

        func run() throws {
            let main = DisplayKit.display(forUUID: uuid)?.isMain ?? false
            print(main ? "true" : "false")
        }
    }

    /// Subcommand form kept for backward compatibility — `aspace --version`
    /// (auto-generated by ArgumentParser) does the same thing.
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Print version."
        )

        func run() throws {
            print(AspaceVersion.current)
        }
    }
}

// MARK: - Helpers

private func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}
