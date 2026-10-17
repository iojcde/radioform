import Foundation

/// Store exclusions by stable CoreAudio UID, including disconnected devices.
/// Existing users and newly connected outputs keep the default EQ behavior.
public struct OutputDevicePreferences: Codable, Equatable {
    public private(set) var disabledDeviceUIDs: Set<String>

    public init(disabledDeviceUIDs: Set<String> = []) {
        self.disabledDeviceUIDs = disabledDeviceUIDs
    }

    public func isEnabled(uid: String) -> Bool { !disabledDeviceUIDs.contains(uid) }

    public mutating func setEnabled(_ enabled: Bool, uid: String) {
        if enabled { disabledDeviceUIDs.remove(uid) }
        else { disabledDeviceUIDs.insert(uid) }
    }
}

public struct OutputDevicePreferenceStore {
    public let url: URL

    public init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!.appendingPathComponent("Radioform/output-devices.json")) {
        self.url = url
    }

    public func load() throws -> OutputDevicePreferences {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(OutputDevicePreferences.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return OutputDevicePreferences()
        }
    }

    public func save(_ preferences: OutputDevicePreferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(preferences)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
