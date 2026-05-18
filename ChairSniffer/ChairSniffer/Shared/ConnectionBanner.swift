import SwiftUI

struct ConnectionBanner: View {
    @ObservedObject var ble: ChairBLEManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                statusDot
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if ble.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(background)
        }
        .buttonStyle(.plain)
    }

    private var statusDot: some View {
        Circle()
            .fill(ble.isBluetoothReady ? .orange : .red)
            .frame(width: 8, height: 8)
    }

    private var message: String {
        if !ble.isBluetoothReady {
            return ble.bluetoothStatusMessage
        }
        if ble.isScanning {
            return "Scanning for chair…"
        }
        return "Disconnected — Tap to scan"
    }

    private var background: some ShapeStyle {
        ble.isBluetoothReady ? AnyShapeStyle(Color.orange.opacity(0.15))
                             : AnyShapeStyle(Color.red.opacity(0.18))
    }
}
