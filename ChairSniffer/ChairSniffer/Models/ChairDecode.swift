import Foundation

struct ChairDecodedStatus {
    var timer: String = "-"
    var air: String = "-"
    var airStrength: String = "-"
    var speed: String = "-"
    var motion: String = "-"
    var back: String = "-"
    var leg: String = "-"
    var width: String = "-"
    var footRoller: String = "-"
    var heater: String = "-"
    var area: String = "-"
}

enum ChairDecode {
    static func bytes(from hex: String) -> [String] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return [] }

        var result: [String] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            result.append(String(cleaned[index..<next]))
            index = next
        }
        return result
    }

    static func spaced(_ hex: String) -> String {
        bytes(from: hex).joined(separator: " ")
    }

    static func isFourDigitHex(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy { $0.isHexDigit }
    }

    static func decode(short: String, long: String) -> ChairDecodedStatus {
        var status = ChairDecodedStatus()

        if !short.isEmpty {
            status.area = decodeArea(short)
        }

        guard !long.isEmpty else {
            return status
        }

        let bytes = bytes(from: long)
        status.timer = decodeTimer(bytes)
        status.air = decodeAir(bytes).state
        status.airStrength = decodeAir(bytes).strength
        status.speed = decodeSpeed(bytes)
        status.motion = decodeMotion(bytes).active
        status.back = decodeMotion(bytes).back
        status.leg = decodeMotion(bytes).leg
        status.width = decodeWidth(bytes)
        status.footRoller = decodeFootRoller(bytes)
        status.heater = decodeHeater(bytes)
        return status
    }

    private static func byteValue(_ bytes: [String], _ index: Int) -> Int? {
        guard bytes.indices.contains(index), bytes[index].count == 2 else { return nil }
        return Int(bytes[index], radix: 16)
    }

    private static func decodeTimer(_ bytes: [String]) -> String {
        guard bytes.count >= 4,
              let b2 = byteValue(bytes, ChairSpec.timerOnesLowByteIndex),
              let b3 = byteValue(bytes, ChairSpec.timerOnesHighByteIndex) else {
            return "-"
        }

        let tensSegment = bytes[ChairSpec.timerTensByteIndex]
        let onesHigh = (b3 & Int(ChairSpec.timerOnesHighMask)) >> ChairSpec.timerOnesHighShift
        let onesLow = (b2 & Int(ChairSpec.timerOnesLowMask)) >> ChairSpec.timerOnesLowShift
        let onesSegmentValue = (onesHigh << 4) | onesLow
        let onesSegment = String(format: "%02X", onesSegmentValue)

        guard let tens = ChairSpec.sevenSegmentDigits[tensSegment],
              let ones = ChairSpec.sevenSegmentDigits[onesSegment] else {
            return "-"
        }
        return "\(tens)\(ones) min"
    }

    private static func decodeAir(_ bytes: [String]) -> (state: String, strength: String) {
        guard let airValue = byteValue(bytes, ChairSpec.airByteIndex),
              let strengthValue = byteValue(bytes, ChairSpec.airStrengthByteIndex) else {
            return ("-", "-")
        }

        let enabled = (airValue & Int(ChairSpec.airMask)) != 0 ? "on" : "off"
        let strengthBits = (strengthValue & Int(ChairSpec.airStrengthMask)) >> ChairSpec.airStrengthShift
        let strength = ChairSpec.level135Values[strengthBits] ?? "reserved"
        return (enabled, strength)
    }

    private static func decodeSpeed(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, ChairSpec.speedByteIndex) else {
            return "-"
        }

        let speedBits = (value & Int(ChairSpec.speedMask)) >> ChairSpec.speedShift
        return ChairSpec.level135Values[speedBits] ?? "reserved"
    }

    private static func decodeMotion(_ bytes: [String]) -> (active: String, back: String, leg: String) {
        guard let value = byteValue(bytes, ChairSpec.motionActiveByteIndex) else {
            return ("-", "-", "-")
        }

        let active = (value & Int(ChairSpec.motionActiveMask)) != 0 ? "moving" : "idle"
        let backRaise = (value & Int(ChairSpec.backRaiseMask)) != 0 ? "raise" : nil
        let backRecline = (value & Int(ChairSpec.backReclineMask)) != 0 ? "recline" : nil
        let legRaise = (value & Int(ChairSpec.legRaiseMask)) != 0 ? "raise" : nil
        let legRecline = (value & Int(ChairSpec.legReclineMask)) != 0 ? "recline" : nil

        return (
            active,
            [backRaise, backRecline].compactMap { $0 }.joined(separator: " / ").nilIfEmpty ?? "off",
            [legRaise, legRecline].compactMap { $0 }.joined(separator: " / ").nilIfEmpty ?? "off"
        )
    }

    private static func decodeWidth(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, ChairSpec.widthByteIndex) else {
            return "-"
        }

        let widthBits = (value & Int(ChairSpec.widthMask)) >> ChairSpec.widthShift
        return ChairSpec.widthValues[widthBits] ?? "reserved"
    }

    private static func decodeFootRoller(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, ChairSpec.footRollerByteIndex) else {
            return "-"
        }

        return (value & Int(ChairSpec.footRollerMask)) != 0 ? "on" : "off"
    }

    private static func decodeHeater(_ bytes: [String]) -> String {
        guard let value = ChairSpec.heaterByteIndex == ChairSpec.lastByteIndex
                ? bytes.last.flatMap({ Int($0, radix: 16) })
                : byteValue(bytes, ChairSpec.heaterByteIndex) else {
            return "-"
        }

        return (value & Int(ChairSpec.heaterMask)) != 0 ? "on" : "off"
    }

    private static func decodeArea(_ data: String) -> String {
        let bytes = bytes(from: data)
        guard let value = byteValue(bytes, ChairSpec.areaByteIndex) else {
            return "-"
        }

        let areaBits = (value & Int(ChairSpec.areaMask)) >> ChairSpec.areaShift
        return ChairSpec.shortAreaValues[areaBits] ?? "reserved"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
