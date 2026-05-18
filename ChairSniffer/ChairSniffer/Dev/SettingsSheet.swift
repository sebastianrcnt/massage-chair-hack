import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var ble: ChairBLEManager
    @Binding var isPresented: Bool
    @State private var showBluetoothSheet = false

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                liveDataSection
                logsSection
                sendSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showBluetoothSheet) {
                DevicePickerSheet(ble: ble, isPresented: $showBluetoothSheet)
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section("Connection") {
            Button {
                showBluetoothSheet = true
            } label: {
                HStack {
                    Text(deviceRowTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text("Status")
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Messages")
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 14) {
                    Label("\(ble.notifyCount)", systemImage: "arrow.down")
                    Label("\(ble.sentCount)", systemImage: "arrow.up")
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private var liveDataSection: some View {
        Section("Live Data") {
            NavigationLink {
                StatusContent(ble: ble)
                    .navigationTitle("Decoded + Frames")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Decoded + Frames", systemImage: "waveform")
            }
        }
    }

    private var logsSection: some View {
        Section("Logs") {
            NavigationLink {
                CommandLogContent(ble: ble)
                    .navigationTitle("Command Log")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Command Log", systemImage: "bubble.left.and.bubble.right")
            }
            NavigationLink {
                RawFeedContent(ble: ble)
                    .navigationTitle("Raw Feed")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Raw Feed", systemImage: "list.bullet.rectangle")
            }
            NavigationLink {
                SystemLogContent(ble: ble)
                    .navigationTitle("System Events")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("System Events", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    private var sendSection: some View {
        Section("Send") {
            NavigationLink {
                CustomHexScreen(ble: ble)
            } label: {
                Label("Custom Hex", systemImage: "keyboard")
            }
        }
    }

    // MARK: - Status helpers

    private var deviceRowTitle: String {
        if !ble.isBluetoothReady { return "Bluetooth Off" }
        if ble.isConnected {
            // Pull the device name from the connection state string if available.
            return connectedDeviceName ?? "Connected"
        }
        if ble.activeDeviceId != nil { return "Connecting…" }
        if ble.isScanning { return "Scanning…" }
        return "Not Connected"
    }

    private var connectedDeviceName: String? {
        // connectionState is "Connected to X" or similar.
        let state = ble.connectionState
        if let range = state.range(of: "Connected to ") {
            return String(state[range.upperBound...]).split(separator: ",").first.map(String.init)
        }
        return nil
    }

    private var statusLabel: String {
        if !ble.isBluetoothReady { return "Bluetooth Off" }
        if ble.isConnected { return "Connected" }
        if ble.activeDeviceId != nil { return "Connecting" }
        if ble.isScanning { return "Scanning" }
        return "Disconnected"
    }

    private var statusColor: Color {
        if !ble.isBluetoothReady { return .red }
        if ble.isConnected { return .green }
        if ble.activeDeviceId != nil || ble.isScanning { return .orange }
        return .secondary
    }
}
