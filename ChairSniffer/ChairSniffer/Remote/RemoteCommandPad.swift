import SwiftUI

struct ControlItem: Identifiable {
    enum Prominence {
        case primary
        case active
        case normal
        case subtle
    }

    let code: String
    let label: String
    let icon: String?
    let prominence: Prominence

    var id: String { code + label }

    init(code: String, label: String, icon: String? = nil, prominence: Prominence = .normal) {
        self.code = code
        self.label = label
        self.icon = icon
        self.prominence = prominence
    }
}

struct RemoteCommandPad: View {
    let availableWidth: CGFloat
    let liveState: (String) -> ControlState?
    let onPress: (String) -> Void
    let onRelease: () -> Void

    private var padWidth: CGFloat {
        min(max(availableWidth - 28, 304), 440)
    }

    private var sideButtonWidth: CGFloat {
        max((padWidth - 48) / 3, 78)
    }

    private var halfButtonWidth: CGFloat {
        max((padWidth - 38) / 2, 128)
    }

    private let power  = ControlItem(code: "0303", label: "전원",     icon: "power",               prominence: .primary)
    private let pause  = ControlItem(code: "0322", label: "일시정지", icon: "playpause",           prominence: .primary)
    private let timer  = ControlItem(code: "032D", label: "타이머",   icon: "timer")
    private let heater = ControlItem(code: "0330", label: "온열",     icon: "heat.waves")
    private let manual = ControlItem(code: "0363", label: "수동",     icon: "slider.horizontal.3")

    private let backRaise   = ControlItem(code: "0302", label: "등받이 ↑", icon: "chevron.up")
    private let backRecline = ControlItem(code: "0304", label: "등받이 ↓", icon: "chevron.down")
    private let legRaise    = ControlItem(code: "0307", label: "다리 ↑",  icon: "chevron.up")
    private let legLower    = ControlItem(code: "0301", label: "다리 ↓",  icon: "chevron.down")

    private let zeroG = ControlItem(code: "0306", label: "무중력", icon: "figure.flexibility",   prominence: .primary)
    private let reset = ControlItem(code: "0384", label: "원위치", icon: "arrow.counterclockwise", prominence: .primary)

    private let speed      = ControlItem(code: "0327", label: "속도",   icon: "speedometer")
    private let width      = ControlItem(code: "0364", label: "폭",     icon: "arrow.left.and.right")
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted")
    private let air        = ControlItem(code: "0375", label: "에어백",   icon: "bubble.left.and.bubble.right.fill")
    private let airLevel   = ControlItem(code: "0315", label: "에어 세기", icon: "gauge.medium")

    private let headUp   = ControlItem(code: "032C", label: "헤드 ↑", icon: "arrow.up")
    private let headDown = ControlItem(code: "032F", label: "헤드 ↓", icon: "arrow.down")

    private let autoModes = [
        ControlItem(code: "031F", label: "충전",     icon: "battery.100"),
        ControlItem(code: "0391", label: "소화",     icon: "sparkles"),
        ControlItem(code: "0305", label: "클래식",   icon: "music.note"),
        ControlItem(code: "0321", label: "숙면",     icon: "moon"),
        ControlItem(code: "031E", label: "스트레칭", icon: "figure.cooldown"),
        ControlItem(code: "0320", label: "힐링",     icon: "heart")
    ]

