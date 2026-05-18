import SwiftUI

struct MassageTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let speed      = ControlItem(code: "0327", label: "속도", emphasizesState: true, releaseCode: "0336")
    private let width      = ControlItem(code: "0364", label: "폭", emphasizesState: true)
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted", releaseCode: "0339")
    private let heater     = ControlItem(code: "0330", label: "온열",   icon: "heat.waves")
    private let air        = ControlItem(code: "0375", label: "에어",     icon: "pillow.fill")
    private let airLevel   = ControlItem(code: "0315", label: "에어 세기", emphasizesState: true)

    private let manual   = ControlItem(code: "0363", label: "수동", emphasizesState: true, releaseCode: "0339")
    private let headUp   = ControlItem(code: "032C", label: "헤드 올리기", icon: "arrow.up", repeatsProgressHaptics: true)
    private let headDown = ControlItem(code: "032F", label: "헤드 내리기", icon: "arrow.down", repeatsProgressHaptics: true)

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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    button(air, minHeight: 76)
                    button(airLevel, minHeight: 76)
                }
                AirAreaStatusRow(activeAreas: ble.activeAirAreas)
            }
        }
    }

    private var manualSection: some View {
        ControlSection(title: "수동 조정", footnote: "헤드 위치는 수동을 한 번 이상 눌러 활성화한 뒤 동작합니다.") {
            VStack(spacing: 12) {
                button(manual, minHeight: 64)
                RollerPositionStatusRow(position: ble.rollerPosition)
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
            onRelease: { ble.send(command: item.releaseCode) }
        )
    }
}

private struct AirAreaStatusRow: View {
    let activeAreas: [ChairAirArea]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("에어 부위")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ChairAirArea.allCases) { area in
                    let isActive = activeAreas.contains(area)
                    Text(area.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isActive ? Color.chairControlTextOnTint : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(chipBackground(isActive: isActive), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func chipBackground(isActive: Bool) -> Color {
        isActive ? .chairActive : Color(.tertiarySystemFill)
    }
}

private struct RollerPositionStatusRow: View {
    let position: ChairRollerPosition?

    var body: some View {
        HStack(spacing: 12) {
            Text("롤러 위치")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(position?.label ?? "-")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 38, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(ChairRollerPosition.allCases) { item in
                    Circle()
                        .fill(item == position ? Color.chairActive : Color(.tertiarySystemFill))
                        .frame(width: 9, height: 9)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 32)
    }
}
