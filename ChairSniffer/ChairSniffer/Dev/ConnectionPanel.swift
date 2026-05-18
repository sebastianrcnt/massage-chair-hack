import SwiftUI

struct ConnectionPanel: View {
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
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button {
                ble.scan()
                showDevicePicker = true
            } label: {
                Label(ble.isScanning ? "Scanning…" : "Scan for devices", systemImage: "dot.radiowaves.left.and.right")
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
