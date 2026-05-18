import SwiftUI

struct ContentView: View {
    @StateObject private var ble = ChairBLEManager()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            PadLayout(ble: ble)
        } else {
            PhoneLayout(ble: ble)
        }
    }
}

private struct PhoneLayout: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        TabView {
            NavigationStack {
                StatusContent(ble: ble, showConnection: true)
            }
            .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }

            CommandsTab(ble: ble)
                .tabItem { Label("Commands", systemImage: "bubble.left.and.bubble.right") }

            RawTab(ble: ble)
                .tabItem { Label("Raw", systemImage: "list.bullet.rectangle") }

            SystemTab(ble: ble)
                .tabItem { Label("System", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

private struct CommandsTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            CommandsContent(ble: ble)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

private struct RawTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            RawFeedContent(ble: ble)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

private struct SystemTab: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            SystemLogContent(ble: ble)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ble.scan(); showPicker = true } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .disabled(ble.isConnected)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    DevicePickerSheet(ble: ble, isPresented: $showPicker)
                }
        }
    }
}

private enum PadSection: String, CaseIterable, Hashable {
    case status = "Status"
    case commands = "Commands"
    case raw = "Raw Feed"
    case system = "System Log"

    var icon: String {
        switch self {
        case .status: return "gauge.with.dots.needle.bottom.50percent"
        case .commands: return "bubble.left.and.bubble.right"
        case .raw: return "list.bullet.rectangle"
        case .system: return "antenna.radiowaves.left.and.right"
        }
    }
}

private struct PadLayout: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var selection: PadSection? = .status

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ConnectionPanel(ble: ble)
                    .padding(16)
                Divider()
                List(selection: $selection) {
                    ForEach(PadSection.allCases, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            NavigationStack {
                detailContent
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .status {
        case .status:
            StatusContent(ble: ble, showConnection: false)
        case .commands:
            CommandsContent(ble: ble)
        case .raw:
            RawFeedContent(ble: ble)
        case .system:
            SystemLogContent(ble: ble)
        }
    }
}

#Preview {
    ContentView()
}
