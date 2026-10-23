import SwiftUI
import Combine
import CoreLocation

@MainActor final class NetworkModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkModel()
    @Published private(set) var services: [NetworkServiceInfo]? = nil
    private let location = CLLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var startupRequestPending = false
    private var activeObserver: AnyCancellable?
    private var permissionWindow: NSWindow?
    var permissionActionTitle: String {
        switch authorizationStatus {
        case .notDetermined: "Allow Wi-Fi Name"
        case .denied, .restricted: "Open Location Settings"
        default: "Refresh Wi-Fi Name"
        }
    }
    var permissionDescription: String {
        switch authorizationStatus {
        case .notDetermined: "Permission has not been requested yet. A macOS permission dialog should appear; you can also use Allow Wi-Fi Name below."
        case .denied: "Location access was previously denied. Enable IT Hub in System Settings → Privacy & Security → Location Services. macOS will not show the original prompt again."
        case .restricted: "Location access is restricted. Review Location Services or contact your administrator."
        default: "Location access is already allowed. macOS will not ask again; refresh to read the network name."
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "IT Hub — Wi-Fi access"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WiFiPermissionView(model: self))
            window.center()
            permissionWindow = window
        }
        guard let window = permissionWindow else { return }
        startupRequestPending = location.authorizationStatus == .notDetermined
        activeObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window))
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestPendingPermission() }
            }
        // Floating above the panel put this window over the macOS location prompt, hiding Allow.
        WindowPresentation.presentBeneathSystemPrompts(window)
        requestPendingPermission()
    }
    private func requestPendingPermission() {
        guard startupRequestPending, NSApplication.shared.isActive, permissionWindow?.isKeyWindow == true else { return }
        startupRequestPending = false
        activeObserver = nil
        guard location.authorizationStatus == .notDetermined else { return }
        location.requestWhenInUseAuthorization()
    }
    func closePermissionWindow() {
        startupRequestPending = false
        activeObserver = nil
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
            if self.authorizationStatus == .authorizedAlways { self.closePermissionWindow() }
        }
    }
}
