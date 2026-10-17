import Foundation
import CRadioformDSP

@main
struct ExtendedPresetTests {
    static func main() throws {
        precondition(EQPreset.maximumBands == Int(RADIOFORM_MAX_BANDS))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("radioform-extended-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        for count in [1, 10, 12, EQPreset.maximumBands] {
            let text = (1...count).map {
                "Filter \($0): \($0 == count ? "ON" : "OFF") PK Fc 1000 Hz Gain 6 dB Q 2"
            }.joined(separator: "\n")
            let original = try AutoEQCodec.decode(text, name: "Extended")
            var decoded = try AutoEQCodec.decode(AutoEQCodec.encode(original), name: original.name)
            decoded.spatialEnabled = true
            decoded.spatialMix = 0.65
            try JSONEncoder().encode(decoded).write(to: url)
            var loaded = try PresetLoader().load(from: url.path)
            precondition(loaded.spatial_enabled && loaded.spatial_mix == 0.65)
            precondition(loaded.num_bands == count)
            precondition(radioform_dsp_preset_validate(&loaded) == RADIOFORM_OK)
            withUnsafeBytes(of: &loaded.bands) { bytes in
                let last = bytes.bindMemory(to: radioform_band_t.self)[count - 1]
                precondition(last.enabled && last.frequency_hz == 1000 && last.gain_db == 6 && last.q_factor == 2)
            }
        }
        let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EQPreset.flat())) as! [String: Any]
        var legacyFields = legacy
        legacyFields.removeValue(forKey: "spatial_enabled")
        legacyFields.removeValue(forKey: "spatial_mix")
        try JSONSerialization.data(withJSONObject: legacyFields).write(to: url)
        let oldPreset = try PresetLoader().load(from: url.path)
        precondition(!oldPreset.spatial_enabled && oldPreset.spatial_mix == 0.4)
        for count in [0, EQPreset.maximumBands + 1] {
            let band = EQBand(frequencyHz: 1000, gainDb: 0, qFactor: 1, filterType: .peak, enabled: true)
            let invalid = EQPreset(name: "Invalid", bands: Array(repeating: band, count: count),
                preampDb: 0, limiterEnabled: false, limiterThresholdDb: -1)
            try JSONEncoder().encode(invalid).write(to: url)
            do {
                _ = try PresetLoader().load(from: url.path)
                preconditionFailure("Host accepted an invalid filter count")
            } catch { }
        }
        print("AutoEQ → JSON → host DSP: 1, 10, 12 and 32 filters preserved; 0 and 33 rejected")
    }
}
