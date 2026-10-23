import SwiftUI
import Combine
import AppKit

nonisolated struct HealthNotice: Identifiable, Equatable {
    let id: String
    let status: HealthStatus
    let message: String
}
nonisolated enum HealthSummary {
    static func status(_ notices: [HealthNotice]) -> HealthStatus {
        if notices.contains(where: { $0.status == .critical }) { return .critical }
        if notices.contains(where: { $0.status == .attention }) { return .attention }
        if notices.contains(where: { $0.status == .unknown }) { return .unknown }
        return .good
    }
}
nonisolated enum UpdateNotice {
    static func message(_ labels: [String], currentMajor: Int) -> String {
        let pattern = #"(?:^|\s)(\d+)\.\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern), !labels.isEmpty else { return "macOS update or upgrade available" }
        let majors = labels.map { label -> Int? in
            let range = NSRange(label.startIndex..., in: label)
            guard let match = regex.firstMatch(in: label, range: range), let valueRange = Range(match.range(at: 1), in: label) else { return nil }
            return Int(label[valueRange])
        }
        if majors.compactMap({ $0 }).contains(where: { $0 > currentMajor }) { return "macOS upgrade available" }
        if majors.contains(where: { $0 == nil }) { return "macOS update or upgrade available" }
        return "macOS update available"
    }
}
@MainActor final class DeviceHealthModel: ObservableObject {
    let uptime = UptimeService()
    let memory = MemoryService()
    let security = SecurityService()
    let storage = StorageService()
    let battery = BatteryService()
    let updates = UpdateService()
    let networkModel = NetworkModel.shared
    let quickActions = QuickActionStore()
    private var subscriptions = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var wakeObserver: AnyCancellable?
    private var started = false
    private var refreshing = false
    private var updateTask: Task<Void, Never>?
    private var lastScan: Date?
    init() {
        [uptime.objectWillChange, memory.objectWillChange, security.objectWillChange,
         storage.objectWillChange, battery.objectWillChange, updates.objectWillChange,
         networkModel.objectWillChange, quickActions.objectWillChange].forEach { publisher in
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refresh()
                if self.updates.checkedAt.map({ Date().timeIntervalSince($0) >= self.quickActions.policy.updateScanMinutes * 60 }) ?? true { self.scanUpdates() }
            }
        }
        start()
    }
    func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in await self?.refresh() }
        scanUpdates()
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refresh()
                if self.lastScan.map({ Date().timeIntervalSince($0) >= self.quickActions.policy.updateScanMinutes * 60 }) ?? true { self.scanUpdates() }
            }
        }
    }
    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        networkModel.refresh(); uptime.refresh()
        // Profiles and managed files normally announce themselves; the minute refresh covers the
        // cases that do not, such as a preference domain cleared while cfprefsd was restarting.
        quickActions.reload()
        await security.refresh(); await storage.refresh(); await battery.refresh()
    }
    private func scanUpdates() {
        guard updateTask == nil else { return }
        lastScan = Date()
        updateTask = Task { [weak self] in
            guard let self else { return }
            await self.updates.refresh()
            self.updateTask = nil
        }
    }
    /// Severity FileVault-off carries into the notices and the menu bar icon. The FileVault card
    /// itself always shows the measured state, red when off, whatever the policy says.
    var fileVaultStatus: HealthStatus {
        security.state == .disabled ? quickActions.policy.fileVaultOff : security.state.status
    }
    var updatesStatus: HealthStatus {
        updates.healthStatus == .attention ? quickActions.policy.softwareUpdates : updates.healthStatus
    }
    var networkHealthStatus: HealthStatus {
        let measured = NetworkHealth.status(networkModel.services)
        return measured == .attention ? quickActions.policy.networkOffline : measured
    }
    var uptimeStatus: HealthStatus { uptime.status(warningDays: quickActions.policy.uptimeWarningDays) }
    var uptimeLabel: String { UptimePolicy.label(uptimeStatus, warningDays: quickActions.policy.uptimeWarningDays) }
    var notices: [HealthNotice] {
        var values: [HealthNotice] = []
        func add(_ id: String, _ state: HealthStatus, _ message: String) {
            if state != .good { values.append(.init(id: id, status: state, message: message)) }
        }
        add("filevault", fileVaultStatus, security.state.label)
        if let disk = storage.snapshot {
            let diskStatus = disk.status(policy: quickActions.policy)
            add("storage", diskStatus, diskStatus == .critical ? "Storage critically low" : "Storage is running low")
        } else { add("storage", .unknown, storage.checking ? "Checking storage…" : "Storage status unavailable") }
        add("uptime", uptimeStatus, uptimeLabel)
        add("memory", memory.pressure.status, memory.pressure.label)
        if let info = battery.snapshot {
            let batteryStatus = info.status(policy: quickActions.policy)
            add("battery", batteryStatus, batteryStatus == .critical ? "Battery charge critically low" : "Battery needs attention")
        } else if battery.internalBatteryPresent != false {
            add("battery", .unknown, "Battery reading unavailable")
        }
        let networkStatus = networkHealthStatus
        add("network", networkStatus, networkStatus == .unknown ? "Network status unavailable" : "No active network address detected")
        let updateMessage: String
        if case .available(let labels) = updates.state {
            updateMessage = UpdateNotice.message(labels, currentMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        } else { updateMessage = updates.summaryLabel }
        add("updates", updatesStatus, updateMessage)
        func rank(_ status: HealthStatus) -> Int {
            switch status { case .critical: 0; case .attention: 1; case .unknown: 2; case .good: 3 }
        }
        return values.enumerated().sorted {
            let a = rank($0.element.status), b = rank($1.element.status)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    var dashboardNotices: [HealthNotice] {
        let actionable = notices.filter { $0.status != .unknown }
        let unknown = notices.filter { $0.status == .unknown }
        guard !unknown.isEmpty else { return actionable }
        let text = unknown.count <= 2 ? unknown.map(\.message).joined(separator: " · ") : "\(unknown.count) checks pending or unavailable. Hover for details."
        return actionable + [.init(id: "unavailable", status: .unknown, message: text)]
    }
    var status: HealthStatus { HealthSummary.status(notices) }
    var hoverSummary: String {
        let title = quickActions.policy.appTitle
        if notices.isEmpty { return "\(title) — No action needed for monitored checks" }
        return title + "\n" + notices.map(\.message).joined(separator: "\n")
    }
    var menuBarImage: NSImage {
        let renderer = ImageRenderer(content: ComputerMark(color: status.color))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "IT Hub") ?? NSImage(size: NSSize(width: 22, height: 18))
        image.size = NSSize(width: 22, height: 18)
        image.isTemplate = false
        return image
    }
}
