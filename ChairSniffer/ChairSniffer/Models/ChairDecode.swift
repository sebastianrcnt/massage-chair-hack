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
    private static let sevenSegmentDigits: [String: String] = [
        "3F": "0",
        "06": "1",
        "5B": "2",
        "4F": "3",
        "66": "4",
        "6D": "5",
        "7D": "6",
        "07": "7",
        "7F": "8",
        "6F": "9"
    ]

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
              let b2 = byteValue(bytes, 2),
              let b3 = byteValue(bytes, 3) else {
            return "-"
        }

        let tensSegment = bytes[1]
        let onesSegmentValue = ((b3 & 0x0F) << 4) | ((b2 & 0xF0) >> 4)
        let onesSegment = String(format: "%02X", onesSegmentValue)

        guard let tens = sevenSegmentDigits[tensSegment],
              let ones = sevenSegmentDigits[onesSegment] else {
            return "-"
        }
        return "\(tens)\(ones) min"
    }

    private static func decodeAir(_ bytes: [String]) -> (state: String, strength: String) {
        guard let airValue = byteValue(bytes, 3),
              let strengthValue = byteValue(bytes, 4) else {
            return ("-", "-")
        }

        let enabled = (airValue & 0x10) != 0 ? "on" : "off"
        let strengthBits = (strengthValue & 0x60) >> 5
        let strength = [0: "1", 1: "3", 3: "5"][strengthBits] ?? "reserved"
        return (enabled, strength)
    }

    private static func decodeSpeed(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, 4) else {
            return "-"
        }

        let speedBits = (value & 0x0C) >> 2
        return [0: "1", 1: "3", 3: "5"][speedBits] ?? "reserved"
    }

    private static func decodeMotion(_ bytes: [String]) -> (active: String, back: String, leg: String) {
        guard let value = byteValue(bytes, 6) else {
            return ("-", "-", "-")
        }

        let active = (value & 0x10) != 0 ? "moving" : "idle"
        let backRaise = (value & 0x04) != 0 ? "raise" : nil
        let backRecline = (value & 0x08) != 0 ? "recline" : nil
        let legRaise = (value & 0x40) != 0 ? "raise" : nil
        let legRecline = (value & 0x20) != 0 ? "recline" : nil

        return (
            active,
            [backRaise, backRecline].compactMap { $0 }.joined(separator: " / ").nilIfEmpty ?? "off",
            [legRaise, legRecline].compactMap { $0 }.joined(separator: " / ").nilIfEmpty ?? "off"
        )
    }

    private static func decodeWidth(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, 6) else {
            return "-"
        }

        return [0: "wide", 1: "medium", 2: "narrow"][value & 0x03] ?? "reserved"
    }

    private static func decodeFootRoller(_ bytes: [String]) -> String {
        guard let value = byteValue(bytes, 6) else {
            return "-"
        }

        return (value & 0x80) != 0 ? "on" : "off"
    }

    private static func decodeHeater(_ bytes: [String]) -> String {
        guard let value = bytes.last.flatMap({ Int($0, radix: 16) }) else {
            return "-"
        }

        return (value & 0x02) != 0 ? "on" : "off"
    }

    private static func decodeArea(_ data: String) -> String {
        let bytes = bytes(from: data)
        guard let value = byteValue(bytes, 4) else {
            return "-"
        }

        return [0x09: "point", 0x0D: "full", 0x0B: "local"][value] ?? "reserved"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
