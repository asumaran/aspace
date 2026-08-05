import Foundation

/// Switches the system's default audio output to a device named in config
/// (a profile's `audioOutput`). Follows the same non-destructive philosophy
/// as the display runners: a device that never shows up, or a name that
/// matches several devices, is skipped with a warning — it never aborts the
/// profile switch that requested it.
public enum AudioRunner {

    /// How a config name resolved against the connected output devices.
    enum Match: Equatable {
        case found(AudioOutputDevice)
        case notFound
        case ambiguous([String])
    }

    /// Resolve a user-supplied name to a device. Exact case-insensitive match
    /// wins; otherwise a case-insensitive substring match is accepted when it
    /// is unique (so `"tv"` finds `"LG TV"` but is rejected if two devices
    /// contain "tv"). Pure so tests can drive it with synthetic devices.
    static func match(name: String, in devices: [AudioOutputDevice]) -> Match {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        if let exact = devices.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) {
            return .found(exact)
        }
        let partial = devices.filter { $0.name.range(of: wanted, options: .caseInsensitive) != nil }
        switch partial.count {
        case 0:  return .notFound
        case 1:  return .found(partial[0])
        default: return .ambiguous(partial.map { $0.name }.sorted())
        }
    }

    /// Production entry point — real CoreAudio backend, real sleeps.
    public static func run(deviceNamed name: String) throws {
        try run(deviceNamed: name, backend: LiveAudioBackend())
    }

    /// The output devices CoreAudio reports right now (for `aspace audio-outputs`).
    public static func outputDevices() -> [AudioOutputDevice] {
        LiveAudioBackend().listOutputDevices()
    }

    /// UID of the current default output device, if one is set.
    public static func defaultOutputUID() -> String? {
        LiveAudioBackend().defaultOutputDeviceUID()
    }

    // MARK: - Test seam

    /// Set the default output to the device matching `name`, waiting up to
    /// `timeout` for it to appear. The wait matters after a profile switch: an
    /// HDMI TV's audio device only registers with CoreAudio once the display
    /// link is up, which can lag the topology change by several seconds.
    ///
    /// An ambiguous name or a device that never appears is reported through
    /// `warn` and otherwise ignored; only a CoreAudio failure while setting an
    /// existing device throws.
    static func run(
        deviceNamed name: String,
        backend: AudioBackend,
        timeout: TimeInterval = 10.0,
        sleep sleepFn: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        warn: (String) -> Void = { msg in
            AspaceLog.audio.warning("\(msg, privacy: .public)")
            FileHandle.standardError.write(Data("aspace: \(msg)\n".utf8))
        }
    ) throws {
        var waited = 0.0
        while true {
            switch match(name: name, in: backend.listOutputDevices()) {
            case .found(let device):
                if backend.defaultOutputDeviceUID() == device.uid {
                    AspaceLog.audio.notice("audio output '\(device.name, privacy: .public)' already default")
                    return
                }
                try backend.setDefaultOutput(uid: device.uid)
                AspaceLog.audio.notice("audio output -> '\(device.name, privacy: .public)' (\(device.uid, privacy: .public)): ok")
                return
            case .ambiguous(let names):
                warn("audio output \"\(name)\" is ambiguous — matches: \(names.joined(separator: ", ")); left the current output unchanged")
                return
            case .notFound:
                guard waited < timeout else {
                    warn("audio output \"\(name)\" not found after \(Int(timeout))s; left the current output unchanged")
                    return
                }
                sleepFn(0.5)
                waited += 0.5
            }
        }
    }
}
