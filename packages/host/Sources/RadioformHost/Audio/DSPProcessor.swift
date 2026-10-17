import Foundation
import CRadioformDSP

class DSPProcessor {
    private var engine: OpaquePointer?
    // Preset/sample-rate changes mutate filter state. The render thread never
    // waits for this lock: it emits silence for a block if an update is active.
    private let stateLock = NSLock()

    init(sampleRate: UInt32) {
        engine = radioform_dsp_create(sampleRate)
    }

    deinit {
        if let engine = engine {
            radioform_dsp_destroy(engine)
        }
    }

    func applyPreset(_ preset: radioform_preset_t) -> Bool {
        guard let engine = engine else { return false }

        stateLock.lock()
        defer { stateLock.unlock() }
        var mutablePreset = preset
        if radioform_dsp_apply_preset(engine, &mutablePreset) == RADIOFORM_OK {
            return true
        }
        return false
    }

    func processInterleaved(
        _ input: [Float],
        output: inout [Float],
        frameCount: UInt32
    ) {
        guard let engine = engine else { return }
        let samples = Int(frameCount) * 2
        guard samples <= input.count, samples <= output.count else { return }
        guard stateLock.try() else {
            for i in 0..<samples { output[i] = 0 }
            return
        }
        defer { stateLock.unlock() }
        radioform_dsp_process_interleaved(engine, input, &output, frameCount)
    }

    func setSampleRate(_ sampleRate: UInt32) -> Bool {
        guard let engine = engine else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        return radioform_dsp_set_sample_rate(engine, sampleRate) == RADIOFORM_OK
    }

    func createFlatPreset() -> radioform_preset_t {
        var preset = radioform_preset_t()
        radioform_dsp_preset_init_flat(&preset)

        return preset
    }
}
