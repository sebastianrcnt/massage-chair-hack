import SwiftUI

struct MassageTab: View {
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    private let manual    = ControlItem(code: "0363", label: "수동", emphasizesState: true, releaseCode: "0339")
    private let speed      = ControlItem(code: "0327", label: "속도", emphasizesState: true, releaseCode: "0336")
    private let width      = ControlItem(code: "0364", label: "폭", emphasizesState: true)
    private let area       = ControlItem(code: "0314", label: "부위", icon: "scope")
    private let headUp     = ControlItem(code: "032C", label: "헤드", icon: "arrow.up", repeatsProgressHaptics: true)
    private let headDown   = ControlItem(code: "032F", label: "헤드", icon: "arrow.down", repeatsProgressHaptics: true)
    private let footRoller = ControlItem(code: "0331", label: "발롤러", icon: "circle.dotted", releaseCode: "0339")
    private let heater     = ControlItem(code: "0330", label: "온열",   icon: "heat.waves")
    private let air        = ControlItem(code: "0375", label: "에어",     icon: "pillow.fill")
    private let airLevel   = ControlItem(code: "0315", label: "에어 세기", emphasizesState: true)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TabHeader(title: "수동", ble: ble, onStatusTap: onStatusTap)
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 24) {
                        manualSection
                        intensitySection
                        airSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var manualSection: some View {
        ControlSection(title: "수동 제어") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    button(manual, minHeight: 76)
                    button(area, minHeight: 76)
                }
                HStack(spacing: 12) {
                    button(headUp, minHeight: 64)
                    button(headDown, minHeight: 64)
                }
            }
        }
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
