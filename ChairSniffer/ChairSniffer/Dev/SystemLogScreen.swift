import SwiftUI

struct SystemLogContent: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        List {
            if ble.systemLogs.isEmpty {
                ContentUnavailableView(
                    "No System Events",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("BLE connection events will appear here.")
                )
            } else {
                ForEach(Array(ble.systemLogs.reversed())) { entry in
                    LogRow(entry: entry)
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: ChairLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.text)
                    .font(.system(.footnote))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch entry.kind {
        case .status: return "waveform.path.ecg"
        case .command: return "arrow.left.arrow.right"
        case .sent: return "paperplane.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .system: return "antenna.radiowaves.left.and.right"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .status: return .secondary
        case .command: return .green
        case .sent: return .purple
        case .error: return .red
        case .system: return .blue
        }
    }
}
