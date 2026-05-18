import SwiftUI

struct TabHeader: View {
    let title: String
    @ObservedObject var ble: ChairBLEManager
    let onStatusTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            StatusMenuButton(ble: ble, onTap: onStatusTap)
        }
    }
}
