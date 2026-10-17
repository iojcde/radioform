import Foundation
import CRadioformDSP

@main
struct DSPProcessorTests {
    static func main() {
        let processor = DSPProcessor(sampleRate: 48000)
        let group = DispatchGroup()
        let control = DispatchQueue(label: "test.dsp.control")
        let audio = DispatchQueue(label: "test.dsp.audio")
        control.async(group: group) {
            for i in 0..<2000 {
                var preset = processor.createFlatPreset()
                preset.num_bands = i % 2 == 0 ? 1 : UInt32(RADIOFORM_MAX_BANDS)
                preset.spatial_enabled = i % 3 == 0
                preset.spatial_mix = Float(i % 101) / 100
                precondition(processor.applyPreset(preset))
                if i % 100 == 0 { precondition(processor.setSampleRate(48000)) }
            }
        }
        audio.async(group: group) {
            let input = [Float](repeating: 0.1, count: 512)
            var output = [Float](repeating: 0, count: 512)
            for _ in 0..<2000 {
                processor.processInterleaved(input, output: &output, frameCount: 256)
                precondition(output.allSatisfy { $0.isFinite && abs($0) < 1 })
            }
            var tooSmall: [Float] = [123]
            processor.processInterleaved(input, output: &tooSmall, frameCount: 256)
            precondition(tooSmall == [123])
        }
        precondition(group.wait(timeout: .now() + 30) == .success)
        print("Concurrent preset/sample-rate updates and rendering completed; short output rejected")
    }
}
