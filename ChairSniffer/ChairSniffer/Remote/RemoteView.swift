import SwiftUI

struct RemoteView: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
                    HeroStatusCard(ble: ble)
                        .frame(maxWidth: heroWidth(for: geo.size.width))

                    RemoteCommandPad(availableWidth: geo.size.width) { code in
                        ble.send(command: code)
                    } onRelease: {
                        ble.send(command: "0355")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func heroWidth(for total: CGFloat) -> CGFloat {
        min(max(total - 28, 304), 440)
    }
}
