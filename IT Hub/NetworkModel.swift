import SwiftUI
import Combine
import CoreLocation

@MainActor final class NetworkModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkModel()
    @Published private(set) var services: [NetworkServiceInfo]? = nil
    private let location = CLLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var permissionWindow: NSWindow?
    var isAuthorized: Bool { authorizationStatus == .authorizedAlways || authorizationStatus == .authorized }
    var permissionActionTitle: String {
        switch authorizationStatus {
        case .notDetermined: "Allow Wi-Fi Name"
        case .denied, .restricted: "Open Location Settings"
        default: "Refresh Wi-Fi Name"
        }
    }
    var permissionDescription: String {
        switch authorizationStatus {
        case .notDetermined: "Nothing has been asked yet. When you click Allow Wi-Fi Name, macOS shows its own permission dialog; choose Allow there."
        case .denied: "Location access was previously denied. Enable IT Hub in System Settings → Privacy & Security → Location Services. macOS will not show the original prompt again."
        case .restricted: "Location access is restricted. Review Location Services or contact your administrator."
        default: "Location access is allowed. The Services card shows the Wi-Fi name; macOS will not ask again."
        }
    }
    func requestPermissionOnFirstLaunch() {
        authorizationStatus = location.authorizationStatus
        let key = "wifiPermissionWelcomeShownV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        switch authorizationStatus {
        case .notDetermined, .denied, .restricted:
            showPermissionWindow()
        default: break
        }
    }
    private func showPermissionWindow() {
        if permissionWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "IT Hub — Wi-Fi access"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WiFiPermissionView(model: self))
            window.center()
            permissionWindow = window
        }
        guard let window = permissionWindow else { return }
        // The window only explains. Asking macOS at the same time put the system dialog over
        // this text and the window closed on Allow, so nobody could read why it was asked.
        // Normal level keeps the system dialog, when it comes, on top and clickable.
        WindowPresentation.presentBeneathSystemPrompts(window)
    }
    /// Called by the window's button: the one place the system dialog is triggered.
    func requestSystemPermission() {
        guard location.authorizationStatus == .notDetermined else { requestLocation(); return }
        location.requestWhenInUseAuthorization()
    }
    func closePermissionWindow() {
        permissionWindow?.close()
    }
    override init() {
        super.init()
        location.delegate = self
        authorizationStatus = location.authorizationStatus
    }
    func refresh() { services = NetworkService.services() }
    func requestLocation() {
        authorizationStatus = location.authorizationStatus
        switch location.authorizationStatus {
        case .notDetermined: showPermissionWindow()
        case .denied, .restricted:
            WindowPresentation.openSettings("com.apple.preference.security?Privacy_LocationServices")
        default: refresh()
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.location.authorizationStatus
            self.refresh()
        }
    }
}
