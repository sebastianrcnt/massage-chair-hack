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
                .tabItem { Label("Commands", systemImage: "bubble.left.and.bubble.right") }

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
                .navigationBarTitleDisplayMode(.inline)
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
                .navigationBarTitleDisplayMode(.inline)
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
                .navigationBarTitleDisplayMode(.inline)
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
        case .commands: return "bubble.left.and.bubble.right"
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

// MARK: - Commands content (iMessage-style)

private struct CommandsContent: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var command = ""

    var body: some View {
        VStack(spacing: 0) {
            chatList
            Divider()
            cheatSheet
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            Divider()
            composer
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground))
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if ble.commandLogs.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(ble.commandLogs) { entry in
                            ChatBubble(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: ble.commandLogs.count) { _, _ in
                if let last = ble.commandLogs.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No commands yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press a chair button or send a hex code below.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var cheatSheet: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CommandCatalog.cheatSheet, id: \.code) { item in
                    Button { command = item.code } label: {
                        VStack(spacing: 1) {
                            Text(item.code)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(commandDisplay)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Command \(commandDisplay)")

                Button { command = String(command.dropLast()) } label: {
                    Image(systemName: "delete.left").frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .disabled(command.isEmpty)

                Button(action: sendCommand) {
                    Image(systemName: "paperplane.fill").frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ChairDecode.isFourDigitHex(command))
            }
            HexKeypadCompact(command: $command)
        }
    }

    private var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var commandDisplay: String {
        let trimmed = normalizedCommand
        let placeholder = String(repeating: "_", count: max(0, 4 - trimmed.count))
        return trimmed + placeholder
    }

    private func sendCommand() {
        let value = normalizedCommand
        ble.send(command: value)
        if ChairDecode.isFourDigitHex(value) { command = "" }
    }
}

// MARK: - Chat bubble

private struct ChatBubble: View {
    let entry: ChairCommandEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if entry.direction == .appToChair {
                Spacer(minLength: 48)
                bubble
            } else if entry.direction == .error {
                bubble
                    .frame(maxWidth: .infinity)
            } else {
                bubble
                Spacer(minLength: 48)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: bubbleAlignment, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.75)
                }
            }
            if let note = entry.note {
                Text(note)
                    .font(.caption2)
                    .opacity(0.7)
            }
            HStack(spacing: 6) {
                if !entry.code.isEmpty {
                    Text(entry.code)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .opacity(0.85)
                }
                Text(timeString)
                    .font(.caption2.monospacedDigit())
                    .opacity(0.55)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(foreground)
    }

    private var bubbleAlignment: HorizontalAlignment {
        entry.direction == .appToChair ? .trailing : .leading
    }

    private var timeString: String {
        entry.date.formatted(date: .omitted, time: .standard)
    }

    private var bubbleBackground: Color {
        switch entry.direction {
        case .appToChair:    return .blue
        case .chairToRemote: return Color(.systemGray5)
        case .remoteToChair: return .green
        case .error:         return .red.opacity(0.9)
        }
    }

    private var foreground: Color {
        switch entry.direction {
        case .appToChair, .remoteToChair, .error: return .white
        case .chairToRemote: return .primary
        }
    }
}

// MARK: - Hex keypad (compact, inline)

private struct HexKeypadCompact: View {
    @Binding var command: String

