import SwiftUI

/// Status indicator + Settings entry, all in one tap.
/// Color-coded by BLE health; tapping opens SettingsSheet (which itself has
/// connection management inside).
struct StatusMenuButton: View {
    @ObservedObject var ble: ChairBLEManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .accessibilityLabel(accessibilityLabel)
        }
        .buttonStyle(.glass)
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
        if !ble.isBluetoothReady { return "Bluetooth unavailable. Open developer tools." }
        if ble.isConnected       { return "Connected. Open developer tools." }
        return "Disconnected. Open developer tools."
    }
}
