import SwiftUI

struct MassageTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let speed      = ControlItem(code: "0327", label: "속도", emphasizesState: true)
    private let width      = ControlItem(code: "0364", label: "폭", emphasizesState: true)
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted")
    private let heater     = ControlItem(code: "0330", label: "온열",   icon: "heat.waves")
    private let air        = ControlItem(code: "0375", label: "에어",     icon: "pillow.fill")
    private let airLevel   = ControlItem(code: "0315", label: "에어 세기", emphasizesState: true)

    private let manual   = ControlItem(code: "0363", label: "수동", emphasizesState: true)
    private let headUp   = ControlItem(code: "032C", label: "헤드 올리기", icon: "arrow.up")
    private let headDown = ControlItem(code: "032F", label: "헤드 내리기", icon: "arrow.down")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TabHeader(title: "마사지", ble: ble, onStatusTap: onStatusTap)
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 24) {
                        intensitySection
                        airSection
                        manualSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var intensitySection: some View {
        ControlSection(title: "강도") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    button(speed, minHeight: 76)
                    button(width, minHeight: 76)
                }
                HStack(spacing: 12) {
                    button(footRoller, minHeight: 64)
                    button(heater, minHeight: 64)
                }
            }
        }
    }

    private var airSection: some View {
        ControlSection(title: "에어") {
            HStack(spacing: 12) {
                button(air, minHeight: 76)
                button(airLevel, minHeight: 76)
            }
        }
    }

    private var manualSection: some View {
        ControlSection(title: "수동 조정", footnote: "헤드 위치는 수동을 한 번 이상 눌러 활성화한 뒤 동작합니다.") {
            VStack(spacing: 12) {
                button(manual, minHeight: 64)
                HStack(spacing: 12) {
                    button(headUp, minHeight: 64)
                    button(headDown, minHeight: 64)
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
            onRelease: { ble.send(command: "0355") }
        )
    }
}
