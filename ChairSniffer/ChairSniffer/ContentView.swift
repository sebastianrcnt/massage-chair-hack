import SwiftUI

// MARK: - Display mode

enum FrameDisplayMode: String, CaseIterable {
    case hex = "HEX"
    case binary = "BIN"
    case octal = "OCT"

    func format(_ hexByte: String) -> String {
        guard let value = UInt8(hexByte, radix: 16) else { return hexByte }
        switch self {
        case .hex:    return hexByte.uppercased()
        case .binary: return String(value, radix: 2).leftPad(to: 8)
        case .octal:  return String(value, radix: 8).leftPad(to: 3)
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            PadLayout(ble: ble)
        } else {
            PhoneLayout(ble: ble)
        }
    }
}

// MARK: - iPhone layout

private struct PhoneLayout: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        TabView {
            NavigationStack {
                StatusContent(ble: ble, showConnection: true)
                    .navigationTitle("Chair Monitor")
            }
            .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }

            CommandsTab(ble: ble)
                .tabItem { Label("Commands", systemImage: "arrow.left.arrow.right") }

            RawTab(ble: ble)
                .tabItem { Label("Raw", systemImage: "list.bullet.rectangle") }

            SystemTab(ble: ble)
                .tabItem { Label("System", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

private struct CommandsTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            CommandsContent(ble: ble)
                .navigationTitle("Commands")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

private struct RawTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            RawFeedContent(ble: ble)
                .navigationTitle("Raw Feed")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

private struct SystemTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            SystemLogContent(ble: ble)
                .navigationTitle("System Log")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

// MARK: - iPad layout

private enum PadSection: String, CaseIterable, Hashable {
    case status   = "Status"
    case commands = "Commands"
    case raw      = "Raw Feed"
    case system   = "System Log"

    var icon: String {
        switch self {
        case .status:   return "gauge.with.dots.needle.bottom.50percent"
        case .commands: return "arrow.left.arrow.right"
        case .raw:      return "list.bullet.rectangle"
        case .system:   return "antenna.radiowaves.left.and.right"
        }
    }
}

private struct PadLayout: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var selection: PadSection? = .status

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ConnectionPanel(ble: ble)
                    .padding(16)
                Divider()
                List(selection: $selection) {
                    ForEach(PadSection.allCases, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Chair Monitor")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            NavigationStack {
                detailContent
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .status {
        case .status:
            StatusContent(ble: ble, showConnection: false)
                .navigationTitle("Status")
        case .commands:
            CommandsContent(ble: ble)
                .navigationTitle("Commands")
        case .raw:
            RawFeedContent(ble: ble)
                .navigationTitle("Raw Feed")
        case .system:
            SystemLogContent(ble: ble)
                .navigationTitle("System Log")
        }
    }
}

// MARK: - Status content

private struct StatusContent: View {
    @ObservedObject var ble: ChairBLEManager
    var showConnection: Bool = true

    @AppStorage("frameDisplayMode") private var displayMode = FrameDisplayMode.hex
    @State private var prevShort = ""
    @State private var prevLong = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showConnection {
                    ConnectionPanel(ble: ble)
                }
                decodedPanel
                rawStatusPanel
            }
            .screenPadding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: ble.latestShort) { old, _ in prevShort = old }
        .onChange(of: ble.latestLong)  { old, _ in prevLong  = old }
    }

    private var decodedPanel: some View {
        let decoded = ble.decodedStatus
        return VStack(alignment: .leading, spacing: 12) {
            Text("Decoded Status")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220))], spacing: 10) {
                MetricTile(title: "Timer",       value: decoded.timer,       icon: "timer")
                MetricTile(title: "Area",        value: decoded.area,        icon: "scope")
                MetricTile(title: "Air",         value: decoded.air,         icon: "wind")
                MetricTile(title: "Air Level",   value: decoded.airStrength, icon: "gauge.medium")
                MetricTile(title: "Speed",       value: decoded.speed,       icon: "speedometer")
                MetricTile(title: "Motion",      value: decoded.motion,      icon: "figure.walk.motion")
                MetricTile(title: "Back",        value: decoded.back,        icon: "arrow.up.and.down")
                MetricTile(title: "Leg",         value: decoded.leg,         icon: "arrow.up.forward")
                MetricTile(title: "Width",       value: decoded.width,       icon: "arrow.left.and.right")
                MetricTile(title: "Foot Roller", value: decoded.footRoller,  icon: "circle.dotted")
                MetricTile(title: "Heater",      value: decoded.heater,      icon: "heat.waves")
            }
        }
        .panelStyle()
    }

    private var rawStatusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Frames")
                    .font(.headline)
                Spacer()
                Picker("Display", selection: $displayMode) {
                    ForEach(FrameDisplayMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel("Byte display mode")
            }
            DiffRawLine(title: "Short", value: ble.latestShort, previous: prevShort, mode: displayMode)
            DiffRawLine(title: "Long",  value: ble.latestLong,  previous: prevLong,  mode: displayMode)
        }
        .panelStyle()
    }
}

