import SwiftUI
import UIKit

struct ControlItem: Identifiable {
    enum Prominence {
        case primary
        case active
        case normal
    }

    let code: String
    let label: String
    let icon: String?
    let prominence: Prominence
    let emphasizesState: Bool
    let iconOnly: Bool
    let releaseCode: String
    let repeatsProgressHaptics: Bool

    var id: String { code + label }

    init(code: String,
         label: String,
         icon: String? = nil,
         prominence: Prominence = .normal,
         emphasizesState: Bool = false,
         iconOnly: Bool = false,
         releaseCode: String = "0355",
         repeatsProgressHaptics: Bool = false) {
        self.code = code
        self.label = label
        self.icon = icon
        self.prominence = prominence
        self.emphasizesState = emphasizesState
        self.iconOnly = iconOnly
        self.releaseCode = releaseCode
        self.repeatsProgressHaptics = repeatsProgressHaptics
    }
}

struct ControlCommandButton: View {
    let item: ControlItem
    var state: ControlState?
    var minHeight: CGFloat = 64
    let onPress: (String) -> Void
    let onRelease: () -> Void

    var body: some View {
        Button {} label: {
            buttonContent
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .buttonStyle(PressReleaseCommandButtonStyle(
            code: item.code,
            prominence: effectiveProminence,
            repeatsProgressHaptics: item.repeatsProgressHaptics,
            onPress: onPress,
            onRelease: onRelease
        ))
        .accessibilityAction {
            ChairHaptics.heavy()
            onPress(item.code)
            onRelease()
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        if item.emphasizesState {
            VStack(spacing: 3) {
                Text(primaryStateText)
                    .font(.system(size: 25, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(item.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(0.72)
            }
        } else if item.iconOnly {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.title.weight(.semibold))
            }
        } else {
            VStack(spacing: 4) {
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
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .opacity(0.78)
                }
            }
        }
    }

    private var primaryStateText: String {
        state?.label ?? "-"
    }

    private var effectiveProminence: ControlItem.Prominence {
        if item.prominence == .primary { return .primary }
        if state?.isOn == true { return .active }
        return item.prominence
    }

    private var iconFont: Font {
        switch effectiveProminence {
        case .primary, .active: return .title2.weight(.semibold)
        case .normal:           return .title3.weight(.medium)
        }
    }

    private var labelFont: Font {
        switch effectiveProminence {
        case .primary, .active: return .system(size: 15, weight: .semibold)
        case .normal:           return .system(size: 13, weight: .medium)
        }
    }

    private var foreground: Color {
        switch effectiveProminence {
        case .primary, .active: return .chairControlTextOnTint
        case .normal:           return .primary
        }
    }
}

private struct PressReleaseCommandButtonStyle: ButtonStyle {
    let code: String
    let prominence: ControlItem.Prominence
    let repeatsProgressHaptics: Bool
    let onPress: (String) -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressReleaseCommandButtonBody(
            configuration: configuration,
            code: code,
            prominence: prominence,
            repeatsProgressHaptics: repeatsProgressHaptics,
            onPress: onPress,
            onRelease: onRelease
        )
    }
}

private struct PressReleaseCommandButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let code: String
    let prominence: ControlItem.Prominence
    let repeatsProgressHaptics: Bool
    let onPress: (String) -> Void
    let onRelease: () -> Void

    @State private var wasPressed = false
    @State private var progressHapticsTask: Task<Void, Never>?

    var body: some View {
        configuration.label
            .glassEffect(glassStyle, in: .rect(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && !wasPressed {
                    wasPressed = true
                    ChairHaptics.heavy()
                    startProgressHapticsIfNeeded()
                    onPress(code)
                } else if !isPressed && wasPressed {
                    wasPressed = false
                    stopProgressHaptics()
                    onRelease()
                }
            }
            .onDisappear {
                stopProgressHaptics()
            }
    }

    private func startProgressHapticsIfNeeded() {
        guard repeatsProgressHaptics else { return }
        progressHapticsTask?.cancel()
        progressHapticsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    ChairHaptics.heavy()
                }
            }
        }
    }

    private func stopProgressHaptics() {
        progressHapticsTask?.cancel()
        progressHapticsTask = nil
    }

    private var glassStyle: Glass {
        switch prominence {
        case .primary:
            return .regular.tint(.chairTint).interactive()
        case .active:
            return .regular.tint(.chairActive).interactive()
        case .normal:
            return .regular.interactive()
        }
    }
}

enum ChairHaptics {
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func doubleHeavy() {
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            heavy()
        }
    }
}

// MARK: - Section helper

struct ControlSection<Content: View>: View {
    let title: String?
    let footnote: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
            }
            content
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
