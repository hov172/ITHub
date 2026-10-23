import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var health = DeviceHealthModel()
    var body: some Scene {
        MenuBarExtra {
            DashboardView(health: health).frame(width: 720)
        } label: {
            Image(nsImage: health.menuBarImage)
                .accessibilityLabel(health.hoverSummary)
                .help(health.hoverSummary)
                .onAppear { health.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
