import SwiftUI

struct MassageTab: View {
    @ObservedObject var ble: ChairBLEManager

    private let speed      = ControlItem(code: "0327", label: "속도",   icon: "speedometer")
    private let width      = ControlItem(code: "0364", label: "폭",     icon: "arrow.left.and.right")
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted")
    private let air        = ControlItem(code: "0375", label: "에어백",   icon: "bubble.left.and.bubble.right.fill")
    private let airLevel   = ControlItem(code: "0315", label: "에어 세기", icon: "gauge.medium")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                intensitySection
                airSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
                button(footRoller, minHeight: 64)
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