    var body: some View {
        VStack(spacing: 14) {
            // Primary controls
            HStack(spacing: 10) {
                ControlCommandButton(item: power, state: liveState(power.code), minHeight: 58, onPress: onPress, onRelease: onRelease)
                ControlCommandButton(item: pause, state: liveState(pause.code), minHeight: 58, onPress: onPress, onRelease: onRelease)
            }

            HStack(spacing: 10) {
                compactButton(timer)
                compactButton(heater)
                compactButton(manual)
            }

            remoteDivider

            // Posture (back + leg)
            HStack(alignment: .top, spacing: 10) {
                verticalPair(title: "등받이", top: backRaise, bottom: backRecline)
                verticalPair(title: "다리",  top: legRaise,  bottom: legLower)
            }
            .frame(maxWidth: .infinity)

            // Posture presets (Zero G + Reset)
            section(title: "자세 프리셋") {
                HStack(spacing: 10) {
                    wideButton(zeroG)
                    wideButton(reset)
                }
            }

            remoteDivider

            // Massage tuning
            HStack(spacing: 10) {
                compactButton(speed)
                compactButton(width)
                compactButton(footRoller)
            }

            HStack(spacing: 10) {
                wideButton(air)
                wideButton(airLevel)
            }

            remoteDivider

            // Massage head (manual-only)
            section(title: "마사지 헤드 · 수동 전용") {
                HStack(spacing: 10) {
                    wideButton(headUp)
                    wideButton(headDown)
                }
            }

            remoteDivider

            // Auto modes
            section(title: "오토 모드") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(autoModes) { item in
                        ControlCommandButton(item: item, state: liveState(item.code), minHeight: 48, onPress: onPress, onRelease: onRelease)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: padWidth)
        .background(remoteBodyBackground)
    }

    private var remoteBodyBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(.systemGray6), Color(.systemGray5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    private var remoteDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.none)
                .padding(.leading, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactButton(_ item: ControlItem) -> some View {
        ControlCommandButton(item: item, state: liveState(item.code), minHeight: 54, onPress: onPress, onRelease: onRelease)
            .frame(width: sideButtonWidth)
    }

    private func wideButton(_ item: ControlItem) -> some View {
        ControlCommandButton(item: item, state: liveState(item.code), minHeight: 54, onPress: onPress, onRelease: onRelease)
            .frame(width: halfButtonWidth)
    }

    private func verticalPair(title: String, top: ControlItem, bottom: ControlItem) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ControlCommandButton(item: top, state: liveState(top.code), minHeight: 46, onPress: onPress, onRelease: onRelease)
            ControlCommandButton(item: bottom, state: liveState(bottom.code), minHeight: 46, onPress: onPress, onRelease: onRelease)
        }
        .frame(maxWidth: halfButtonWidth)
    }
}

private struct ControlCommandButton: View {
    let item: ControlItem
    var state: ControlState?
    var minHeight: CGFloat = 64
    let onPress: (String) -> Void
    let onRelease: () -> Void

    var body: some View {
        Button {} label: {
            VStack(spacing: 2) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(iconFont)
                }
                Text(item.label)
                    .font(labelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let stateLabel = state?.label {
                    Text(stateLabel)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .opacity(0.85)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 5)
        }
        .buttonStyle(PressReleaseCommandButtonStyle(
            code: item.code,
            prominence: effectiveProminence,
            onPress: onPress,
            onRelease: onRelease
        ))
        .accessibilityAction {
            onPress(item.code)
            onRelease()
        }
    }

    private var effectiveProminence: ControlItem.Prominence {
        if item.prominence == .primary { return .primary }
        if state?.isOn == true { return .active }
        return item.prominence
    }

    private var iconFont: Font {
        switch effectiveProminence {
        case .primary, .active: return .title3.weight(.semibold)
        case .normal:           return .body.weight(.semibold)
        case .subtle:           return .callout.weight(.semibold)
        }
    }

    private var labelFont: Font {
        switch effectiveProminence {
        case .primary, .active: return .system(size: 14, weight: .semibold)
        case .normal:           return .system(size: 12, weight: .medium)
        case .subtle:           return .system(size: 11, weight: .medium)
        }
    }

    private var foreground: Color {
        switch effectiveProminence {
        case .primary, .active: return .white
        case .normal, .subtle:  return .primary
        }
    }
}

private struct PressReleaseCommandButtonStyle: ButtonStyle {
    let code: String
    let prominence: ControlItem.Prominence
    let onPress: (String) -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressReleaseCommandButtonBody(
            configuration: configuration,
            code: code,
            prominence: prominence,
            onPress: onPress,
            onRelease: onRelease
        )
    }
}

private struct PressReleaseCommandButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let code: String
    let prominence: ControlItem.Prominence
    let onPress: (String) -> Void
    let onRelease: () -> Void

    @State private var wasPressed = false

    var body: some View {
        configuration.label
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.02 : 0.08), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.04 : 0.14),
                radius: configuration.isPressed ? 1 : 4,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .offset(y: configuration.isPressed ? 1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && !wasPressed {
                    wasPressed = true
                    onPress(code)
                } else if !isPressed && wasPressed {
                    wasPressed = false
                    onRelease()
                }
            }
    }

    private var buttonBackground: Color {
        switch prominence {
        case .primary:
            return configuration.isPressed ? Color.accentColor.opacity(0.82) : Color.accentColor
        case .active:
            return configuration.isPressed ? Color.green.opacity(0.82) : Color.green
        case .normal:
            return configuration.isPressed ? Color(.systemGray4) : Color(.secondarySystemBackground)
        case .subtle:
            return configuration.isPressed ? Color(.systemGray5) : Color(.tertiarySystemBackground)
        }
    }
}
