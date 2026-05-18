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
        case "032D":
            return timerState(decoded.timer)
        case "0363":
            return ControlState(isOn: ble.isManualMode, label: ble.manualTechnique ?? "수동")
        case "0330":
            return toggleState(decoded.heater)
        case "0375":
            return toggleState(decoded.air)
        case "0331":
            return toggleState(decoded.footRoller)
        case "0315":
            return levelState(decoded.airStrength)
        case "0327":
            return speedState(decoded.speed)
        case "0364":
            if ble.isWidthAutoCycling {
                return ControlState(isOn: false, label: "자동")
            }
            return widthState(decoded.width)
        default:
            return nil
        }
    }

    private static func toggleState(_ value: String) -> ControlState? {
        switch value {
        case "on":  return ControlState(isOn: true,  label: nil)
        case "off": return ControlState(isOn: false, label: nil)
        default:    return nil
        }
    }

    private static func levelState(_ value: String) -> ControlState? {
        switch value {
        case "1": return ControlState(isOn: false, label: "약하게")
        case "3": return ControlState(isOn: false, label: "중간")
        case "5": return ControlState(isOn: false, label: "강하게")
        default:  return nil
        }
    }

    private static func speedState(_ value: String) -> ControlState? {
        switch value {
        case "1": return ControlState(isOn: false, label: "느리게")
        case "3": return ControlState(isOn: false, label: "중간")
        case "5": return ControlState(isOn: false, label: "빠르게")
        default:  return nil
        }
    }

    private static func widthState(_ value: String) -> ControlState? {
        switch value {
        case "wide":   return ControlState(isOn: false, label: "넓게")
        case "medium": return ControlState(isOn: false, label: "중간")
        case "narrow": return ControlState(isOn: false, label: "좁게")
        default:       return nil
        }
    }

    private static func timerState(_ value: String) -> ControlState? {
        guard value != "-" else { return nil }
        let minutes = value.split(separator: " ").first.map(String.init) ?? value
        return ControlState(isOn: false, label: "\(minutes)분")
    }
}
