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

struct DevicePickerSheet: View {
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
                Text(autoRefresh ? "List re-sorts every 5 seconds." : "List stays put until you refresh.")
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
