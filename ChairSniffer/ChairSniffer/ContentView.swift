import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @State private var showDevTools = false
    @State private var showDevicePicker = false

    var body: some View {
        TabView {
            Tab("홈", systemImage: "house.fill") {
                tabContent(title: "홈") { HomeTab(ble: ble) }
            }
            Tab("자세", systemImage: "figure.seated.side") {
                tabContent(title: "자세") { PostureTab(ble: ble) }
            }
            Tab("마사지", systemImage: "hand.raised.fill") {
                tabContent(title: "마사지") { MassageTab(ble: ble) }
            }
        }
        .tint(.chairTint)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
        }
        .sheet(isPresented: $showDevTools) {
            DevToolsSheet(ble: ble, isPresented: $showDevTools)
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(
        title: String,
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
    }
}

#Preview {
    ContentView()
}
