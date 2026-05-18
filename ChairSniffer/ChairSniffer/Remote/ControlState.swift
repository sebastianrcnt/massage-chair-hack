import Foundation

struct ControlState: Equatable {
    let isOn: Bool
    let label: String?
}

enum LiveStateLookup {
    static func state(for code: String, ble: ChairBLEManager) -> ControlState? {
        guard ble.isConnected else { return nil }
        let decoded = ble.decodedStatus

        switch code.uppercased() {
        // Toggles
        case "0330":
            return toggleState(decoded.heater)
        case "0375":
            return toggleState(decoded.air)
        case "0331":
            return toggleState(decoded.footRoller)

        // Levels
        case "0315":
            return levelState(decoded.airStrength)
        case "0327":
            return levelState(decoded.speed)
        case "0364":
            return widthState(decoded.width)

        // Auto modes
        case "031F", "0391", "0305", "0321", "031E", "0320":
            guard let label = autoModeLabels[code.uppercased()] else { return nil }
            return ControlState(isOn: ble.currentAutoMode == label, label: nil)

        default:
            return nil
        }
    }

    private static let autoModeLabels: [String: String] = [
        "031F": "충전",
        "0391": "소화",
        "0305": "클래식",
        "0321": "숙면",
        "031E": "스트레칭",
        "0320": "힐링",
    ]

    private static func toggleState(_ value: String) -> ControlState? {
        switch value {
        case "on":  return ControlState(isOn: true,  label: nil)
        case "off": return ControlState(isOn: false, label: nil)
        default:    return nil
        }
    }

    private static func levelState(_ value: String) -> ControlState? {
        guard ["1", "3", "5"].contains(value) else { return nil }
        return ControlState(isOn: false, label: "Lv \(value)")
    }

    private static func widthState(_ value: String) -> ControlState? {
        switch value {
        case "wide":   return ControlState(isOn: false, label: "넓게")
        case "medium": return ControlState(isOn: false, label: "보통")
        case "narrow": return ControlState(isOn: false, label: "좁게")
        default:       return nil
        }
    }
}
