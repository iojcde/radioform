import SwiftUI

struct OutputDevicesSection: View {
    @StateObject private var manager = OutputDeviceManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Outputs").font(.headline)
            Text("Choose which outputs get a Radioform EQ device. New outputs are enabled by default.")
                .font(.caption).foregroundColor(.secondary)
            if manager.devices.isEmpty {
                Text("No physical audio outputs connected.").foregroundColor(.secondary)
            }
            ForEach(manager.devices) { device in
                Toggle(device.name, isOn: Binding(
                    get: { manager.preferences.isEnabled(uid: device.id) },
                    set: { manager.setEnabled($0, uid: device.id) }
                ))
                .help("Enable or disable the Radioform device for \(device.name)")
            }
            if let error = manager.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .onAppear { manager.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in manager.refresh() }
    }
}
