import Foundation
import Darwin
import CRadioformDSP

struct PresetJSON: Codable {
    let name: String
    let bands: [BandJSON]
    let preampDb: Float
    let limiterEnabled: Bool
    let limiterThresholdDb: Float
    let spatialEnabled: Bool?
    let spatialMix: Float?

    enum CodingKeys: String, CodingKey {
        case name, bands
        case preampDb = "preamp_db"
        case limiterEnabled = "limiter_enabled"
        case limiterThresholdDb = "limiter_threshold_db"
        case spatialEnabled = "spatial_enabled"
        case spatialMix = "spatial_mix"
    }
}

struct BandJSON: Codable {
    let frequencyHz: Float
    let gainDb: Float
    let qFactor: Float
    let filterType: Int
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case frequencyHz = "frequency_hz"
        case gainDb = "gain_db"
        case qFactor = "q_factor"
        case filterType = "filter_type"
        case enabled
    }
}

class PresetLoader {
    func load(from path: String) throws -> radioform_preset_t {
        // Inspect the opened inode, reject symlinks/FIFOs, and bound allocation
        // even if the file grows after fstat.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let limit = 1_048_576
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), (info.st_mode & 0o022) == 0,
              info.st_size >= 0, info.st_size <= limit else {
            throw CocoaError(.fileReadNoPermission)
        }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        }
        let presetJSON = try JSONDecoder().decode(PresetJSON.self, from: data)

        guard (1...Int(RADIOFORM_MAX_BANDS)).contains(presetJSON.bands.count) else {
            throw NSError(domain: "Radioform.Preset", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Presets must contain 1–\(RADIOFORM_MAX_BANDS) filters."])
        }

        // Validate before converting signed JSON integers to the C enum.
        guard presetJSON.bands.allSatisfy({
            $0.filterType >= Int(RADIOFORM_FILTER_PEAK.rawValue) &&
            $0.filterType <= Int(RADIOFORM_FILTER_BAND_PASS.rawValue)
        }) else {
            throw NSError(domain: "Radioform.Preset", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid filter type."])
        }

        var preset = radioform_preset_t()
        radioform_dsp_preset_init_flat(&preset)

        preset.num_bands = UInt32(presetJSON.bands.count)

        copyName(presetJSON.name, to: &preset)
        copyBands(presetJSON.bands, to: &preset)

        preset.spatial_enabled = presetJSON.spatialEnabled ?? false
        preset.spatial_mix = presetJSON.spatialMix ?? 0.4
        preset.preamp_db = presetJSON.preampDb
        preset.limiter_enabled = presetJSON.limiterEnabled
        preset.limiter_threshold_db = presetJSON.limiterThresholdDb

        guard radioform_dsp_preset_validate(&preset) == RADIOFORM_OK else {
            throw NSError(domain: "Radioform.Preset", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Preset parameters are outside supported limits."])
        }
        return preset
    }

    private func copyName(_ name: String, to preset: inout radioform_preset_t) {
        let nameBytes = Array(name.utf8.prefix(63))
        withUnsafeMutableBytes(of: &preset.name) { ptr in
            let buffer = ptr.baseAddress!.assumingMemoryBound(to: CChar.self)
            for (i, byte) in nameBytes.enumerated() {
                buffer[i] = CChar(bitPattern: byte)
            }
            buffer[min(nameBytes.count, 63)] = 0
        }
    }

    private func copyBands(_ bands: [BandJSON], to preset: inout radioform_preset_t) {
        for (i, band) in bands.enumerated() {
            withUnsafeMutablePointer(to: &preset.bands) { bandsPtr in
                let bandPtr = UnsafeMutableRawPointer(bandsPtr)
                    .advanced(by: i * MemoryLayout<radioform_band_t>.stride)
                    .assumingMemoryBound(to: radioform_band_t.self)

                bandPtr.pointee.frequency_hz = band.frequencyHz
                bandPtr.pointee.gain_db = band.gainDb
                bandPtr.pointee.q_factor = band.qFactor
                bandPtr.pointee.type = radioform_filter_type_t(UInt32(band.filterType))
                bandPtr.pointee.enabled = band.enabled
            }
        }
    }
}
