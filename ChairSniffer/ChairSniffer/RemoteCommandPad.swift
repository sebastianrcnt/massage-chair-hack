import SwiftUI

struct ControlItem: Identifiable {
    enum Prominence {
        case primary
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
    @Binding var autoSendRelease: Bool
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

    private let power = ControlItem(code: "0303", label: "Power", icon: "power", prominence: .primary)
    private let pause = ControlItem(code: "0322", label: "Pause", icon: "playpause", prominence: .primary)
    private let timer = ControlItem(code: "032D", label: "Timer", icon: "timer")
    private let heater = ControlItem(code: "0330", label: "Heater", icon: "heat.waves")
    private let speed = ControlItem(code: "0327", label: "Speed", icon: "speedometer")
    private let manual = ControlItem(code: "0363", label: "Manual", icon: "slider.horizontal.3")
    private let backRaise = ControlItem(code: "0302", label: "Back Up", icon: "chevron.up")
    private let backRecline = ControlItem(code: "0304", label: "Back Down", icon: "chevron.down")
    private let legRaise = ControlItem(code: "0307", label: "Leg Up", icon: "chevron.up")
    private let legLower = ControlItem(code: "0301", label: "Leg Down", icon: "chevron.down")
    private let zeroG = ControlItem(code: "0306", label: "Zero G", icon: "figure.flexibility", prominence: .primary)
    private let width = ControlItem(code: "0364", label: "Width", icon: "arrow.left.and.right")
    private let footRoller = ControlItem(code: "0331", label: "Foot", icon: "circle.dotted")
    private let air = ControlItem(code: "0375", label: "Air", icon: "wind")
    private let airLevel = ControlItem(code: "0315", label: "Air Level", icon: "gauge.medium")
    private let posUp = ControlItem(code: "032C", label: "Pos Up", icon: "arrow.up")
    private let posDown = ControlItem(code: "032F", label: "Pos Down", icon: "arrow.down")
    private let reset = ControlItem(code: "0384", label: "Reset", icon: "arrow.counterclockwise")
    private let autoModes = [
        ControlItem(code: "031F", label: "충전", icon: "battery.100"),
        ControlItem(code: "0391", label: "소화", icon: "sparkles"),
        ControlItem(code: "0305", label: "클래식", icon: "music.note"),
        ControlItem(code: "0321", label: "숙면", icon: "moon"),
        ControlItem(code: "031E", label: "스트레칭", icon: "figure.cooldown"),
        ControlItem(code: "0320", label: "힐링", icon: "heart")
    ]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ControlCommandButton(
                        item: power,
                        minHeight: 58,
                        autoSendRelease: autoSendRelease,
                        onPress: onPress,
                        onRelease: onRelease
                    )
                    ControlCommandButton(
                        item: pause,
                        minHeight: 58,
                        autoSendRelease: autoSendRelease,
                        onPress: onPress,
                        onRelease: onRelease
                    )
                }

                HStack(spacing: 10) {
                    compactButton(timer)
                    compactButton(heater)
                    compactButton(manual)
                }

                remoteDivider

                HStack(alignment: .center, spacing: 10) {
                    verticalPair(title: "Back", top: backRaise, bottom: backRecline)
                    ControlCommandButton(
                        item: zeroG,
                        minHeight: 86,
                        autoSendRelease: autoSendRelease,
                        onPress: onPress,
                        onRelease: onRelease
                    )
                    .frame(width: sideButtonWidth)
                    verticalPair(title: "Leg", top: legRaise, bottom: legLower)
                }

                remoteDivider

                HStack(spacing: 10) {
                    compactButton(speed)
                    compactButton(width)
                    compactButton(footRoller)
                }

                HStack(spacing: 10) {
                    wideButton(air)
                    wideButton(airLevel)
                }

                HStack(spacing: 10) {
                    compactButton(posUp)
                    compactButton(posDown)
                    compactButton(reset)
                }

