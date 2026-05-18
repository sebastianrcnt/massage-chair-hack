import SwiftUI

struct HomeTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let power = ControlItem(code: "0303", label: "전원",     icon: "power",     prominence: .primary, iconOnly: true)
    private let pause = ControlItem(code: "0322", label: "일시정지", icon: "playpause", prominence: .primary, iconOnly: true)
    private let timer = ControlItem(code: "032D", label: "타이머", emphasizesState: true)
    private let manual = ControlItem(code: "0363", label: "수동", emphasizesState: true, releaseCode: "0339")
    private let headUp = ControlItem(code: "032C", label: "헤드", icon: "arrow.up", repeatsProgressHaptics: true)
    private let headDown = ControlItem(code: "032F", label: "헤드", icon: "arrow.down", repeatsProgressHaptics: true)

    private let autoModes: [ControlItem] = [
        ControlItem(code: "031F", label: "충전",     icon: "battery.100"),
        ControlItem(code: "0320", label: "힐링",     icon: "heart"),
        ControlItem(code: "031E", label: "스트레칭", icon: "figure.cooldown", releaseCode: "0336"),
        ControlItem(code: "0321", label: "숙면",     icon: "moon"),
        ControlItem(code: "0305", label: "클래식",   icon: "music.note"),
        ControlItem(code: "0391", label: "소화",     icon: "sparkles"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TabHeader(title: "홈", ble: ble, onStatusTap: onStatusTap)
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 14) {
                        primaryRow
                        timerRow
                        autoModeRow
                        manualRow
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var primaryRow: some View {
        HStack(spacing: 12) {
            button(power, minHeight: 76)
            button(pause, minHeight: 76)
        }
    }

    private var timerRow: some View {
        HStack(spacing: 12) {
            button(timer, minHeight: 76)
            autoTimerExtendButton
                .frame(width: 76)
        }
    }

    private var autoModeRow: some View {
        HStack(spacing: 8) {
            ForEach(autoModes) { item in
                button(item, minHeight: 54)
            }
        }
    }

    private var manualRow: some View {
        HStack(spacing: 12) {
            button(manual, minHeight: 64)
            HStack(spacing: 12) {
                button(headUp, minHeight: 64)
                button(headDown, minHeight: 64)
            }
        }
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
