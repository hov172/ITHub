import SwiftUI

struct WiFiPermissionView: View {
    @ObservedObject var model: NetworkModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Show your Wi-Fi name", systemImage: "wifi").font(.title2.bold())
            Text("macOS requires location access before IT Hub can read the Wi-Fi network name. IT Hub does not request your coordinates or send this information anywhere.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            Text(model.permissionDescription).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Later") { model.closePermissionWindow() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.permissionActionTitle) { model.requestLocation() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440)
    }
}
