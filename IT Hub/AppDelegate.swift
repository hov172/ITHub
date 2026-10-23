import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let networkModel = NetworkModel.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fleets that do not need the Wi-Fi name can switch the location prompt off in menu.json.
        guard QuickActionConfig.loadPolicy().wifiNameLookup else { return }
        networkModel.requestPermissionOnFirstLaunch()
    }
}
