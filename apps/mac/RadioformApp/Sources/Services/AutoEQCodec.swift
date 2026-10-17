import Foundation

enum AutoEQError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// AutoEQ / Equalizer APO parametric text. Values are never silently clamped.
enum AutoEQCodec {
    static let maximumFileSize = 1_048_576
    private static let number = #"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"#

    static func decode(_ text: String, name: String) throws -> EQPreset {
        guard text.utf8.count <= maximumFileSize else {
            throw AutoEQError.invalid("AutoEQ files must be smaller than 1 MB.")
        }
        let preampPattern = try NSRegularExpression(pattern: "^Preamp:\\s*" + number + "\\s*dB$", options: .caseInsensitive)
        let filterPattern = try NSRegularExpression(pattern:
            #"^Filter\s+(\d+):\s*(ON|OFF)\s+(\w+)\s+Fc\s+"# + number +
            #"\s*Hz(?:\s+Gain\s+"# + number + #"\s*dB)?(?:\s+Q\s+"# + number + #")?\s*$"#,
            options: .caseInsensitive)
        var preamp: Float?
        var filters: [Int: EQBand] = [:]

        func value(_ token: String, field: String, range: ClosedRange<Float>, line: Int) throws -> Float {
            guard let value = Float(token), value.isFinite, range.contains(value) else {
                throw AutoEQError.invalid("Line \(line): \(field) must be between \(range.lowerBound) and \(range.upperBound).")
            }
            return value
        }

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.replacingOccurrences(of: "\u{feff}", with: "")
                .components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = preampPattern.firstMatch(in: line, range: range) {
                guard preamp == nil else { throw AutoEQError.invalid("Line \(lineNumber): duplicate preamp.") }
                preamp = try value((line as NSString).substring(with: match.range(at: 1)),
                    field: "preamp (dB)", range: -12...12, line: lineNumber)
                continue
            }
            if line.lowercased().hasPrefix("graphiceq:") {
                throw AutoEQError.invalid("Choose an AutoEQ ParametricEQ .txt file. GraphicEQ curves are not supported.")
            }
            guard let match = filterPattern.firstMatch(in: line, range: range) else {
                throw AutoEQError.invalid("Line \(lineNumber): expected a Preamp or parametric Filter entry.")
            }
            func token(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : (line as NSString).substring(with: range)
            }
            guard let index = Int(token(1)!), index > 0, filters[index] == nil else {
                throw AutoEQError.invalid("Line \(lineNumber): filter numbers must be positive and unique.")
            }
            guard filters.count < EQPreset.maximumBands else { throw AutoEQError.invalid("Radioform supports up to \(EQPreset.maximumBands) filters per preset.") }
            let type: FilterType
            switch token(3)!.uppercased() {
            case "PK": type = .peak
            case "LS", "LSC", "LSQ": type = .lowShelf
            case "HS", "HSC", "HSQ": type = .highShelf
            case "LP", "LPQ": type = .lowPass
            case "HP", "HPQ": type = .highPass
            case "NO": type = .notch
            case "BP": type = .bandPass
            default: throw AutoEQError.invalid("Line \(lineNumber): unsupported filter type \(token(3)!).")
            }
            let needsGain = type == .peak || type == .lowShelf || type == .highShelf
            guard !needsGain || token(5) != nil, type != .peak || token(6) != nil else {
                throw AutoEQError.invalid("Line \(lineNumber): this filter is missing Gain or Q.")
            }
            filters[index] = EQBand(
                frequencyHz: try value(token(4)!, field: "frequency (Hz)", range: 20...20000, line: lineNumber),
                gainDb: try value(token(5) ?? "0", field: "gain (dB)", range: -12...12, line: lineNumber),
                qFactor: try value(token(6) ?? "0.70710677", field: "Q", range: 0.1...10, line: lineNumber),
                filterType: type, enabled: token(2)!.uppercased() == "ON")
        }
        guard !filters.isEmpty else { throw AutoEQError.invalid("The file contains no parametric filters.") }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return EQPreset(name: String((trimmedName.isEmpty ? "Imported AutoEQ" : trimmedName).prefix(64)),
            bands: filters.keys.sorted().compactMap { filters[$0] }, preampDb: preamp ?? 0,
            limiterEnabled: false, limiterThresholdDb: -1)
    }

    static func encode(_ preset: EQPreset) throws -> String {
        guard preset.isValid() else { throw AutoEQError.invalid("The current preset has invalid parameters.") }
        var lines = ["Preamp: \(preset.preampDb) dB"]
        for (index, band) in preset.bands.enumerated() {
            let code: String
            switch band.filterType {
            case .peak: code = "PK"
            case .lowShelf: code = "LSC"
            case .highShelf: code = "HSC"
            case .lowPass: code = "LPQ"
            case .highPass: code = "HPQ"
            case .notch: code = "NO"
            case .bandPass: code = "BP"
            }
            let gain = (band.filterType == .peak || band.filterType == .lowShelf || band.filterType == .highShelf)
                ? " Gain \(band.gainDb) dB" : ""
            lines.append("Filter \(index + 1): \(band.enabled ? "ON" : "OFF") \(code) Fc \(band.frequencyHz) Hz\(gain) Q \(band.qFactor)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
