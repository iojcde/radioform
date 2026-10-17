import Foundation
import Combine
import RadioformConfiguration

final class OutputDeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var preferences = OutputDevicePreferences()
    @Published var errorMessage: String?
    private let store = OutputDevicePreferenceStore()

    func refresh() {
        devices = AudioOutputDevice.connectedOutputs()
        do { preferences = try store.load(); errorMessage = nil }
        catch { errorMessage = "Could not load output preferences: \(error.localizedDescription)" }
    }

    func setEnabled(_ enabled: Bool, uid: String) {
        var updated = preferences
        updated.setEnabled(enabled, uid: uid)
        do {
            try store.save(updated)
            preferences = updated
            errorMessage = nil
        } catch {
            errorMessage = "Could not save output preferences: \(error.localizedDescription)"
        }
    }
}