                remoteDivider

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(autoModes) { item in
                        ControlCommandButton(
                            item: item,
                            minHeight: 48,
                            autoSendRelease: autoSendRelease,
                            onPress: onPress,
                            onRelease: onRelease
                        )
                    }
                }

                Toggle(isOn: $autoSendRelease) {
                    Label("Auto Release", systemImage: "arrow.up.circle")
                }
                .font(.footnote.weight(.medium))
                .tint(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
            .frame(width: padWidth)
            .background(remoteBodyBackground)
        }
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

    private func compactButton(_ item: ControlItem) -> some View {
        ControlCommandButton(
            item: item,
            minHeight: 54,
            autoSendRelease: autoSendRelease,
            onPress: onPress,
            onRelease: onRelease
        )
        .frame(width: sideButtonWidth)
    }

    private func wideButton(_ item: ControlItem) -> some View {
        ControlCommandButton(
            item: item,
            minHeight: 54,
            autoSendRelease: autoSendRelease,
            onPress: onPress,
            onRelease: onRelease
        )
        .frame(width: halfButtonWidth)
    }

    private func verticalPair(title: String, top: ControlItem, bottom: ControlItem) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ControlCommandButton(
                item: top,
                minHeight: 46,
                autoSendRelease: autoSendRelease,
                onPress: onPress,
                onRelease: onRelease
            )
            ControlCommandButton(
                item: bottom,
                minHeight: 46,
                autoSendRelease: autoSendRelease,
                onPress: onPress,
                onRelease: onRelease
            )
        }
        .frame(width: sideButtonWidth)
    }
}

private struct ControlCommandButton: View {
    let item: ControlItem
    var minHeight: CGFloat = 64
    let autoSendRelease: Bool
    let onPress: (String) -> Void
    let onRelease: () -> Void

    var body: some View {
        Button {} label: {
            VStack(spacing: 3) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(iconFont)
                }
                Text(item.label)
                    .font(labelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 5)
        }
        .buttonStyle(PressReleaseCommandButtonStyle(
            code: item.code,
            prominence: item.prominence,
            autoSendRelease: autoSendRelease,
            onPress: onPress,
            onRelease: onRelease
        ))
        .accessibilityAction {
            onPress(item.code)
            if autoSendRelease { onRelease() }
        }
    }

    private var iconFont: Font {
        switch item.prominence {
        case .primary: return .title3.weight(.semibold)
        case .normal: return .body.weight(.semibold)
        case .subtle: return .callout.weight(.semibold)
        }
    }

    private var labelFont: Font {
        switch item.prominence {
        case .primary: return .system(size: 14, weight: .semibold)
        case .normal: return .system(size: 12, weight: .medium)
        case .subtle: return .system(size: 11, weight: .medium)
        }
    }

    private var foreground: Color {
        switch item.prominence {
        case .primary: return .white
        case .normal, .subtle: return .primary
        }
    }
}

private struct PressReleaseCommandButtonStyle: ButtonStyle {
    let code: String
    let prominence: ControlItem.Prominence
    let autoSendRelease: Bool
    let onPress: (String) -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressReleaseCommandButtonBody(
            configuration: configuration,
            code: code,
            prominence: prominence,
            autoSendRelease: autoSendRelease,
            onPress: onPress,
            onRelease: onRelease
        )
    }
}

private struct PressReleaseCommandButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let code: String
    let prominence: ControlItem.Prominence
    let autoSendRelease: Bool
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
                    if autoSendRelease {
                        onRelease()
                    }
                }
            }
    }

    private var buttonBackground: Color {
        switch prominence {
        case .primary:
            return configuration.isPressed ? Color.accentColor.opacity(0.82) : Color.accentColor
        case .normal:
            return configuration.isPressed ? Color(.systemGray4) : Color(.secondarySystemBackground)
        case .subtle:
            return configuration.isPressed ? Color(.systemGray5) : Color(.tertiarySystemBackground)
        }
    }
}
