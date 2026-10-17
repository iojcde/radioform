import Foundation
import Darwin
import CRadioformAudio
import RadioformConfiguration

class DeviceRegistry {
    private(set) var devices: [PhysicalDevice] = []

    private let controlFilePath: String
    var outputPreferences: OutputDevicePreferences
    var eqDevices: [PhysicalDevice] { devices.filter { outputPreferences.isEnabled(uid: $0.uid) } }

    init(preferences: OutputDevicePreferences = (try? OutputDevicePreferenceStore().load()) ?? OutputDevicePreferences(),
         controlFilePath: String = RadioformConfig.controlFilePath) {
        outputPreferences = preferences
        self.controlFilePath = controlFilePath
    }

    func isEQEnabled(uid: String) -> Bool { outputPreferences.isEnabled(uid: uid) }

    func update(_ newDevices: [PhysicalDevice]) {
        devices = newDevices
        writeControlFile()
    }

    func find(uid: String) -> PhysicalDevice? {
        return devices.first { $0.uid == uid }
    }

    func findAdded(comparing old: [PhysicalDevice]) -> [PhysicalDevice] {
        return devices.filter { new in
            !old.contains { $0.uid == new.uid }
        }
    }

    func findRemoved(comparing old: [PhysicalDevice]) -> [PhysicalDevice] {
        return old.filter { old in
            !devices.contains { $0.uid == old.uid }
        }
    }

    func writeControlFile() {
        // Device strings are protocol fields, not additional control-file records.
        let validDevices = eqDevices.filter {
            !$0.name.contains("\n") && !$0.name.contains("\r") && !$0.name.contains("|") &&
            !$0.uid.contains("\n") && !$0.uid.contains("\r") && !$0.uid.contains("|")
        }
        let content = validDevices.map { "\($0.name)|\($0.uid)" }.joined(separator: "\n")

        var template = Array((controlFilePath + ".XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else {
            print("Failed to create private control file")
            return
        }
        let temporaryPath = String(cString: template)
        defer { close(fd); unlink(temporaryPath) }
        guard rf_ipc_set_permissions(fd, false) == 0 else {
            print("Failed to restrict control file access")
            return
        }
        let data = Data(content.utf8)
        let written = data.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
        guard written, rename(temporaryPath, controlFilePath) == 0 else {
            print("Failed to publish control file")
            return
        }
    }
}
