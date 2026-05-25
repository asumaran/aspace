import Foundation
import DisplayKit

func usage() -> Never {
    let text = """
    aspace - Minimal display connection control for macOS

    Usage: aspace <command> [args]

    Commands:
      list                        List displays (UUID, id, enabled, main, name)
      enable     <uuid>           Reconnect a display
      disable    <uuid>           Disconnect a display
      main       <uuid>           Make a display the primary
      profile    <name>           Apply a profile (use "all" for built-in
                                  "everything on"; others come from
                                  ~/.config/aspace/config.json)
      profiles                    List available profile names
      is-enabled <uuid>           Print "on" or "off"
      is-main    <uuid>           Print "true" or "false"
      version                     Print version and exit
    """
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

func requireArg(_ args: [String], _ index: Int, _ name: String) -> String {
    guard args.indices.contains(index) else {
        FileHandle.standardError.write(Data("Missing required argument: \(name)\n".utf8))
        exit(2)
    }
    return args[index]
}

private func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}

func printList() {
    let displays = DisplayKit.listDisplays()
    print("\(pad("UUID", 38)) \(pad("ID", 8)) \(pad("ENABLED", 8)) \(pad("MAIN", 6)) NAME")
    for d in displays {
        let enabled = d.isEnabled ? "on" : "off"
        let main = d.isMain ? "true" : "false"
        print("\(pad(d.uuid, 38)) \(pad(String(d.id), 8)) \(pad(enabled, 8)) \(pad(main, 6)) \(d.name)")
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { usage() }

do {
    switch args[1] {
    case "list":
        printList()
    case "enable":
        try DisplayKit.setEnabled(uuid: requireArg(args, 2, "uuid"), enabled: true)
    case "disable":
        try DisplayKit.setEnabled(uuid: requireArg(args, 2, "uuid"), enabled: false)
    case "main":
        try DisplayKit.setMain(uuid: requireArg(args, 2, "uuid"))
    case "profile":
        let name = requireArg(args, 2, "name")
        let config = AspaceConfig.loadOrEmpty()
        try ProfileRunner.run(profile: name, config: config)
    case "profiles":
        let config = AspaceConfig.loadOrEmpty()
        for name in ProfileRunner.availableProfileNames(config: config) {
            print(name)
        }
    case "is-enabled":
        let uuid = requireArg(args, 2, "uuid")
        let enabled = DisplayKit.display(forUUID: uuid)?.isEnabled ?? false
        print(enabled ? "on" : "off")
    case "is-main":
        let uuid = requireArg(args, 2, "uuid")
        let main = DisplayKit.display(forUUID: uuid)?.isMain ?? false
        print(main ? "true" : "false")
    case "version", "--version", "-v":
        print(AspaceVersion.current)
    case "-h", "--help", "help":
        usage()
    default:
        FileHandle.standardError.write(Data("Unknown command: \(args[1])\n".utf8))
        usage()
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
