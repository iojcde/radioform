import Foundation

@main
struct AutoEQTests {
    static func main() throws {
        // Representative AutoEQ ParametricEQ output, including shelf filters.
        let text = """
        Preamp: -6.3 dB
        Filter 1: ON LSC Fc 105 Hz Gain 6.5 dB Q 0.70
        Filter 2: ON PK Fc 125 Hz Gain -2.7 dB Q 0.55
        Filter 3: ON PK Fc 8445 Hz Gain 3.3 dB Q 1.61
        Filter 4: ON PK Fc 522 Hz Gain 0.7 dB Q 1.02
        Filter 5: ON PK Fc 1298 Hz Gain -1.2 dB Q 2.14
        Filter 6: ON HSC Fc 10000 Hz Gain -3.1 dB Q 0.70
        Filter 7: ON PK Fc 3158 Hz Gain -1.8 dB Q 3.67
        Filter 8: ON PK Fc 2166 Hz Gain 0.9 dB Q 3.32
        Filter 9: ON PK Fc 6639 Hz Gain 2.2 dB Q 5.82
        Filter 10: ON PK Fc 5433 Hz Gain -1.2 dB Q 5.70
        """
        let preset = try AutoEQCodec.decode(text, name: "Headphones")
        precondition(preset.bands.count == 10 && preset.preampDb == -6.3)
        precondition(preset.bands[0].filterType == .lowShelf && preset.bands[5].filterType == .highShelf)
        precondition(preset.bands[2].frequencyHz == 8445 && preset.bands[2].qFactor == 1.61)
        let exported = try AutoEQCodec.encode(preset)
        let roundTrip = try AutoEQCodec.decode(exported, name: preset.name)
        precondition(roundTrip == preset)

        let unordered = """
        # Comments, Windows line endings and OFF filters are supported.
        Filter 2: OFF PK Fc 1234.5 Hz Gain +1.2345 dB Q .71 # keep this precision
        Filter 1: ON HPQ Fc 25 Hz Q 0.9
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let small = try AutoEQCodec.decode("\u{feff}" + unordered, name: "Small")
        precondition(small.bands.count == 2 && small.bands[0].filterType == .highPass)
        precondition(!small.bands[1].enabled && small.bands[1].gainDb == 1.2345)
        let editable = small.editableBands()
        precondition(editable.count == 10 && Array(editable.prefix(2)) == small.bands)
        precondition(editable.dropFirst(2).allSatisfy { !$0.enabled && $0.gainDb == 0 })
        precondition(preset.editableBands() == preset.bands)
        let smallRoundTrip = try AutoEQCodec.decode(AutoEQCodec.encode(small), name: small.name)
        precondition(smallRoundTrip == small)

        let codes = ["PK", "LSC", "HSC", "LPQ", "HPQ", "NO", "BP"]
        for code in codes {
            let input = "Filter 1: ON \(code) Fc 100 Hz Gain 0 dB Q 1.234567"
            let original = try AutoEQCodec.decode(input, name: code)
            let result = try AutoEQCodec.decode(AutoEQCodec.encode(original), name: code)
            precondition(original == result)
        }

        for count in [11, 12, EQPreset.maximumBands] {
            let extended = (1...count).map {
                "Filter \($0): ON PK Fc \($0 * 100) Hz Gain 1 dB Q 1"
            }.joined(separator: "\n")
            let decoded = try AutoEQCodec.decode(extended, name: "Extended")
            precondition(decoded.isValid() && decoded.bands.count == count)
            precondition(decoded.editableBands() == decoded.bands)
            let result = try AutoEQCodec.decode(AutoEQCodec.encode(decoded), name: decoded.name)
            precondition(result == decoded)
        }

        let legacyData = Data("""
        {"name":"Legacy","bands":[{"frequency_hz":1000,"gain_db":0,"q_factor":1,"filter_type":0,"enabled":false}],"preamp_db":0,"limiter_enabled":false,"limiter_threshold_db":-1}
        """.utf8)
        var spatial = try JSONDecoder().decode(EQPreset.self, from: legacyData)
        precondition(!spatial.spatialEnabled && spatial.spatialMix == 0.4)
        spatial.spatialEnabled = true
        spatial.spatialMix = 0.65
        let savedSpatial = try JSONDecoder().decode(EQPreset.self, from: JSONEncoder().encode(spatial))
        precondition(savedSpatial == spatial)
        let textOnly = try AutoEQCodec.decode(AutoEQCodec.encode(spatial), name: spatial.name)
        precondition(!textOnly.spatialEnabled && textOnly.bands == spatial.bands)
        spatial.spatialMix = .nan
        precondition(!spatial.isValid())
        spatial.spatialMix = 1.01
        precondition(!spatial.isValid())

        let invalidFiles = [
            "", "GraphicEQ: 20 -1; 100 2", "Preamp: -13 dB\n" + text,
            (1...(EQPreset.maximumBands + 1)).map { "Filter \($0): ON PK Fc 200 Hz Gain 1 dB Q 1" }.joined(separator: "\n"),
            text + "\nFilter 1: ON PK Fc 200 Hz Gain 1 dB Q 1",
            "Filter 1: ON PK Fc 100 Hz Gain 13 dB Q 1",
            "Filter 1: ON PK Fc 100 Hz Gain 1 dB Q 10.1",
            "Filter 1: ON PK Fc 1e999 Hz Gain 1 dB Q 1",
            "Filter 1: ON PK Fc 10 Hz Gain 1 dB Q 1",
            "Filter 1: ON PK Fc 100 Hz Gain 1 dB",
            "Filter 1: ON UNKNOWN Fc 100 Hz Gain 1 dB Q 1",
            "Filter 0: ON PK Fc 100 Hz Gain 1 dB Q 1",
            String(repeating: "#", count: AutoEQCodec.maximumFileSize + 1)
        ]
        for invalid in invalidFiles {
            do {
                _ = try AutoEQCodec.decode(invalid, name: "Invalid")
                preconditionFailure("Accepted an invalid AutoEQ file")
            } catch is AutoEQError { }
        }
        print("AutoEQ import/export: precision, all filter types, OFF states and invalid-file checks passed")
    }
}
