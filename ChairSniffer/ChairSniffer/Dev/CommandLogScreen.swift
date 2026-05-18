import SwiftUI

struct CommandLogContent: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if ble.commandLogs.isEmpty {
                        Text("No messages yet — tap a control or send a custom hex.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 36)
                            .padding(.horizontal, 24)
                            .multilineTextAlignment(.center)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(ble.commandLogs) { entry in
                                ChatBubble(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .onChange(of: ble.commandLogs.count) { _, _ in
                    if let last = ble.commandLogs.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ChatBubble: View {
    let entry: ChairCommandEntry

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if entry.direction == .appToChair {
                Spacer(minLength: 30)
                timeLabel
                bubble
            } else if entry.direction == .error {
                bubble
                    .frame(maxWidth: .infinity)
            } else {
                bubble
                timeLabel
                Spacer(minLength: 30)
            }
        }
    }

    private var bubble: some View {
        HStack(spacing: 6) {
            Text(entry.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if !entry.code.isEmpty {
                Text(entry.code)
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(bubbleBackground, in: Capsule())
        .foregroundStyle(foreground)
    }

    private var timeLabel: some View {
        Text(entry.date.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.tertiary)
    }

    private var bubbleBackground: Color {
        switch entry.direction {
        case .appToChair: return .blue
        case .chairToRemote: return Color(.systemGray5)
        case .remoteToChair: return .green
        case .error: return .red.opacity(0.9)
        }
    }

    private var foreground: Color {
        switch entry.direction {
        case .appToChair, .remoteToChair, .error: return .white
        case .chairToRemote: return .primary
        }
    }
}
