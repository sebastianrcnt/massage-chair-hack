import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()

    var body: some View {
        TabView {
            DecodedTab(ble: ble)
                .tabItem {
                    Label("Decoded", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }

            CommandsTab(ble: ble)
                .tabItem {
                    Label("Commands", systemImage: "arrow.left.arrow.right")
                }

            RawFeedTab(ble: ble)
                .tabItem {
                    Label("Raw", systemImage: "list.bullet.rectangle")
                }

        }
    }
}

private struct DecodedTab: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ConnectionPanel(ble: ble)
                    decodedPanel
                    rawStatusPanel
                }
                .screenPadding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chair Monitor")
            .toolbar {
                ScanToolbarButton(ble: ble)
            }
        }
    }

    private var decodedPanel: some View {
        let decoded = ble.decodedStatus

        return VStack(alignment: .leading, spacing: 12) {
            Text("Decoded Status")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Timer", value: decoded.timer, icon: "timer")
                MetricTile(title: "Area", value: decoded.area, icon: "scope")
                MetricTile(title: "Air", value: decoded.air, icon: "wind")
                MetricTile(title: "Air Level", value: decoded.airStrength, icon: "gauge.medium")
                MetricTile(title: "Speed", value: decoded.speed, icon: "speedometer")
                MetricTile(title: "Motion", value: decoded.motion, icon: "figure.walk.motion")
                MetricTile(title: "Back", value: decoded.back, icon: "arrow.up.and.down")
                MetricTile(title: "Leg", value: decoded.leg, icon: "arrow.up.forward")
                MetricTile(title: "Width", value: decoded.width, icon: "arrow.left.and.right")
                MetricTile(title: "Foot Roller", value: decoded.footRoller, icon: "circle.dotted")
                MetricTile(title: "Heater", value: decoded.heater, icon: "heat.waves")
            }
        }
        .panelStyle()
    }

    private var rawStatusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Frames")
                .font(.headline)

            RawLine(title: "Short", value: ble.latestShort)
            RawLine(title: "Long", value: ble.latestLong)
        }
        .panelStyle()
    }
}

private struct CommandsTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var command = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    commandComposer
                } header: {
                    Text("Send")
                }

                Section {
                    if ble.commandLogs.isEmpty {
                        ContentUnavailableView(
                            "No Commands",
                            systemImage: "arrow.left.arrow.right",
                            description: Text("Remote-chair commands and app-sent commands will appear here.")
                        )
                    } else {
                        ForEach(Array(ble.commandLogs.reversed())) { entry in
                            CommandLogRow(entry: entry)
                        }
                    }
                } header: {
                    Text("Remote / Chair Command Log")
                }
            }
            .navigationTitle("Commands")
            .toolbar {
                ScanToolbarButton(ble: ble)
            }
        }
    }

    private var commandComposer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(commandDisplay)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Command \(commandDisplay)")

                Button {
                    command = String(command.dropLast())
                } label: {
                    Image(systemName: "delete.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(command.isEmpty)
                .accessibilityLabel("Delete digit")
            }

            HexKeypad(command: $command, send: sendCommand)
        }
        .padding(.vertical, 4)
    }

    private var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var commandDisplay: String {
        let suffix = String(repeating: "-", count: max(0, 4 - normalizedCommand.count))
        return normalizedCommand + suffix
    }

    private func sendCommand() {
        let value = normalizedCommand
        ble.send(command: value)
        if ChairDecode.isFourDigitHex(value) {
            command = ""
        }
    }
}

private struct RawFeedTab: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Label("\(ble.rawLogs.count) kept", systemImage: "tray.full")
                    Text("\(ble.droppedRawLogCount) dropped")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        ble.scan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Scan again")
                }
                .font(.caption)
                .padding(.horizontal, 16)

                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        Text(ble.rawTerminalText.isEmpty ? "waiting for BLE notifications..." : ble.rawTerminalText)
                            .id("terminal-end")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .frame(height: 520)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .onChange(of: ble.rawLogs.count) { _, _ in
                        proxy.scrollTo("terminal-end", anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Raw Feed")
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct HexKeypad: View {
    @Binding var command: String
    let send: () -> Void

    private let rows = [
        ["0", "1", "2", "3"],
        ["4", "5", "6", "7"],
        ["8", "9", "A", "B"],
        ["C", "D", "E", "F"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { digit in
                        Button {
                            append(digit)
                        } label: {
                            Text(digit)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    command = ""
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(command.isEmpty)

                Button(action: send) {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ChairDecode.isFourDigitHex(command))
            }
        }
    }

    private func append(_ digit: String) {
        guard command.count < 4 else { return }
        command.append(digit)
    }
}

private struct ConnectionPanel: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showDevicePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ble.isConnected ? .green : (ble.isScanning ? .orange : .secondary))
                    .frame(width: 10, height: 10)

                Text(ble.connectionState)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Text("\(ble.notifyCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            HStack {
                Button {
                    ble.scan()
                    showDevicePicker = true
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(ble.isConnected)

                Button(role: .destructive) {
                    ble.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!ble.isConnected)
            }
        }
        .panelStyle()
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
        }
    }
}

private struct DevicePickerSheet: View {
    @ObservedObject var ble: ChairBLEManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if ble.discoveredDevices.isEmpty {
                    ContentUnavailableView(
                        "Scanning...",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Move closer to your device.")
                    )
                } else {
                    ForEach(ble.discoveredDevices.sorted(by: { $0.rssi > $1.rssi })) { device in
                        Button {
                            ble.connect(device)
                            isPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("RSSI \(device.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        ble.disconnect()
                        isPresented = false
                    }
                }
            }
        }
    }
}

private struct ScanToolbarButton: ToolbarContent {
    @ObservedObject var ble: ChairBLEManager

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                ble.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Scan again")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RawLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "Waiting..." : ChairDecode.spaced(value))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LogRow: View {
    let entry: ChairLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch entry.kind {
        case .status:
            return "waveform.path.ecg"
        case .command:
            return "arrow.left.arrow.right"
        case .sent:
            return "paperplane.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .system:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .status:
            return .secondary
        case .command:
            return .green
        case .sent:
            return .purple
        case .error:
            return .red
        case .system:
            return .blue
        }
    }
}

private struct CommandLogRow: View {
    let entry: ChairCommandEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch entry.direction {
        case .remoteToChair:
            return "arrow.right.circle.fill"
        case .chairToRemote:
            return "arrow.left.circle.fill"
        case .appToChair:
            return "paperplane.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch entry.direction {
        case .remoteToChair:
            return .green
        case .chairToRemote:
            return .orange
        case .appToChair:
            return .purple
        case .error:
            return .red
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    func screenPadding() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}


#Preview {
    ContentView()
}
