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

    static let entries = ChairSpec.commandEntries

    static func describe(_ code: String) -> Entry? {
        entries[code.uppercased()]
    }

    static let cheatSheet = ChairSpec.commandCheatSheet
}
