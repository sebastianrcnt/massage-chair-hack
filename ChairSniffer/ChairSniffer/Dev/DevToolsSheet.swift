import SwiftUI

struct DevToolsSheet: View {
    @ObservedObject var ble: ChairBLEManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Live Data") {
                    NavigationLink {
                        StatusContent(ble: ble, showConnection: false)
                            .navigationTitle("Decoded + Frames")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Decoded + Frames", systemImage: "waveform")
                    }
                }

                Section("Logs") {
                    NavigationLink {
                        CommandLogContent(ble: ble)
                            .navigationTitle("Command Log")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Command Log", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink {
                        RawFeedContent(ble: ble)
                            .navigationTitle("Raw Feed")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Raw Feed", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        SystemLogContent(ble: ble)
                            .navigationTitle("System Events")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("System Events", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

                Section("Send") {
                    NavigationLink {
                        CustomHexScreen(ble: ble)
                    } label: {
                        Label("Custom Hex", systemImage: "keyboard")
                    }
                }

                Section("Connection") {
                    ConnectionPanel(ble: ble)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
