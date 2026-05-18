import SwiftUI

enum FrameDisplayMode: String, CaseIterable {
    case hex = "HEX"
    case binary = "BIN"
    case octal = "OCT"

    func format(_ hexByte: String) -> String {
        guard let value = UInt8(hexByte, radix: 16) else { return hexByte }
        switch self {
        case .hex: return hexByte.uppercased()
        case .binary: return String(value, radix: 2).leftPad(to: 8)
        case .octal: return String(value, radix: 8).leftPad(to: 3)
        }
    }

    var columnWidth: Int {
        switch self {
        case .hex: return 2
        case .binary: return 8
        case .octal: return 3
        }
    }
}

struct StatusContent: View {
    @ObservedObject var ble: ChairBLEManager

    @AppStorage("frameDisplayMode") private var displayMode = FrameDisplayMode.binary
    @State private var isFramesPaused = false
    @State private var maskKnownBits = false
    @State private var prevShort = ""
    @State private var prevLong = ""
    @State private var frozenShort = ""
    @State private var frozenLong = ""
    @State private var frozenPrevShort = ""
    @State private var frozenPrevLong = ""

    // 1 bit = decoded/known per docs/decoding.md
    private static let longKnownMask: [UInt8] = [
        0x00, // B0 unknown
        0xFF, // B1 timer tens
        0xF0, // B2 timer ones (high nibble)
        0xFF, // B3 b7 지압 + b6:b5 air strength / 주무름 + b4 air + timer ones low nibble
        0x3F, // B4 b5:b4 manual indicator + b3:b0 manual technique blinks / speed
        0x00, // B5 unknown
        0xFF, // B6 foot roller, leg/back motion, width
        0x00, // B7 unknown
        0x02, // B8 (last) heater b1
    ]
    private static let shortKnownMask: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0xFF]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                decodedPanel
                rawStatusPanel
            }
            .screenPadding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: ble.latestShort) { old, _ in
            guard !isFramesPaused else { return }
            prevShort = old
        }
        .onChange(of: ble.latestLong) { old, _ in
            guard !isFramesPaused else { return }
            prevLong = old
        }
    }

    private var decodedPanel: some View {
        let decoded = ble.decodedStatus
        return VStack(alignment: .leading, spacing: 12) {
            Text("Decoded Status")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220))], spacing: 10) {
                MetricTile(title: "Timer", value: decoded.timer, icon: "timer")
                MetricTile(title: "Area", value: decoded.area, icon: "scope")
                MetricTile(title: "Air", value: decoded.air, icon: "wind")
                MetricTile(title: "Air Level", value: decoded.airStrength, icon: "gauge.medium")
                MetricTile(title: "Speed", value: decoded.speed, icon: "speedometer")
                MetricTile(title: "Motion", value: decoded.motion, icon: "figure.walk.motion")
                MetricTile(title: "Back", value: decoded.back, icon: "arrow.up.and.down")
                MetricTile(title: "Leg", value: decoded.leg, icon: "arrow.up.forward")
                MetricTile(title: "Width", value: decoded.width, icon: "arrow.left.and.right")
                MetricTile(title: "Foot Roller", value: decoded.footRoller, icon: "circle.dotted")
                MetricTile(title: "Heater", value: decoded.heater, icon: "heat.waves")
            }
        }
        .panelStyle()
    }

    private var rawStatusPanel: some View {
        let shownShort = isFramesPaused ? frozenShort : ble.latestShort
        let shownLong = isFramesPaused ? frozenLong : ble.latestLong
        let shownPrevShort = isFramesPaused ? frozenPrevShort : prevShort
        let shownPrevLong = isFramesPaused ? frozenPrevLong : prevLong

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Frames")
                    .font(.headline)
                Spacer()
                Button {
                    if !isFramesPaused {
                        frozenShort = ble.latestShort
                        frozenLong = ble.latestLong
                        frozenPrevShort = prevShort
                        frozenPrevLong = prevLong
                    } else {
                        prevShort = ble.latestShort
                        prevLong = ble.latestLong
                    }
                    isFramesPaused.toggle()
                } label: {
                    Image(systemName: isFramesPaused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(isFramesPaused ? .orange : .primary)
                .accessibilityLabel(isFramesPaused ? "Resume latest frames" : "Pause latest frames")

                if displayMode == .binary {
                    Button { maskKnownBits.toggle() } label: {
                        Image(systemName: maskKnownBits ? "eye.slash.fill" : "eye")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(maskKnownBits ? .chairTint : .primary)
                    .accessibilityLabel(maskKnownBits ? "Show all bits" : "Mask decoded bits")
                }

                Picker("Display", selection: $displayMode) {
                    ForEach(FrameDisplayMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel("Byte display mode")
            }
            DiffRawLine(title: "Short", value: shownShort, previous: shownPrevShort, mode: displayMode,
                        knownMask: maskKnownBits ? Self.shortKnownMask : nil)
            DiffRawLine(title: "Long",  value: shownLong,  previous: shownPrevLong,  mode: displayMode,
                        knownMask: maskKnownBits ? Self.longKnownMask : nil)
        }
        .panelStyle()
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiffRawLine: View {
    let title: String
    let value: String
    let previous: String
    let mode: FrameDisplayMode
    var knownMask: [UInt8]? = nil

    private let rawFont = Font.system(size: 12, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if value.isEmpty {
                Text("Waiting…")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if mode == .binary {
                            Text(byteHeader)
                                .font(rawFont)
                                .foregroundStyle(.tertiary)
                            Text(bitHeader)
                                .font(rawFont)
                                .foregroundStyle(.tertiary)
                        }
                        Text(attributedBytes)
                            .font(rawFont)
                            .textSelection(.enabled)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var byteHeader: String {
        let bytes = ChairDecode.bytes(from: value)
        return bytes.indices.map { idx in
            "B\(idx + 1)".centered(in: mode.columnWidth)
        }.joined(separator: " ")
    }

    private var bitHeader: String {
        let bytes = ChairDecode.bytes(from: value)
        return Array(repeating: "76543210", count: bytes.count).joined(separator: " ")
    }

    private var attributedBytes: AttributedString {
        let curBytes = ChairDecode.bytes(from: value)
        let prevBytes = ChairDecode.bytes(from: previous)
        var result = AttributedString()
        let canDiff = !previous.isEmpty
        let dotColor = Color(.tertiaryLabel)

        for (i, byte) in curBytes.enumerated() {
            let prev = i < prevBytes.count ? prevBytes[i] : ""
            let separator = i < curBytes.count - 1 ? " " : ""
            let mask: UInt8 = (knownMask.flatMap { $0.indices.contains(i) ? $0[i] : nil }) ?? 0

            if mode == .binary {
                let curBits = Array(mode.format(byte))
                let prevBits = prev.isEmpty ? [] : Array(mode.format(prev))
                for (bitIdx, bit) in curBits.enumerated() {
                    let bitPosition = 7 - bitIdx
                    let isMasked = (mask & (UInt8(1) << bitPosition)) != 0
                    if isMasked {
                        var part = AttributedString(".")
                        part.foregroundColor = dotColor
                        result.append(part)
                    } else {
                        let changed = canDiff && (bitIdx >= prevBits.count || bit != prevBits[bitIdx])
                        var part = AttributedString(String(bit))
                        if changed { part.foregroundColor = .orange }
                        result.append(part)
                    }
                }
                result.append(AttributedString(separator))
            } else {
                if mask == 0xFF {
                    let dots = String(repeating: ".", count: mode.columnWidth)
                    var part = AttributedString(dots + separator)
                    part.foregroundColor = dotColor
                    result.append(part)
                } else {
                    let changed = canDiff && (i >= prevBytes.count || byte != prev)
                    var part = AttributedString(mode.format(byte) + separator)
                    if changed { part.foregroundColor = .orange }
                    result.append(part)
                }
            }
        }
        return result
    }
}
