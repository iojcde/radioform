import Foundation

// Keep editor regression tests independent of the installed audio driver.
final class IPCController {
    static let shared = IPCController()
    var lastApplied: EQPreset?
    func getCurrentPreset() -> EQPreset? { nil }
    func applyPreset(_ preset: EQPreset) throws { lastApplied = preset }
}

@main
struct PresetManagerTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("radioform-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = PresetManager(userPresetsURL: directory)

        for count in [1, 2, 5, 9, 10, 11, 12, EQPreset.maximumBands] {
            let text = (1...count).map {
                "Filter \($0): \($0 == 2 ? "OFF" : "ON") PK Fc \($0 * 100) Hz Gain -1.2 dB Q 0.7"
            }.joined(separator: "\n")
            let preset = try AutoEQCodec.decode(text, name: "Test")
            manager.setFocusedBand(9)
            manager.applyPreset(preset)
            precondition(manager.currentBandCount == count)
            precondition(manager.focusedBandIndex == nil)
            precondition(manager.configuredPreset() == preset)

            manager.updatePreamp(gainDb: -2)
            manager.updateBand(index: count - 1, gainDb: 3.5)
            manager.updateBandQ(index: 0, qFactor: 1.25)
            manager.updateBandFrequency(index: 0, frequencyHz: 123)
            let edited = manager.configuredPreset()
            precondition(edited.bands.count == count)
            precondition(edited.bands[count - 1].gainDb == 3.5)
            if count > 2 { precondition(!edited.bands[1].enabled) }
            let exportURL = directory.appendingPathComponent("export.txt")
            try manager.exportAutoEQ(to: exportURL)
            let exported = try AutoEQCodec.decode(String(contentsOf: exportURL, encoding: .utf8), name: edited.name)
            precondition(exported == edited)

            manager.updateBand(index: count, gainDb: 9)
            precondition(manager.configuredPreset() == edited)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            precondition(IPCController.shared.lastApplied == edited)
            manager.toggleEnabled()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            precondition(IPCController.shared.lastApplied?.bands.count == count)
            precondition(IPCController.shared.lastApplied!.bands.allSatisfy { !$0.enabled })
            precondition(manager.configuredPreset() == edited)
            manager.toggleEnabled()
        }
        manager.applyPreset(EQPreset.flat())
        while manager.currentBandCount < EQPreset.maximumBands { manager.addBand() }
        precondition(manager.configuredPreset().bands.count == EQPreset.maximumBands)
        precondition(manager.focusedBandIndex == EQPreset.maximumBands - 1)
        manager.updateBand(index: 10, gainDb: 4)
        manager.updatePreamp(gainDb: -3)
        precondition(manager.configuredPreset().bands[10].gainDb == 4)
        precondition(manager.configuredPreset().preampDb == -3)
        manager.addBand()
        precondition(manager.currentBandCount == EQPreset.maximumBands)
        let previous = manager.configuredPreset().bands
        manager.removeBand(at: 3)
        precondition(manager.configuredPreset().bands == Array(previous[..<3]) + Array(previous[4...]))
        precondition(manager.focusedBandIndex == EQPreset.maximumBands - 2)
        manager.setFocusedBand(PresetManager.preampFocusIndex)
        manager.removeBand(at: 0)
        precondition(manager.focusedBandIndex == PresetManager.preampFocusIndex)
        while manager.currentBandCount > 1 { manager.removeBand(at: 0) }
        manager.removeBand(at: 0)
        precondition(manager.currentBandCount == 1)
        manager.addBand()
        precondition(manager.currentBandCount == 2 && manager.configuredPreset().isValid())
        manager.updateSpatialEnabled(true)
        manager.updateSpatialMix(0.65)
        let spatial = manager.configuredPreset()
        precondition(spatial.spatialEnabled && spatial.spatialMix == 0.65)
        manager.updateBand(index: 0, gainDb: 1)
        precondition(manager.configuredPreset().spatialEnabled)
        manager.toggleEnabled()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(IPCController.shared.lastApplied?.spatialEnabled == false)
        precondition(manager.configuredPreset().spatialEnabled)
        manager.toggleEnabled()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(IPCController.shared.lastApplied?.spatialEnabled == true)
        manager.applyPreset(spatial)
        precondition(manager.currentSpatialEnabled && manager.currentSpatialMix == 0.65)
        print("Preset editor: 1–32 filters preserved through edits, export, audio apply, bypass, add and remove")
    }
}
