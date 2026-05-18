import SwiftUI

struct HeroStatusCard: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        let decoded = ble.decodedStatus
        VStack(alignment: .leading, spacing: 14) {
            timerRow(decoded)
            Divider()
            footerRow(decoded)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func timerRow(_ decoded: ChairDecodedStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(timerNumber(from: decoded.timer))
                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text("min")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .baselineOffset(2)
            Spacer(minLength: 0)
            connectionDot
        }
    }

    private func footerRow(_ decoded: ChairDecodedStatus) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모드")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(modeLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            motionIndicator(decoded.motion)
        }
    }

    private var connectionDot: some View {
        Circle()
            .fill(ble.isConnected ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 10, height: 10)
    }

    private func motionIndicator(_ motion: String) -> some View {
        let moving = motion == "moving"
        return HStack(spacing: 6) {
            Circle()
                .fill(moving ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .scaleEffect(moving ? 1.0 : 0.85)
                .animation(moving ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                           value: moving)
            Text(moving ? "동작 중" : "정지")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var modeLabel: String {
        if !ble.isConnected { return "—" }
        return ble.currentAutoMode ?? "수동"
    }

    private func timerNumber(from raw: String) -> String {
        if !ble.isConnected { return "—" }
        let first = raw.split(separator: " ").first.map(String.init) ?? raw
        return first == "-" ? "—" : first
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
    }
}
