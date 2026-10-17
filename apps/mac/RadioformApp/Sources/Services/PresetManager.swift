import Foundation

enum PresetError: Error {
    case invalidPreset
    case fileNotFound
    case encodingFailed
    case decodingFailed
}

/// Manages loading, saving, and organizing presets
class PresetManager: ObservableObject {
    static let shared = PresetManager()
    static let customPresetName = "Custom"
    static let preampFocusIndex = -1

    @Published var bundledPresets: [EQPreset] = []
    @Published var userPresets: [EQPreset] = []
    @Published var currentPreset: EQPreset?
    @Published var isEnabled: Bool = true
    @Published var currentBands: [Float] = Array(repeating: 0, count: 10)  // Default editor layout

    @Published private(set) var currentBandCount: Int = 10

    @Published var currentBandEnabled: [Bool] = Array(repeating: false, count: 10)

    // Per-band advanced settings
    @Published var currentQFactors: [Float] = Array(repeating: 1.0, count: 10)
    @Published var currentFilterTypes: [FilterType] = Array(repeating: .peak, count: 10)
    @Published var currentFrequencies: [Float] = EQBand.standardFrequencies

    @Published var currentSpatialEnabled = false
    @Published var currentSpatialMix: Float = 0.4

    // Global settings
    @Published var currentPreampDb: Float = 0.0
    @Published var currentLimiterEnabled: Bool = true
    @Published var currentLimiterThresholdDb: Float = -1.0

    // Focus mode state
    @Published var focusedBandIndex: Int? = nil   // nil = no focus, nonnegative = band, -1 = preamp

    // Custom preset state
    @Published var isCustomPreset: Bool = false
    @Published var isEditingPresetName: Bool = false
    @Published var isSavingPreset: Bool = false

    // Cached computed values (updated when presets change)
    private(set) var allPresets: [EQPreset] = []
    private(set) var userPresetIDs: Set<EQPreset.ID> = []

    private let userPresetsURL: URL
    // Timers
    private var audioApplyTimer: Timer?

    private convenience init() {
        // Get user presets directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let presetsURL =
            appSupport
            .appendingPathComponent("Radioform")
            .appendingPathComponent("Presets")

        self.init(userPresetsURL: presetsURL)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: userPresetsURL,
            withIntermediateDirectories: true
        )

        loadAllPresets()

        // Load current preset from IPC
        let loadedPreset = IPCController.shared.getCurrentPreset()

