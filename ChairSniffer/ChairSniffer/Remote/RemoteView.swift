import SwiftUI

struct RemoteView: View {
    @ObservedObject var ble: ChairBLEManager

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                RemoteCommandPad(availableWidth: geo.size.width) { code in
                    ble.send(command: code)
                } onRelease: {
                    ble.send(command: "0355")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}
