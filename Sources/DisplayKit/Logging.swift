import Foundation
import os

/// Unified logging for the aspace components. Each subsystem gets its own
/// category so `log show --predicate 'subsystem == "com.asumaran.aspace"'`
/// (or Console.app filtering) can scope the output.
public enum AspaceLog {
    private static let subsystem = "com.asumaran.aspace"

    public static let displayKit = Logger(subsystem: subsystem, category: "DisplayKit")
    public static let profile    = Logger(subsystem: subsystem, category: "ProfileRunner")
    public static let registry   = Logger(subsystem: subsystem, category: "Registry")
    public static let audio      = Logger(subsystem: subsystem, category: "Audio")
    public static let cli        = Logger(subsystem: subsystem, category: "CLI")
    public static let app        = Logger(subsystem: subsystem, category: "App")
}
