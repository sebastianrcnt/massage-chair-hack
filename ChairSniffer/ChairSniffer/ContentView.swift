import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @State private var showDevTools = false
    @State private var showDevicePicker = false

    var body: some View {
        TabView {
            tab(title: "Chair", icon: "house.fill", label: "홈") {
                HomeTab(ble: ble)
            }
            tab(title: "자세", icon: "figure.seated.side", label: "자세") {
                PostureTab(ble: ble)
            }
            tab(title: "마사지", icon: "hand.raised.fill", label: "마사지") {
                MassageTab(ble: ble)
            }
        }
        .tint(.chairTint)
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
        }
        .sheet(isPresented: $showDevTools) {
            DevToolsSheet(ble: ble, isPresented: $showDevTools)
        }
    }

    @ViewBuilder
    private func tab<Content: View>(
        title: String,
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        StatusMenuButton(
                            ble: ble,
                            onScanRequest: {
                                ble.scan()
                                showDevicePicker = true
                            },
                            onDevTools: {
                                showDevTools = true
                            }
                        )
                    }
                }
        }
        .tabItem { Label(label, systemImage: icon) }
    }
}

#Preview {
    ContentView()
}
