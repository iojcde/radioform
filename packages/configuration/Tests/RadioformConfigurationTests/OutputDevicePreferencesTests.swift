import XCTest
@testable import RadioformConfiguration

final class OutputDevicePreferencesTests: XCTestCase {
    func testSavedExclusionSurvivesReconnectAndRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OutputDevicePreferenceStore(url: directory.appendingPathComponent("output-devices.json"))
        var preferences = try store.load()
        XCTAssertTrue(preferences.isEnabled(uid: "headphones"))
        preferences.setEnabled(false, uid: "headphones")
        preferences.setEnabled(false, uid: "disconnected-monitor")
        try store.save(preferences)
        let restored = try store.load()
        XCTAssertFalse(restored.isEnabled(uid: "headphones"))
        XCTAssertFalse(restored.isEnabled(uid: "disconnected-monitor"))
        XCTAssertTrue(restored.isEnabled(uid: "new-speakers"))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var updated = restored
        updated.setEnabled(true, uid: "headphones")
        try store.save(updated)
        XCTAssertTrue(try store.load().isEnabled(uid: "headphones"))
        XCTAssertFalse(try store.load().isEnabled(uid: "disconnected-monitor"))
    }

    func testAllOutputsCanBeDisabledAndMalformedDataIsReported() throws {
        var preferences = OutputDevicePreferences()
        ["a", "b", "c"].forEach { preferences.setEnabled(false, uid: $0) }
        XCTAssertTrue(["a", "b", "c"].filter { preferences.isEnabled(uid: $0) }.isEmpty)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{broken".utf8).write(to: file)
        XCTAssertThrowsError(try OutputDevicePreferenceStore(url: file).load())
    }
}