    private let rows = [
        ["0", "1", "2", "3"],
        ["4", "5", "6", "7"],
        ["8", "9", "A", "B"],
        ["C", "D", "E", "F"],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { digit in
                        Button { append(digit) } label: {
                            Text(digit)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func append(_ digit: String) {
        guard command.count < 4 else { return }
        command.append(digit)
    }
}

// MARK: - Raw feed content (clean, left-aligned)

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
                Label("\(displayedCount) lines", systemImage: "tray.full")
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
            .background(Color(.secondarySystemBackground))

            Divider()

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayedText.isEmpty ? "Waiting for BLE notifications…" : displayedText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                            Color.clear.frame(width: 1, height: 1).id("terminal-end")
                        }
                        .padding(14)
                        .frame(
                            minWidth: geo.size.width,
                            minHeight: geo.size.height,
                            alignment: .topLeading
                        )
                    }
                    .background(Color(.systemBackground))
                    .overlay(alignment: .topTrailing) {
                        if isPaused {
                            Text("PAUSED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
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
            }
        }
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
    @State private var showDisconnectConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ble.isConnected ? .green : (ble.isScanning ? .orange : .secondary))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ble.connectionState)
                        .font(.headline)
                        .lineLimit(2)
                    statsRow
                }
                Spacer()
            }

            primaryButton
        }
        .panelStyle()
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
        }
        .confirmationDialog(
            "Disconnect from chair?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { ble.disconnect() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if ble.isConnected {
            Button {
                showDisconnectConfirm = true
            } label: {
                Label("Connected — tap to disconnect", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button {
                ble.scan()
                showDevicePicker = true
            } label: {
                Label(ble.isScanning ? "Scanning…" : "Scan for devices",
                      systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            Label("\(ble.notifyCount)", systemImage: "arrow.down")
                .accessibilityLabel("Received \(ble.notifyCount) frames")
            Label("\(ble.sentCount)", systemImage: "arrow.up")
                .accessibilityLabel("Sent \(ble.sentCount) commands")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Device picker (iOS Bluetooth settings style)

private struct DevicePickerSheet: View {
    @ObservedObject var ble: ChairBLEManager
    @Binding var isPresented: Bool
    @AppStorage("scannerAutoRefresh") private var autoRefresh: Bool = true

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var chairDevices: [DiscoveredDevice] {
        ble.displayedDevices.filter { $0.name.localizedCaseInsensitiveContains("ChairSniffer") }
    }
    private var otherDevices: [DiscoveredDevice] {
        ble.displayedDevices.filter { !$0.name.localizedCaseInsensitiveContains("ChairSniffer") }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ble.isBluetoothReady {
                    deviceList
                } else {
                    bluetoothUnavailable
                }
            }
            .navigationTitle("Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .onAppear { ble.refreshDeviceList() }
            .onReceive(refreshTimer) { _ in
                if autoRefresh { ble.refreshDeviceList() }
            }
        }
    }

    private var deviceList: some View {
        List {
            Section {
                Toggle(isOn: $autoRefresh) {
                    Label("Auto-refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    ble.refreshDeviceList()
                } label: {
                    HStack {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                        Spacer()
                        if ble.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text(autoRefresh
                     ? "List re-sorts every 5 seconds."
                     : "List stays put until you refresh.")
            }

            if !chairDevices.isEmpty {
                Section("Chair Bridges") {
                    ForEach(chairDevices) { device in
                        DeviceRow(name: device.name, isMatch: true) {
                            ble.connect(device)
                            isPresented = false
                        }
                    }
                }
            }

            if !otherDevices.isEmpty {
                Section("Other Devices") {
                    ForEach(otherDevices) { device in
                        DeviceRow(name: device.name, isMatch: false) {
                            ble.connect(device)
                            isPresented = false
                        }
                    }
                }
            }

            if chairDevices.isEmpty && otherDevices.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Scanning for devices…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var bluetoothUnavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(ble.bluetoothStatusMessage)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Turn on Bluetooth in Settings to scan for nearby chair bridges.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct DeviceRow: View {
    let name: String
    let isMatch: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if isMatch {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                        .font(.body)
                }
                Text(name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if value.isEmpty {
                Text("Waiting…")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if mode == .binary {
                            Text(byteHeader)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(bitHeader)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Text(attributedBytes)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var byteHeader: String {
        let bytes = ChairDecode.bytes(from: value)
        return bytes.indices.map { idx in
            "B\(idx + 1)".centered(in: mode.columnWidth)
        }.joined(separator: " ")
    }

    private var bitHeader: String {
        let bytes = ChairDecode.bytes(from: value)
        return Array(repeating: "76543210", count: bytes.count).joined(separator: " ")
    }

    private var attributedBytes: AttributedString {
        let curBytes  = ChairDecode.bytes(from: value)
        let prevBytes = ChairDecode.bytes(from: previous)
        var result = AttributedString()
        let canDiff = !previous.isEmpty

        for (i, byte) in curBytes.enumerated() {
            let prev = i < prevBytes.count ? prevBytes[i] : ""
            let separator = i < curBytes.count - 1 ? " " : ""

            if mode == .binary && canDiff {
                let curBits = Array(mode.format(byte))
                let prevBits = prev.isEmpty ? [] : Array(mode.format(prev))
                for (bitIdx, bit) in curBits.enumerated() {
                    let changed = bitIdx >= prevBits.count || bit != prevBits[bitIdx]
                    var part = AttributedString(String(bit))
                    if changed { part.foregroundColor = .orange }
                    result.append(part)
                }
                result.append(AttributedString(separator))
            } else {
                let changed = canDiff && (i >= prevBytes.count || byte != prev)
                var part = AttributedString(mode.format(byte) + separator)
                if changed { part.foregroundColor = .orange }
                result.append(part)
            }
        }
        return result
    }
}

private extension FrameDisplayMode {
    var columnWidth: Int {
        switch self {
        case .hex: return 2
        case .binary: return 8
        case .octal: return 3
        }
    }
}

private extension String {
    func centered(in width: Int) -> String {
        if count >= width { return String(prefix(width)) }
        let pad = width - count
        let left = pad / 2
        let right = pad - left
        return String(repeating: " ", count: left) + self + String(repeating: " ", count: right)
    }
}

// MARK: - System log row

private struct LogRow: View {
    let entry: ChairLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.text)
                    .font(.system(.footnote))
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
