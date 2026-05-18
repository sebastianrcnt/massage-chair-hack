import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @State private var showDevTools = false
    @State private var showDevicePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !ble.isConnected {
                    ConnectionBanner(ble: ble) {
                        ble.scan()
                        showDevicePicker = true
                    }
                }
                RemoteView(ble: ble)
            }
            .navigationTitle("Chair Sniffer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Chair Sniffer")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            showDevTools = true
                        }
                }
            }
        }
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
        }
        .sheet(isPresented: $showDevTools) {
            DevToolsSheet(ble: ble, isPresented: $showDevTools)
        }
    }
}

#Preview {
    ContentView()
}
