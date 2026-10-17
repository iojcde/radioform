import CoreAudio

public struct AudioOutputDevice: Identifiable {
    public let id: String
    public let name: String

    /// Match the host's physical-output eligibility without opening audio units.
    public static func connectedOutputs() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { device in
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var property = AudioObjectPropertyAddress(mSelector: selector,
                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: CFString = "" as CFString
                var length = UInt32(MemoryLayout<CFString>.size)
                let status = withUnsafeMutablePointer(to: &value) { pointer in
                    AudioObjectGetPropertyData(device, &property, 0, nil, &length, pointer)
                }
                guard status == noErr else { return nil }
                return value as String
            }
            guard let uid = string(kAudioDevicePropertyDeviceUID),
                  let name = string(kAudioObjectPropertyName),
                  !name.contains("Radioform"), !name.contains("Netcat") else { return nil }
            var transport: UInt32 = 0
            var length = UInt32(MemoryLayout<UInt32>.size)
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &length, &transport) == noErr,
                  transport != kAudioDeviceTransportTypeVirtual,
                  transport != kAudioDeviceTransportTypeAggregate else { return nil }
            property.mSelector = kAudioDevicePropertyStreams
            property.mScope = kAudioDevicePropertyScopeOutput
            guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &length) == noErr,
                  length > 0 else { return nil }
            return AudioOutputDevice(id: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
