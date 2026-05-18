import SwiftUI

struct HomeTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let power = ControlItem(code: "0303", label: "전원",     icon: "power",     prominence: .primary, iconOnly: true)
    private let timer = ControlItem(code: "032D", label: "타이머", emphasizesState: true)
    private let backRaise = ControlItem(code: "0302", label: "등", icon: "chevron.up")
    private let backRecline = ControlItem(code: "0304", label: "등", icon: "chevron.down")
    private let legRaise = ControlItem(code: "0307", label: "다리", icon: "chevron.up")
    private let legLower = ControlItem(code: "0301", label: "다리", icon: "chevron.down")
    private let air = ControlItem(code: "0375", label: "에어", icon: "pillow.fill")
    private let airLevel = ControlItem(code: "0315", label: "강도", emphasizesState: true)
    private let heater = ControlItem(code: "0330", label: "온열", icon: "heat.waves")
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted", releaseCode: "0339")
    private let reset = ControlItem(code: "0384", label: "원위치", icon: "arrow.counterclockwise")

    private let autoModes: [ControlItem] = [
        ControlItem(code: "031F", label: "충전",     icon: "battery.100"),
        ControlItem(code: "0320", label: "힐링",     icon: "heart"),
        ControlItem(code: "031E", label: "스트레칭", icon: "figure.cooldown", releaseCode: "0336"),
        ControlItem(code: "0321", label: "숙면",     icon: "moon"),
        ControlItem(code: "0305", label: "클래식",   icon: "music.note"),
        ControlItem(code: "0391", label: "소화",     icon: "sparkles"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            TabHeader(title: "홈", ble: ble, onStatusTap: onStatusTap)
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 14) {
                    sessionRow
                    postureRow
                    comfortRows
                    autoModeRow
                    resetRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Color(.systemGroupedBackground))
        .onDisappear {
            ble.releaseLatchedPosture()
        }
    }

    private var sessionRow: some View {
        HStack(spacing: 12) {
            button(power, minHeight: 76)
            button(timer, minHeight: 76)
            autoTimerExtendButton
                .frame(width: 76)
        }
    }

    private var postureRow: some View {
        HStack(spacing: 8) {
            latchedPostureButton(backRaise)
            latchedPostureButton(backRecline)
            latchedPostureButton(legRaise)
            latchedPostureButton(legLower)
        }
    }

    private var comfortRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                button(air, minHeight: 68)
                button(airLevel, minHeight: 68)
            }
            HStack(spacing: 12) {
                button(heater, minHeight: 62)
                button(footRoller, minHeight: 62)
            }
        }
    }

    private var autoModeRow: some View {
        HStack(spacing: 8) {
            ForEach(autoModes) { item in
                button(item, minHeight: 54)
            }
        }
    }

    private var resetRow: some View {
        button(reset, minHeight: 76)
    }

    private var autoTimerExtendButton: some View {
        Button {
            ChairHaptics.heavy()
            ble.toggleAutoTimerExtend()
        } label: {
            Image(systemName: "infinity")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ble.autoTimerExtendEnabled ? Color.chairControlTextOnTint : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
        }
        .glassEffect(timerExtendGlass, in: .rect(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Auto timer extend")
    }

    private var timerExtendGlass: Glass {
        ble.autoTimerExtendEnabled ? .regular.tint(.chairActive).interactive() : .regular.interactive()
    }

    private func latchedPostureButton(_ item: ControlItem) -> some View {
        let isActive = ble.latchedPostureCommand == item.code
        return Button {
            ChairHaptics.heavy()
            ble.toggleLatchedPosture(command: item.code)
        } label: {
            VStack(spacing: 4) {
                if isActive {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.chairControlTextOnTint)
                } else if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                }
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isActive ? Color.chairControlTextOnTint : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .glassEffect(isActive ? .regular.tint(.chairActive).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("\(item.label) \(item.icon == "chevron.up" ? "up" : "down")")
    }

    private func button(_ item: ControlItem, minHeight: CGFloat) -> some View {
        ControlCommandButton(
            item: item,
            state: LiveStateLookup.state(for: item.code, ble: ble),
            minHeight: minHeight,
            onPress: { ble.send(command: $0) },
            onRelease: { ble.send(command: item.releaseCode) }
        )
    }
}
