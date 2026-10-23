import Foundation
import Combine
import Darwin
import AppKit

nonisolated enum UptimePolicy {
    static let defaultWarningDays: Double = 14
    /// `warningDays` of 0 disables the check: uptime is then always good when readable.
    static func status(for seconds: TimeInterval?, warningDays: Double = defaultWarningDays) -> HealthStatus {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return .unknown }
        guard warningDays > 0 else { return .good }
        return seconds >= warningDays * 86400 ? .attention : .good
    }
    static func label(_ status: HealthStatus, warningDays: Double) -> String {
        switch status {
        case .good: warningDays > 0 ? "Uptime below \(formatted(warningDays)) days" : "Uptime check disabled"
        case .attention: "A restart may speed up your Mac."
        default: "Uptime unavailable"
        }
    }
    static func formatted(_ days: Double) -> String {
        days == days.rounded() ? String(Int(days)) : String(format: "%.1f", days)
    }
}

@MainActor final class UptimeService: ObservableObject {
    @Published private(set) var seconds: TimeInterval?
    @Published private(set) var bootDate: Date?
    private var timer: AnyCancellable?
    private var wake: AnyCancellable?
    init() {
        refresh()
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func status(warningDays: Double) -> HealthStatus { UptimePolicy.status(for: seconds, warningDays: warningDays) }
    func refresh() {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            seconds = nil; bootDate = nil; return
        }
        let date = Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
        let elapsed = Date().timeIntervalSince(date)
        guard elapsed >= 0 else { seconds = nil; bootDate = nil; return }
        bootDate = date
        seconds = elapsed // Includes sleep; wake does not reset the boot timestamp.
    }
    var detail: String {
        guard let seconds else { return "Uptime unavailable" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 1440)d \((minutes / 60) % 24)h \(minutes % 60)m"
    }
}
