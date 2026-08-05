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
            Modes.self,
            Profile.self,
            Profiles.self,
            Capture.self,
            Audio.self,
            AudioOutputs.self,
            Resolution.self,
            Resolutions.self,
            CaptureResolution.self,
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
            print("\(pad("UUID", 38)) \(pad("ID", 8)) \(pad("ENABLED", 8)) \(pad("MAIN", 6)) \(pad("RESOLUTION", 12)) NAME")
            for d in displays {
                let enabled = d.isEnabled ? "on" : "off"
                let main = d.isMain ? "true" : "false"
                let res = DisplayKit.currentMode(uuid: d.uuid).map { "\($0.pointWidth)x\($0.pointHeight)" } ?? "-"
                print("\(pad(d.uuid, 38)) \(pad(String(d.id), 8)) \(pad(enabled, 8)) \(pad(main, 6)) \(pad(res, 12)) \(d.name)")
            }
        }
    }

    struct Modes: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "modes",
            abstract: """
                List the resolutions a display supports (points, pixels, \
                scaling, refresh). Use the POINTS value in a resolution preset. \
                A `*` marks the current mode. Defaults to every online display.
                """
        )

        @Argument(help: "Display UUID from `aspace list` (default: all online displays).")
        var uuid: String?

        func run() throws {
            let displays = DisplayKit.listDisplays()
            let targets: [DisplayInfo]
            if let uuid = uuid {
                guard let match = displays.first(where: { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }) else {
                    throw ValidationError("Display \(uuid) is not online (see `aspace list`).")
                }
                targets = [match]
            } else {
                targets = displays
            }

            for (index, display) in targets.enumerated() {
                if index > 0 { print("") }
                printModes(for: display)
            }
        }

        private func printModes(for display: DisplayInfo) {
            print("\(display.name)  [\(display.uuid)]")
            print("\(pad("POINTS", 12)) \(pad("PIXELS", 12)) \(pad("SCALE", 6)) \(pad("HZ", 4)) \(pad("HIDPI", 6)) CURRENT")
            let current = DisplayKit.currentMode(uuid: display.uuid)
            for mode in DisplayModeReport.sorted(DisplayKit.modes(uuid: display.uuid)) {
                let points = "\(mode.pointWidth)x\(mode.pointHeight)"
                let pixels = "\(mode.pixelWidth)x\(mode.pixelHeight)"
                let factor = mode.pointWidth > 0 ? Double(mode.pixelWidth) / Double(mode.pointWidth) : 0
                let scale = String(format: "%.1fx", factor)
                let hz = String(format: "%.0f", mode.refreshHz)
                let hidpi = mode.isHiDPI ? "yes" : "no"
                let marker = (current == mode) ? "*" : ""
                print("\(pad(points, 12)) \(pad(pixels, 12)) \(pad(scale, 6)) \(pad(hz, 4)) \(pad(hidpi, 6)) \(marker)")
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

        @Flag(name: .long, help: "Preview what the profile would do, changing nothing.")
        var dryRun = false

        @Flag(name: .long, help: "Skip the post-switch stabilization watch (~2s faster; see README).")
        var noStabilize = false

        func run() throws {
            let config = AspaceConfig.loadOrEmpty()
            if dryRun {
                guard let plan = ProfileRunner.plan(profile: name, config: config) else {
                    throw ValidationError("Profile not found in config: \(name)")
                }
                printPlan(plan)
                return
            }
            try ProfileRunner.run(profile: name, config: config, stabilization: !noStabilize)
        }

        private func printPlan(_ plan: ProfileRunner.Plan) {
            let names = DisplayKit.knownDisplayNames()
            let onlineNow = Set(plan.onlineNow)
            func label(_ uuid: String) -> String {
                let name = names[uuid] ?? "(unknown)"
                return "\(name)  [\(uuid)]\(onlineNow.contains(uuid) ? "" : "  offline now")"
            }
            print("dry-run: profile '\(plan.profile)' — nothing was changed\n")
            print("  enable:")
            plan.toEnable.isEmpty ? print("    (none)") : plan.toEnable.forEach { print("    + \(label($0))") }
            print("  disable:")
            plan.toDisable.isEmpty ? print("    (none)") : plan.toDisable.forEach { print("    - \(label($0))") }
            if let main = plan.effectiveMain {
                let how = plan.declaredMain == nil ? "  (auto: sole surviving display)" : ""
                print("  main:\n    * \(label(main))\(how)")
            } else {
                print("  main:\n    (unchanged)")
            }
            if let audio = plan.audioOutput {
                print("  audio output:\n    ~ \(audio)")
            }
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

    struct Capture: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "capture",
            abstract: """
                Save the current topology as a profile in \
                ~/.config/aspace/config.json: the main display, plus any \
                known-but-off displays as the profile's disable list. Does not \
                record resolutions (see `capture-resolution`). Overwrites an \
                existing profile of the same name.
                """
        )

        @Argument(help: "Profile name to create or overwrite.")
        var name: String

        func run() throws {
            guard name != AspaceConfig.allProfileName else {
                throw ValidationError("\"\(AspaceConfig.allProfileName)\" is a built-in profile and cannot be captured.")
            }

            let live = DisplayKit.listDisplays()
            let activeKeys = Set(live.filter { $0.isEnabled }.map { $0.uuid.uppercased() })
            let off = DisplayKit.allKnownUUIDs().filter { !activeKeys.contains($0.uppercased()) }
            let mainUUID = live.first { $0.isMain }?.uuid

            let profile = ProfileCapture.profile(mainUUID: mainUUID, off: Array(off))

            let existing = AspaceConfig.loadOrEmpty()
            var profiles = existing.profiles
            profiles[name] = profile
            let updated = AspaceConfig(profiles: profiles, resolutions: existing.resolutions, schemaVersion: existing.schemaVersion)
            try updated.save()

            print("Captured profile \"\(name)\": main=\(mainUUID ?? "none"), \(off.count) off.")
        }
    }

    struct Audio: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "audio",
            abstract: """
                Set the default audio output device by name (see \
                `aspace audio-outputs`). Case-insensitive; a substring works \
                when it matches exactly one device.
                """
        )

        @Argument(help: "Output device name from `aspace audio-outputs`.")
        var name: String

        func run() throws {
            try AudioRunner.run(deviceNamed: name)
        }
    }

    struct AudioOutputs: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "audio-outputs",
            abstract: "List audio output devices. A `*` marks the current default."
        )

        func run() throws {
            let defaultUID = AudioRunner.defaultOutputUID()
            print("\(pad("NAME", 32)) \(pad("DEFAULT", 8)) UID")
            for device in AudioRunner.outputDevices().sorted(by: { $0.name < $1.name }) {
                let marker = device.uid == defaultUID ? "*" : ""
                print("\(pad(device.name, 32)) \(pad(marker, 8)) \(device.uid)")
            }
        }
    }

    struct Resolution: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resolution",
            abstract: """
                Apply a resolution preset from ~/.config/aspace/config.json. \
                Changes only the resolution of the listed displays; it never \
                connects/disconnects displays or changes the main.
                """
        )

        @Argument(help: "Resolution preset name.")
        var name: String

        func run() throws {
            let config = AspaceConfig.loadOrEmpty()
            try ResolutionRunner.run(preset: name, config: config)
        }
    }

    struct Resolutions: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resolutions",
            abstract: "List available resolution preset names."
        )

        func run() throws {
            let config = AspaceConfig.loadOrEmpty()
            for name in ResolutionRunner.availablePresetNames(config: config) {
                print(name)
            }
        }
    }

    struct CaptureResolution: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "capture-resolution",
            abstract: """
                Save the current resolutions of all on displays as a resolution \
                preset in ~/.config/aspace/config.json. Overwrites an existing \
                preset of the same name.
                """
        )

        @Argument(help: "Resolution preset name to create or overwrite.")
        var name: String

        func run() throws {
            let active = DisplayKit.listDisplays().filter { $0.isEnabled }
            let snapshot: [ProfileCapture.ActiveDisplay] = active.compactMap { d in
                guard let mode = DisplayKit.currentMode(uuid: d.uuid) else { return nil }
                return ProfileCapture.ActiveDisplay(
                    uuid: d.uuid,
                    mode: AspaceConfig.ModeSpec(pointWidth: mode.pointWidth, pointHeight: mode.pointHeight)
                )
            }
            let preset = ProfileCapture.resolutionPreset(active: snapshot)

            let existing = AspaceConfig.loadOrEmpty()
            var resolutions = existing.resolutions
            resolutions[name] = preset
            let updated = AspaceConfig(profiles: existing.profiles, resolutions: resolutions, schemaVersion: existing.schemaVersion)
            try updated.save()

            print("Captured resolution preset \"\(name)\": \(preset.count) display(s).")
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
