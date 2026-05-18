import SwiftUI

extension Color {
    /// Primary CTA + nav tint. Neutral, with enough dark-mode lift for glass controls.
    static let chairTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.82, alpha: 1)
            : UIColor(white: 0.24, alpha: 1)
    })

    /// Toggle "on" / active accent. Slightly stronger neutral than the default button tint.
    static let chairActive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor(white: 0.12, alpha: 1)
    })

    static let chairControlTextOnTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
}