// MARK: - Commands content

private struct CommandsContent: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var command = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            padLayout
        } else {
            phoneLayout
        }
    }

    private var phoneLayout: some View {
        List {
            Section { composerView.padding(.vertical, 4) } header: { Text("Send") }
            Section { commandLogRows } header: { Text("Command Log") }
        }
    }

    private var padLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                composerView.padding(16)
            }
            .frame(width: 340)
            .background(Color(.systemGroupedBackground))

            Divider()

            List {
                Section { commandLogRows } header: { Text("Command Log") }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var composerView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(commandDisplay)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Command \(commandDisplay)")

                Button { command = String(command.dropLast()) } label: {
                    Image(systemName: "delete.left").frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(command.isEmpty)
                .accessibilityLabel("Delete digit")
            }
            HexKeypad(command: $command, send: sendCommand)
        }
    }

    @ViewBuilder
    private var commandLogRows: some View {
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
    }

    private var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var commandDisplay: String {
        normalizedCommand + String(repeating: "-", count: max(0, 4 - normalizedCommand.count))
    }

    private func sendCommand() {
        let value = normalizedCommand
        ble.send(command: value)
        if ChairDecode.isFourDigitHex(value) { command = "" }
    }
}

// MARK: - Raw feed content

private struct RawFeedContent: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var isPaused = false
    @State private var frozenText = ""
    @State private var frozenCount = 0

    var displayedText: String { isPaused ? frozenText : ble.rawTerminalText }
    var displayedCount: Int   { isPaused ? frozenCount : ble.rawLogs.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("\(displayedCount) kept", systemImage: "tray.full")
                if ble.droppedRawLogCount > 0 {
                    Text("\(ble.droppedRawLogCount) dropped")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if !isPaused {
                        frozenText = ble.rawTerminalText
                        frozenCount = ble.rawLogs.count
                    }
                    isPaused.toggle()
                } label: {
                    Label(isPaused ? "Resume" : "Pause",
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(isPaused ? .orange : .primary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayedText.isEmpty ? "waiting for BLE notifications..." : displayedText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                        Color.clear.frame(height: 1).id("terminal-end")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if isPaused {
                        Text("PAUSED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
                .onChange(of: ble.rawLogs.count) { _, _ in
                    guard !isPaused else { return }
                    proxy.scrollTo("terminal-end", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - System log content

private struct SystemLogContent: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        List {
            if ble.systemLogs.isEmpty {
                ContentUnavailableView(
                    "No System Events",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("BLE connection events will appear here.")
                )
            } else {
                ForEach(Array(ble.systemLogs.reversed())) { entry in
                    LogRow(entry: entry)
                }
            }
        }
    }
}

// MARK: - Connection panel

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

// MARK: - Device picker

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

// MARK: - Hex keypad

private struct HexKeypad: View {
    @Binding var command: String
    let send: () -> Void

    private let rows = [
        ["0", "1", "2", "3"],
        ["4", "5", "6", "7"],
        ["8", "9", "A", "B"],
        ["C", "D", "E", "F"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { digit in
                        Button { append(digit) } label: {
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

// MARK: - Metric tile

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

// MARK: - Diff raw line

private struct DiffRawLine: View {
    let title: String
    let value: String
    let previous: String
    let mode: FrameDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if value.isEmpty {
                Text("Waiting...")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(attributedBytes)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var attributedBytes: AttributedString {
        let curBytes  = ChairDecode.bytes(from: value)
        let prevBytes = ChairDecode.bytes(from: previous)
        var result = AttributedString()
        for (i, byte) in curBytes.enumerated() {
            let changed = !previous.isEmpty && (i >= prevBytes.count || byte != prevBytes[i])
            var part = AttributedString(mode.format(byte) + (i < curBytes.count - 1 ? " " : ""))
            if changed { part.foregroundColor = .orange }
            result.append(part)
        }
        return result
    }
}

// MARK: - Log rows

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
        case .status:  return "waveform.path.ecg"
        case .command: return "arrow.left.arrow.right"
        case .sent:    return "paperplane.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .system:  return "antenna.radiowaves.left.and.right"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .status:  return .secondary
        case .command: return .green
        case .sent:    return .purple
        case .error:   return .red
        case .system:  return .blue
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
        case .remoteToChair: return "arrow.right.circle.fill"
        case .chairToRemote: return "arrow.left.circle.fill"
        case .appToChair:    return "paperplane.circle.fill"
        case .error:         return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch entry.direction {
        case .remoteToChair: return .green
        case .chairToRemote: return .orange
        case .appToChair:    return .purple
        case .error:         return .red
        }
    }
}

// MARK: - View extensions

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

private extension String {
    func leftPad(to length: Int) -> String {
        let padding = max(0, length - count)
        return String(repeating: "0", count: padding) + self
    }
}

#Preview {
    ContentView()
}
