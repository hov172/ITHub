import SwiftUI

struct WiFiPermissionView: View {
    @ObservedObject var model: NetworkModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Show your Wi-Fi name", systemImage: "wifi").font(.title2.bold())
            Text("IT Hub shows the name of the Wi-Fi network you are on, so the Services card can tell whether you are on the expected network. macOS only reveals that name to apps with Location Services access, so it will ask you to allow location for IT Hub.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            Text("IT Hub never reads your coordinates, stores a location, or sends anything anywhere.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            Text(model.permissionDescription).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.isAuthorized ? "Done" : "Later") { model.closePermissionWindow() }.keyboardShortcut(.cancelAction)
                Spacer()
                if !model.isAuthorized {
                    Button(model.permissionActionTitle) { model.requestSystemPermission() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 440)
    }
}
