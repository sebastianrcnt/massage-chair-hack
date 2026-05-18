import SwiftUI

struct PostureTab: View {
    @ObservedObject var ble: ChairBLEManager

    private let backRaise   = ControlItem(code: "0302", label: "올리기", icon: "chevron.up")
    private let backRecline = ControlItem(code: "0304", label: "내리기", icon: "chevron.down")
    private let legRaise    = ControlItem(code: "0307", label: "올리기", icon: "chevron.up")
    private let legLower    = ControlItem(code: "0301", label: "내리기", icon: "chevron.down")

    private let zeroG = ControlItem(code: "0306", label: "무중력", icon: "figure.flexibility")
    private let reset = ControlItem(code: "0384", label: "원위치", icon: "arrow.counterclockwise")

    private let manual   = ControlItem(code: "0363", label: "수동 모드", icon: "slider.horizontal.3")
    private let headUp   = ControlItem(code: "032C", label: "헤드 올리기", icon: "arrow.up")
    private let headDown = ControlItem(code: "032F", label: "헤드 내리기", icon: "arrow.down")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                postureSection
                presetSection
                manualSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var postureSection: some View {
        HStack(alignment: .top, spacing: 12) {
            pair(title: "등받이", top: backRaise, bottom: backRecline)
            pair(title: "다리",  top: legRaise,  bottom: legLower)
        }
    }

    private var presetSection: some View {
        ControlSection(title: "자세 프리셋") {
            HStack(spacing: 12) {
                button(zeroG, minHeight: 76)
                button(reset, minHeight: 76)
            }
        }
    }

    private var manualSection: some View {
        ControlSection(title: "수동 조정", footnote: "헤드 위치는 수동 모드에서만 동작합니다.") {
            VStack(spacing: 12) {
                button(manual, minHeight: 64)
                HStack(spacing: 12) {
                    button(headUp, minHeight: 64)
                    button(headDown, minHeight: 64)
                }
            }
        }
    }

    private func pair(title: String, top: ControlItem, bottom: ControlItem) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            button(top, minHeight: 64)
            button(bottom, minHeight: 64)
        }
        .frame(maxWidth: .infinity)
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
