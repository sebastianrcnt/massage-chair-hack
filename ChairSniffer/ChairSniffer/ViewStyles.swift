import SwiftUI

extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    func screenPadding() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

extension String {
    func leftPad(to length: Int) -> String {
        let padding = max(0, length - count)
        return String(repeating: "0", count: padding) + self
    }

    func centered(in width: Int) -> String {
        if count >= width { return String(prefix(width)) }
        let pad = width - count
        let left = pad / 2
        let right = pad - left
        return String(repeating: " ", count: left) + self + String(repeating: " ", count: right)
    }
}