        // Apply the loaded preset (ensures UI sync), or default to "Flat"
        if let preset = loadedPreset {
            applyPreset(preset)
        } else if let flatPreset = bundledPresets.first(where: { $0.name == "Flat" }) {
            applyPreset(flatPreset)
        }
    }

    /// Create an isolated library without loading or applying a preset.
    init(userPresetsURL: URL) {
        self.userPresetsURL = userPresetsURL
    }

    /// Load all presets (bundled + user)
    func loadAllPresets() {
        bundledPresets = loadBundledPresets()
        userPresets = loadUserPresets()
        // Update cached values
        allPresets = bundledPresets + userPresets
        userPresetIDs = Set(userPresets.map { $0.id })
    }

    /// Load bundled presets from app Resources
    private func loadBundledPresets() -> [EQPreset] {
        var presetsPath: String?

        // Debug info
        print("[PresetManager] Looking for bundled presets...")
        print("[PresetManager] Bundle.main.resourcePath: \(Bundle.main.resourcePath ?? "nil")")
        print("[PresetManager] Bundle.main.executablePath: \(Bundle.main.executablePath ?? "nil")")
        print("[PresetManager] CWD: \(FileManager.default.currentDirectoryPath)")

        // Try bundle resources first (production)
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = (resourcePath as NSString).appendingPathComponent("Presets")
            print("[PresetManager] Trying bundle path: \(bundlePath)")
            if FileManager.default.fileExists(atPath: bundlePath) {
                presetsPath = bundlePath
                print("[PresetManager] Found at bundle path")
            }
        }

        // Fall back to source directory (development - swift build)
        if presetsPath == nil {
            if let executablePath = Bundle.main.executablePath {
                let executableDir = (executablePath as NSString).deletingLastPathComponent

                // For .build/debug/RadioformApp -> Sources/Resources/Presets
                let debugPath = (executableDir as NSString).appendingPathComponent(
                    "../../Sources/Resources/Presets")
                let normalizedDebugPath = (debugPath as NSString).standardizingPath
                print("[PresetManager] Trying debug path: \(normalizedDebugPath)")
                if FileManager.default.fileExists(atPath: normalizedDebugPath) {
                    presetsPath = normalizedDebugPath
                    print("[PresetManager] Found at debug path")
                }
            }
        }

        // Try finding based on current working directory
        if presetsPath == nil {
            let cwd = FileManager.default.currentDirectoryPath
            let possiblePaths = [
                "\(cwd)/Sources/Resources/Presets",
                "\(cwd)/apps/mac/RadioformApp/Sources/Resources/Presets",
                // Add home directory fallback for when launched from various locations
                NSString(string: "~/radioform/apps/mac/RadioformApp/Sources/Resources/Presets")
                    .expandingTildeInPath,
                NSString(string: "~/radioform/apps/mac/RadioformApp/Sources/Resources/Presets")
                    .expandingTildeInPath,
            ]
            for path in possiblePaths {
                print("[PresetManager] Trying CWD path: \(path)")
                if FileManager.default.fileExists(atPath: path) {
                    presetsPath = path
                    print("[PresetManager] Found at CWD path")
                    break
                }
            }
        }

        guard let finalPath = presetsPath else {
            print("[PresetManager] ERROR: Presets directory not found anywhere!")
            return []
        }

        print("[PresetManager] Loading presets from: \(finalPath)")

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: finalPath) else {
            print("[PresetManager] ERROR: Failed to read presets directory")
            return []
        }

        let jsonFiles = files.filter { $0.hasSuffix(".json") }
        print("[PresetManager] Found \(jsonFiles.count) JSON files: \(jsonFiles)")

        let presets =
            jsonFiles
            .compactMap { filename -> EQPreset? in
                let url = URL(fileURLWithPath: finalPath).appendingPathComponent(filename)
                do {
                    return try loadPreset(from: url)
                } catch {
                    print("[PresetManager] ERROR: Failed to load \(filename): \(error)")
                    return nil
                }
            }
            .sorted { $0.name < $1.name }

        print(
            "[PresetManager] Loaded \(presets.count) bundled presets: \(presets.map { $0.name })")
        return presets
    }

    /// Load user presets from Application Support
    private func loadUserPresets() -> [EQPreset] {
        print("[PresetManager] Loading user presets from: \(userPresetsURL.path)")

        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: userPresetsURL,
                includingPropertiesForKeys: nil
            )
        else {
            print("[PresetManager] No user presets directory or empty")
            return []
        }

        let presets =
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? loadPreset(from: $0) }
            .sorted { $0.name < $1.name }

        print("[PresetManager] Loaded \(presets.count) user presets: \(presets.map { $0.name })")
        return presets
    }

    /// Load preset from file
    private func loadPreset(from url: URL) throws -> EQPreset {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(EQPreset.self, from: data)
    }

    /// Save user preset
    func savePreset(_ preset: EQPreset) throws {
        guard preset.isValid() else {
            throw PresetError.invalidPreset
        }

        let filename = sanitizeFilename(preset.name) + ".json"
        let url = userPresetsURL.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)

        loadAllPresets()
    }

    /// Delete user preset
    func deletePreset(_ preset: EQPreset) throws {
        let filename = sanitizeFilename(preset.name) + ".json"
        let url = userPresetsURL.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)

        loadAllPresets()
    }

    /// Apply preset via IPC
    func applyPreset(_ preset: EQPreset) {
        guard preset.isValid() else { return }
        audioApplyTimer?.invalidate()
        do {
            try IPCController.shared.applyPreset(isEnabled ? preset : EQPreset.flat())
            currentPreset = preset

            // Reset custom preset state
            isCustomPreset = false
            isEditingPresetName = false

            // Keep exact parametric values when showing the preset in the editor.
            focusedBandIndex = nil
            currentBandCount = preset.bands.count
            let slots = preset.editableBands()
            currentBands = slots.map(\.gainDb)
            currentQFactors = slots.map(\.qFactor)
            currentFilterTypes = slots.map(\.filterType)
            currentFrequencies = slots.map(\.frequencyHz)
            currentBandEnabled = slots.map(\.enabled)
            currentSpatialEnabled = preset.spatialEnabled
            currentSpatialMix = preset.spatialMix
            currentPreampDb = preset.preampDb
            currentLimiterEnabled = preset.limiterEnabled
            currentLimiterThresholdDb = preset.limiterThresholdDb

        } catch {
            print("Failed to apply preset: \(error)")
        }
    }

    /// Update a single band and apply immediately (batched to avoid multiple redraws)
    func updateBand(index: Int, gainDb: Float) {
        guard (0..<currentBandCount).contains(index) else { return }

        // Update band value without triggering @Published (direct array mutation)
        // We'll manually notify once at the end
        let needsCustomUpdate = !isCustomPreset && isEnabled
        let needsPresetClear = currentPreset != nil && isEnabled

        // Batch all state changes together
        currentBands[index] = gainDb
        currentBandEnabled[index] = true

        // Only update these if needed (avoids redundant publishes during drag)
        if needsPresetClear {
            currentPreset = nil
        }
        if needsCustomUpdate {
            isCustomPreset = true
        }

        // Reset inactivity timer if this band is focused
        if focusedBandIndex != nil {
            resetInactivityTimer()
        }

        // Apply to audio (doesn't trigger UI updates)
        applyCurrentStateToAudio()
    }

    /// Apply current state to audio, throttled to prevent IPC flooding during rapid updates
    private func applyCurrentStateToAudio() {
        // Throttle: coalesce rapid calls (drag, scroll) into one IPC write per ~30ms
        audioApplyTimer?.invalidate()
        audioApplyTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.doApplyCurrentStateToAudio()
        }
    }

    private func doApplyCurrentStateToAudio() {
        let enabled = isEnabled
        let bands = currentFrequencies.prefix(currentBandCount).enumerated().map { index, frequency in
            let gain = enabled ? currentBands[index] : 0.0
            return EQBand(
                frequencyHz: frequency,
                gainDb: gain,
                qFactor: currentQFactors[index],
                filterType: currentFilterTypes[index],
                enabled: enabled && currentBandEnabled[index]
            )
        }

        // When disabled, force neutral global settings to ensure a true bypass.
        let preampDb = enabled ? currentPreampDb : 0.0
        let limiterEnabled = enabled ? currentLimiterEnabled : false
        let limiterThresholdDb = enabled ? currentLimiterThresholdDb : 0.0

        let customPreset = EQPreset(
            name: "Custom",
            bands: bands,
            preampDb: preampDb,
            limiterEnabled: limiterEnabled,
            limiterThresholdDb: limiterThresholdDb,
            spatialEnabled: enabled && currentSpatialEnabled, spatialMix: currentSpatialMix
        )

        do {
            try IPCController.shared.applyPreset(customPreset)
        } catch {
            print("Failed to apply current state: \(error)")
        }
    }

    /// Apply current state (either enabled with current bands, or disabled with all zeros)
    func applyCurrentState() {
        if isEnabled {
            currentPreset = nil
            isCustomPreset = true
        }
        applyCurrentStateToAudio()
    }

    /// Toggle EQ enabled state
    func toggleEnabled() {
        isEnabled.toggle()
        applyCurrentState()
    }

    func updateBandEnabled(index: Int, enabled: Bool) {
        guard (0..<currentBandCount).contains(index) else { return }
        currentBandEnabled[index] = enabled
        markCustomIfNeeded()
        applyCurrentStateToAudio()
    }

    /// Import into the preset library, then apply without changing global bypass.
    func importAutoEQ(from url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: AutoEQCodec.maximumFileSize + 1) ?? Data()
        guard data.count <= AutoEQCodec.maximumFileSize,
              let text = String(data: data, encoding: .utf8) else {
            throw AutoEQError.invalid("Choose a UTF-8 AutoEQ file smaller than 1 MB.")
        }
        var preset = try AutoEQCodec.decode(text, name: url.deletingPathExtension().lastPathComponent)
        preset.name = generateUniqueName(preset.name)
        try savePreset(preset)
        applyPreset(userPresets.first(where: { $0.name == preset.name }) ?? preset)
    }

    func exportAutoEQ(to url: URL) throws {
        try AutoEQCodec.encode(configuredPreset()).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Configuration rather than the temporary flat preset sent during bypass.
    func configuredPreset() -> EQPreset {
        let bands = (0..<currentBandCount).map { index in
            EQBand(frequencyHz: currentFrequencies[index], gainDb: currentBands[index],
                qFactor: currentQFactors[index], filterType: currentFilterTypes[index],
                enabled: currentBandEnabled[index])
        }
        return EQPreset(name: currentPreset?.name ?? Self.customPresetName, bands: bands,
            preampDb: currentPreampDb, limiterEnabled: currentLimiterEnabled,
            limiterThresholdDb: currentLimiterThresholdDb,
            spatialEnabled: currentSpatialEnabled, spatialMix: currentSpatialMix)
    }

    /// Add a neutral filter without changing the existing response.
    func addBand() {
        guard currentBandCount < EQPreset.maximumBands else { return }
        let index = currentBandCount
        if index == currentBands.count {
            currentBands.append(0)
            currentFrequencies.append(1000)
            currentQFactors.append(1)
            currentFilterTypes.append(.peak)
            currentBandEnabled.append(true)
        } else {
            currentBands[index] = 0
            currentFrequencies[index] = 1000
            currentQFactors[index] = 1
            currentFilterTypes[index] = .peak
            currentBandEnabled[index] = true
        }
        currentBandCount += 1
        focusedBandIndex = index
        markCustomIfNeeded()
        applyCurrentStateToAudio()
    }

    func removeBand(at index: Int) {
        guard currentBandCount > 1, (0..<currentBandCount).contains(index) else { return }
        currentBands.remove(at: index)
        currentFrequencies.remove(at: index)
        currentQFactors.remove(at: index)
        currentFilterTypes.remove(at: index)
        currentBandEnabled.remove(at: index)
        currentBandCount -= 1
        if let focused = focusedBandIndex, focused >= 0 {
            focusedBandIndex = focused == index ? nil : (focused > index ? focused - 1 : focused)
        }
        markCustomIfNeeded()
        applyCurrentStateToAudio()
    }

    // MARK: - Band Advanced Settings

    /// Update Q factor for a specific band
    func updateBandQ(index: Int, qFactor: Float) {
        guard (0..<currentBandCount).contains(index) else { return }
        currentBandEnabled[index] = true
        currentQFactors[index] = max(0.1, min(10.0, qFactor))
        markCustomIfNeeded()
        resetInactivityTimer()
        applyCurrentStateToAudio()
    }

    /// Update filter type for a specific band
    func updateBandFilterType(index: Int, filterType: FilterType) {
        guard (0..<currentBandCount).contains(index) else { return }
        currentBandEnabled[index] = true
        currentFilterTypes[index] = filterType
        markCustomIfNeeded()
        resetInactivityTimer()
        applyCurrentStateToAudio()
    }

    /// Update frequency for a specific band
    func updateBandFrequency(index: Int, frequencyHz: Float) {
        guard (0..<currentBandCount).contains(index) else { return }
        currentBandEnabled[index] = true
        currentFrequencies[index] = max(20, min(20000, frequencyHz))
        markCustomIfNeeded()
        resetInactivityTimer()
        applyCurrentStateToAudio()
    }

    func updateSpatialEnabled(_ enabled: Bool) {
        currentSpatialEnabled = enabled
        markCustomIfNeeded()
        applyCurrentStateToAudio()
    }

    func updateSpatialMix(_ amount: Float) {
        guard amount.isFinite else { return }
        currentSpatialMix = max(0, min(1, amount))
        markCustomIfNeeded()
        applyCurrentStateToAudio()
    }

    // MARK: - Global Settings

    /// Update preamp gain
    func updatePreamp(gainDb: Float) {
        currentPreampDb = max(-12.0, min(12.0, gainDb))
        markCustomIfNeeded()
        if focusedBandIndex != nil {
            resetInactivityTimer()
        }
        applyCurrentStateToAudio()
    }

    /// Update limiter enabled state
    func updateLimiterEnabled(_ enabled: Bool) {
        currentLimiterEnabled = enabled
        markCustomIfNeeded()
        resetInactivityTimer()
        applyCurrentStateToAudio()
    }

    /// Update limiter threshold
    func updateLimiterThreshold(db: Float) {
        currentLimiterThresholdDb = max(-6.0, min(0.0, db))
        markCustomIfNeeded()
        resetInactivityTimer()
        applyCurrentStateToAudio()
    }

    // MARK: - Focus Mode

    /// Toggle focus on a band (double-click behavior)
    func toggleFocusedBand(_ index: Int) {
        if focusedBandIndex == index {
            focusedBandIndex = nil
            cancelInactivityTimer()
        } else {
            focusedBandIndex = index
            resetInactivityTimer()
        }
    }

    /// Set focused band directly (used for unfocusing on empty space click)
    func setFocusedBand(_ index: Int?) {
        focusedBandIndex = index
        if index != nil {
            resetInactivityTimer()
        } else {
            cancelInactivityTimer()
        }
    }

    /// Reset the inactivity timer (no-op, timeout removed)
    func resetInactivityTimer() {
        // No timeout - band stays focused until user clicks elsewhere
    }

    /// Cancel the inactivity timer (no-op, timeout removed)
    func cancelInactivityTimer() {
        // No timeout to cancel
    }


    // MARK: - Custom Preset Management

    /// Mark as custom preset if a saved preset was active
    private func markCustomIfNeeded() {
        if currentPreset != nil && isEnabled {
            currentPreset = nil
        }
        if !isCustomPreset && isEnabled {
            isCustomPreset = true
        }
    }

    /// Validate preset name for saving
    func validatePresetName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // Check not empty
        guard !trimmed.isEmpty else { return false }

        // Check not too long
        guard trimmed.count <= 64 else { return false }

        // Check not reserved name
        guard trimmed != Self.customPresetName else { return false }

        return true
    }

    /// Generate a unique preset name by appending numbers if needed
    func generateUniqueName(_ baseName: String) -> String {
        let base = String(baseName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        let existing = Set((bundledPresets + userPresets).map { sanitizeFilename($0.name) })
        if base != Self.customPresetName && !existing.contains(sanitizeFilename(base)) { return base }
        var counter = 2
        while true {
            let suffix = " \(counter)"
            let candidate = String(base.prefix(64 - suffix.count)) + suffix
            if !existing.contains(sanitizeFilename(candidate)) { return candidate }
            counter += 1
        }
    }

    /// Save current EQ state as a custom preset
    @MainActor
    func saveCustomPreset(name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Validate
        guard validatePresetName(trimmedName) else {
            throw PresetError.invalidPreset
        }

        // Generate unique name if needed
        let finalName = generateUniqueName(trimmedName)

        var newPreset = configuredPreset()
        newPreset.name = finalName

        // Save to disk (this reloads all presets, creating new instances)
        try savePreset(newPreset)

        // Find the newly loaded version of the preset from userPresets
        // (savePreset reloads all presets with new UUIDs, so we need to find by name)
        if let reloadedPreset = userPresets.first(where: { $0.name == finalName }) {
            currentPreset = reloadedPreset
        } else {
            currentPreset = newPreset  // Fallback (shouldn't happen)
        }

        isCustomPreset = false
        isEditingPresetName = false
    }

    /// Cancel editing mode
    func cancelEditing() {
        isEditingPresetName = false
    }

    /// Sanitize filename (remove invalid characters)
    private func sanitizeFilename(_ name: String) -> String {
        var safe = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")

        if safe.count > 64 {
            safe = String(safe.prefix(64))
        }

        return safe.trimmingCharacters(in: .whitespaces)
    }
}
