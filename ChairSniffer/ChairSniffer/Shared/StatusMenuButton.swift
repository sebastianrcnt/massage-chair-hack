import SwiftUI

/// Top-right omni button: color-coded BLE status icon that opens a menu with
/// connection actions and developer-tools entry.
struct StatusMenuButton: View {
    @ObservedObject var ble: ChairBLEManager
    let onScanRequest: () -> Void
    let onDevTools: () -> Void

    var body: some View {
        Menu {
            connectionItems
            Section {
                Button {
                    onDevTools()
                } label: {
                    Label("Developer Tools", systemImage: "wrench.and.screwdriver")
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var connectionItems: some View {
        if !ble.isBluetoothReady {
            Section {
                Label(ble.bluetoothStatusMessage, systemImage: "exclamationmark.circle")
            }
        } else if ble.isConnected {
            Section(ble.connectionState) {
                Button(role: .destructive) {
                    ble.disconnect()
                } label: {
                    Label("연결 해제", systemImage: "xmark.circle")
                }
            }
        } else {
            Section {
                Button {
                    onScanRequest()
                } label: {
                    Label(ble.isScanning ? "스캔 중…" : "기기 검색",
                          systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(ble.isScanning)
            }
        }
    }

    private var iconName: String {
        if !ble.isBluetoothReady { return "xmark.circle.fill" }
        if ble.isConnected       { return "checkmark.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    private var iconColor: Color {
        if !ble.isBluetoothReady { return .red }
        if ble.isConnected       { return .green }
        return .orange
    }

    private var accessibilityLabel: String {
        if !ble.isBluetoothReady { return "Bluetooth unavailable" }
        if ble.isConnected       { return "Connected" }
        return "Disconnected"
    }
}
