import SwiftUI

struct CustomHexScreen: View {
    @ObservedObject var ble: ChairBLEManager
    var showsNavigationTitle = true
    @State private var command = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Text(commandDisplay)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    Button { command = String(command.dropLast()) } label: {
                        Image(systemName: "delete.left").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(command.isEmpty)

                    Button(action: sendCommand) {
                        Image(systemName: "paperplane.fill").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ChairDecode.isFourDigitHex(command))
                }

                Text(commandDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HexKeypadFull(command: $command)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(showsNavigationTitle ? "Custom Hex" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var commandDisplay: String {
        let trimmed = normalizedCommand
        let placeholder = String(repeating: "_", count: max(0, 4 - trimmed.count))
        return trimmed + placeholder
    }

    private var commandDescription: String {
        guard ChairDecode.isFourDigitHex(normalizedCommand) else {
            return command.isEmpty ? "Enter a 4-digit hex command." : "Need \(4 - normalizedCommand.count) more digit(s)."
        }
        if let info = CommandCatalog.describe(normalizedCommand) {
            let role = info.role.rawValue
            if let note = info.note { return "\(info.name) — \(role) (\(note))" }
            return "\(info.name) — \(role)"
        }
        return "Unknown command (will still send to chair)."
    }

    private func sendCommand() {
        let value = normalizedCommand
        ble.send(command: value)
        if ChairDecode.isFourDigitHex(value) { command = "" }
    }
}

private struct HexKeypadFull: View {
    @Binding var command: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 16) {
            digitsPad
            VStack(spacing: 6) {
                Text("LETTERS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                lettersPad
            }
        }
    }

    private var digitsPad: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            key("1"); key("2"); key("3")
            key("4"); key("5"); key("6")
            key("7"); key("8"); key("9")
            Color.clear.frame(minHeight: 52)
            key("0")
            Color.clear.frame(minHeight: 52)
        }
    }

    private var lettersPad: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            key("A"); key("B"); key("C")
            key("D"); key("E"); key("F")
        }
    }

    private func key(_ digit: String) -> some View {
        Button { append(digit) } label: {
            Text(digit)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
    }

    private func append(_ digit: String) {
        guard command.count < 4 else { return }
        command.append(digit)
    }
}
