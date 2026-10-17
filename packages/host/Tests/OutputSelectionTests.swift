import Foundation
import RadioformConfiguration

// The registry uses device identity only. Avoid accessing hardware in tests.
struct PhysicalDevice {
    let id: UInt32
    let name: String
    let uid: String
}
enum RadioformConfig { static let controlFilePath = "/unused-in-tests" }

@main
struct OutputSelectionTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("devices.txt")
        func advertised() -> String { try! String(contentsOf: url, encoding: .utf8) }
        let store = OutputDevicePreferenceStore(url: directory.appendingPathComponent("preferences.json"))
        var preferences = OutputDevicePreferences(disabledDeviceUIDs: ["display"])
        try store.save(preferences)
        let registry = DeviceRegistry(preferences: try store.load(), controlFilePath: url.path)
        let headphones = PhysicalDevice(id: 1, name: "Headphones", uid: "phones")
        let display = PhysicalDevice(id: 2, name: "Display", uid: "display")
        registry.update([headphones, display])
        precondition(advertised() == "Headphones|phones")
        // Excluded devices remain available for restoration to the physical output.
        precondition(registry.find(uid: "display")?.id == 2 && registry.eqDevices.count == 1)

        registry.update([headphones])
        let reconnected = PhysicalDevice(id: 99, name: "Renamed Display", uid: "display")
        registry.update([headphones, reconnected])
        precondition(advertised() == "Headphones|phones")

        preferences.setEnabled(false, uid: "phones")
        registry.outputPreferences = preferences
        registry.writeControlFile()
        precondition(advertised().isEmpty)

        preferences.setEnabled(true, uid: "display")
        registry.outputPreferences = preferences
        registry.writeControlFile()
        precondition(advertised() == "Renamed Display|display")

        let malicious = PhysicalDevice(id: 3, name: "Spoof\nInjected|uid", uid: "malformed")
        registry.update([headphones, reconnected, malicious])
        precondition(advertised() == "Renamed Display|display")
        print("Output selection: only enabled UIDs are advertised, reconnects persist, and all outputs can be disabled")
    }
}
