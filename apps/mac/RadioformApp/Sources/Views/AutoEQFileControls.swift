import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AutoEQFileControls: View {
    @ObservedObject private var presets = PresetManager.shared

    var body: some View {
        HStack {
            Button("Import AutoEQ…", systemImage: "square.and.arrow.down", action: importFile)
            Spacer()
            Button("Export AutoEQ…", systemImage: "square.and.arrow.up", action: exportFile)
        }
        .font(.system(size: 11))
        .buttonStyle(.borderless)
    }

    private func showError(_ error: Error) {
        // File panels can dismiss the transient menu-bar popover. A native alert
        // remains visible even when that popover has closed.
        let alert = NSAlert()
        alert.messageText = "AutoEQ File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.title = "Import AutoEQ Preset"
        panel.message = "Choose a ParametricEQ .txt file with up to \(EQPreset.maximumBands) filters."
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try presets.importAutoEQ(from: url) }
        catch { showError(error) }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.title = "Export AutoEQ Preset"
        panel.message = "Exports preamp and filters. AutoEQ text does not store limiter or Fixed Spatial settings."
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = presets.configuredPreset().name.replacingOccurrences(of: "/", with: "-") + ".txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try presets.exportAutoEQ(to: url) }
        catch { showError(error) }
    }
}
