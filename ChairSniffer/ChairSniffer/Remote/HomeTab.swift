import SwiftUI

struct HomeTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let power = ControlItem(code: "0303", label: "전원",     icon: "power",     prominence: .primary)
    private let pause = ControlItem(code: "0322", label: "일시정지", icon: "playpause", prominence: .primary)
    private let timer = ControlItem(code: "032D", label: "타이머", emphasizesState: true)

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
                    VStack(spacing: 24) {
                        primaryRow
                        timerRow
                        autoModeSection
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
        button(timer, minHeight: 76)
    }

    private var autoModeSection: some View {
        ControlSection(title: "오토 모드") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(autoModes) { item in
                    button(item, minHeight: 72)
                }
            }
        }
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
