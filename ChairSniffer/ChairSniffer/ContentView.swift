import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @State private var showDevTools = false

    var body: some View {
        TabView {
            Tab("홈", systemImage: "house.fill") {
                HomeTab(ble: ble, onStatusTap: { showDevTools = true })
            }
            Tab("자세", systemImage: "figure.seated.side") {
                PostureTab(ble: ble, onStatusTap: { showDevTools = true })
            }
            Tab("마사지", systemImage: "hand.raised.fill") {
                MassageTab(ble: ble, onStatusTap: { showDevTools = true })
            }
        }
        .tint(.chairTint)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showDevTools) {
            DevToolsSheet(ble: ble, isPresented: $showDevTools)
        }
    }
}

#Preview {
    ContentView()
}
