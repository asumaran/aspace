import Foundation
@testable import DisplayKit

/// In-memory `AudioBackend` used to drive AudioRunner without touching real
/// CoreAudio state. Tracks every default-output change so tests can assert on
/// exactly what the runner did.
final class FakeAudioBackend: AudioBackend {
    /// Devices currently visible to `listOutputDevices()`.
    var devices: [AudioOutputDevice]

    /// UID reported as the current default output.
    var defaultUID: String?

    /// UIDs whose setDefaultOutput call should throw.
    var setFailures: Set<String> = []

    /// Devices that only become visible after `listOutputDevices()` has been
    /// polled this many times (simulates an HDMI TV's audio device registering
    /// seconds after the display link comes up).
    var lateDevices: [(device: AudioOutputDevice, afterPolls: Int)] = []
    private var polls = 0

    /// UIDs passed to setDefaultOutput, in order.
    private(set) var setOps: [String] = []

    init(devices: [AudioOutputDevice] = [], defaultUID: String? = nil) {
        self.devices = devices
        self.defaultUID = defaultUID
    }

    func listOutputDevices() -> [AudioOutputDevice] {
        polls += 1
        for (device, afterPolls) in lateDevices where polls > afterPolls {
            if !devices.contains(device) { devices.append(device) }
        }
        return devices
    }

    func defaultOutputDeviceUID() -> String? {
        defaultUID
    }

    func setDefaultOutput(uid: String) throws {
        if setFailures.contains(uid) {
            throw AudioKitError.operationFailed("set default output \(uid)", -1)
        }
        setOps.append(uid)
        defaultUID = uid
    }
}
