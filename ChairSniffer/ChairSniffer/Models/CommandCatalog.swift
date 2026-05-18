import Foundation

enum CommandCatalog {
    enum Role: String {
        case press
        case release
        case ack
    }

    struct Entry {
        let name: String
        let role: Role
        let note: String?
    }

    static let entries: [String: Entry] = [
        // Controls
        "0303": .init(name: "Power",            role: .press,   note: nil),
        "0322": .init(name: "Pause / Resume",   role: .press,   note: nil),
        "032D": .init(name: "Timer",            role: .press,   note: "+5 min cycle"),
        "0327": .init(name: "Speed",            role: .press,   note: "manual mode only"),
        "0363": .init(name: "Manual mode",      role: .press,   note: nil),
        "0364": .init(name: "Width",            role: .press,   note: "cycle"),
        "0330": .init(name: "Heater",           role: .press,   note: nil),

        // Posture
        "0302": .init(name: "Back raise",       role: .press,   note: nil),
        "0304": .init(name: "Back recline",     role: .press,   note: nil),
        "0307": .init(name: "Leg raise",        role: .press,   note: nil),
        "0301": .init(name: "Leg lower",        role: .press,   note: nil),
        "0306": .init(name: "Zero gravity",     role: .press,   note: nil),

        // Air
        "0375": .init(name: "Air mode",         role: .press,   note: "cycle"),
        "0315": .init(name: "Air strength",     role: .press,   note: nil),

        // Massage
        "0331": .init(name: "Foot roller",      role: .press,   note: nil),
        "032C": .init(name: "Position up",      role: .press,   note: nil),
        "032F": .init(name: "Position down",    role: .press,   note: nil),
        "0384": .init(name: "Position reset",   role: .press,   note: nil),

        // Auto modes
        "031F": .init(name: "Auto: Charging",   role: .press,   note: "충전"),
        "0391": .init(name: "Auto: Digestion",  role: .press,   note: "소화"),
        "0305": .init(name: "Auto: Classic",    role: .press,   note: "클래식"),
        "0321": .init(name: "Auto: Sleep",      role: .press,   note: "숙면"),
        "031E": .init(name: "Auto: Stretching", role: .press,   note: "스트레칭"),
        "0320": .init(name: "Auto: Healing",    role: .press,   note: "힐링"),

        // Releases (shared)
        "0355": .init(name: "Release",          role: .release, note: nil),
        "0336": .init(name: "Release",          role: .release, note: "speed / stretch"),
        "0339": .init(name: "Release",          role: .release, note: "manual / roller"),

        // ACKs
        "1103": .init(name: "Beep",             role: .ack,     note: nil),
        "1104": .init(name: "Double beep",      role: .ack,     note: "cycle complete"),
        "1100": .init(name: "Position reached", role: .ack,     note: nil),
    ]

    static func describe(_ code: String) -> Entry? {
        entries[code.uppercased()]
    }

    static let cheatSheet: [(code: String, label: String)] = [
        ("0303", "Power"),
        ("0322", "Pause"),
        ("032D", "Timer"),
        ("0330", "Heater"),
        ("0306", "Zero G"),
        ("0364", "Width"),
        ("0302", "Back ↑"),
        ("0304", "Back ↓"),
        ("0307", "Leg ↑"),
        ("0301", "Leg ↓"),
        ("0331", "Foot roller"),
        ("032C", "Pos ↑"),
        ("032F", "Pos ↓"),
        ("0384", "Reset"),
        ("0375", "Air"),
        ("0315", "Air str"),
        ("0327", "Speed"),
        ("031F", "충전"),
        ("0391", "소화"),
        ("0305", "클래식"),
        ("0321", "숙면"),
        ("031E", "스트레칭"),
        ("0320", "힐링"),
    ]
}
