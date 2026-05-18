import SwiftUI

struct RawFeedContent: View {
    @ObservedObject var ble: ChairBLEManager
    @State private var isPaused = false
    @State private var frozenText = ""
    @State private var frozenCount = 0

    var displayedText: String { isPaused ? frozenText : ble.rawTerminalText }
    var displayedCount: Int { isPaused ? frozenCount : ble.rawLogs.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("\(displayedCount) lines", systemImage: "tray.full")
                if ble.droppedRawLogCount > 0 {
                    Text("\(ble.droppedRawLogCount) dropped")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if !isPaused {
                        frozenText = ble.rawTerminalText
                        frozenCount = ble.rawLogs.count
                    }
                    isPaused.toggle()
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(isPaused ? .orange : .primary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            Divider()

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayedText.isEmpty ? "Waiting for BLE notifications…" : displayedText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                            Color.clear.frame(width: 1, height: 1).id("terminal-end")
                        }
                        .padding(14)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                    .background(Color(.systemBackground))
                    .overlay(alignment: .topTrailing) {
                        if isPaused {
                            Text("PAUSED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    .onChange(of: ble.rawLogs.count) { _, _ in
                        guard !isPaused else { return }
                        proxy.scrollTo("terminal-end", anchor: .bottom)
                    }
                }
            }
        }
    }
}
