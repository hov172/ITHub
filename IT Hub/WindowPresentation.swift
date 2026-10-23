import SwiftUI
import AppKit

@MainActor enum WindowPresentation {
    static weak var dashboard: NSWindow?
    static func prepare(_ window: NSWindow) {
        // Independent windows remain usable if MenuBarExtra dismisses its panel.
        let parentLevel = dashboard?.level.rawValue ?? NSWindow.Level.normal.rawValue
        window.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, parentLevel + 1))
        window.hidesOnDeactivate = true
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    private static func beginHandoff(to bundleID: String) {
        // Yield while this user-initiated action still has activation authority.
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        // Hide all our panels, not only a possibly stale MenuBarExtra window reference.
        NSApplication.shared.hide(nil)
    }
    private static func finishHandoff(_ app: NSRunningApplication?, error: Error?) {
        guard let app, error == nil else {
            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not open the requested app"
            alert.informativeText = error?.localizedDescription ?? "macOS did not return the destination app."
            alert.runModal()
            return
        }
        app.unhide()
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(to: app)
            app.activate(from: .current, options: [.activateAllWindows])
        } else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }
    static func openSettings(_ target: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + target),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        beginHandoff(to: "com.apple.systempreferences")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { app, error in
            Task { @MainActor in finishHandoff(app, error: error) }
        }
    }
    static func openApplication(_ url: URL) {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.apple.ActivityMonitor"
        beginHandoff(to: bundleID)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            Task { @MainActor in finishHandoff(app, error: error) }
        }
    }

}

struct DashboardWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowReaderView { WindowReaderView() }
    func updateNSView(_ view: WindowReaderView, context: Context) {}
    final class WindowReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowPresentation.dashboard = window }
        }
    }
}
