import SwiftUI

struct DevicePickerSheet: View {
    @ObservedObject var ble: ChairBLEManager
    @Binding var isPresented: Bool

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if !ble.isConnected && !ble.isScanning {
                    ble.scan()
                }
                ble.refreshDeviceList()
            }
            .onReceive(refreshTimer) { _ in
                ble.refreshDeviceList()
            }
            .onChange(of: ble.isConnected) { _, isConnected in
                if isConnected {
                    // Auto-dismiss once a device connects.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isPresented = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        List {
            if !chairDevices.isEmpty {
                Section("Chair Bridges") {
                    ForEach(chairDevices) { device in
                        DeviceRow(
                            device: device,
                            indicator: indicator(for: device)
                        ) {
                            tap(device)
                        }
                    }
                }
            }

            if !otherDevices.isEmpty {
                Section("Other Devices") {
                    ForEach(otherDevices) { device in
                        DeviceRow(
                            device: device,
                            indicator: indicator(for: device)
                        ) {
                            tap(device)
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
                            Text("Searching for devices…")
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

    private func indicator(for device: DiscoveredDevice) -> DeviceRowIndicator {
        if ble.activeDeviceId == device.id {
            return ble.isConnected ? .connected : .connecting
        }
        return .none
    }

    private func tap(_ device: DiscoveredDevice) {
        // No-op if already connected to this device; otherwise connect.
        if ble.activeDeviceId == device.id && ble.isConnected { return }
        ble.connect(device)
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

private enum DeviceRowIndicator {
    case none
    case connecting
    case connected
}

private struct DeviceRow: View {
    let device: DiscoveredDevice
    let indicator: DeviceRowIndicator
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text(device.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                switch indicator {
                case .none:
                    EmptyView()
                case .connecting:
                    ProgressView()
                        .controlSize(.small)
                case .connected:
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
