import SwiftUI
import Combine

@MainActor struct DashboardView: View {
    @ObservedObject var health: DeviceHealthModel
    @StateObject private var hardware = HardwareService()
    @StateObject private var internet = InternetService()
    private var uptime: UptimeService { health.uptime }
    private var memory: MemoryService { health.memory }
    private var security: SecurityService { health.security }
    private var storage: StorageService { health.storage }
    private var battery: BatteryService { health.battery }
    private var updates: UpdateService { health.updates }
    private var networkModel: NetworkModel { health.networkModel }
    private var policy: HealthPolicy { health.quickActions.policy }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) { ComputerMark(); Text(policy.appTitle).font(.headline) }
                    Text(policy.appSubtitle).font(.title2.bold())
                }
                Spacer()
                Text("v\(Self.appVersion)").font(.caption).foregroundStyle(.secondary)
            }
            if !health.notices.isEmpty {
                DashboardCard(title: "Needs attention", icon: "info.circle", status: health.status, statusLabel: health.hoverSummary) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(health.dashboardNotices) { notice in
                            HStack(alignment: .top, spacing: 8) {
                                StatusIndicator(status: notice.status, label: notice.message)
                                Text(notice.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.help(health.hoverSummary)
            }
            HStack(alignment: .top, spacing: 12) {
                summary("macOS", "desktopcomputer", .good, "Version read successfully; update status is separate") {
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                }
                summary("FileVault", "shield", security.state.status, security.state.label) {
                    Text(security.state.label)
                    if security.state == .unknown { settings("Open Settings", "com.apple.preference.security?FileVault") }
                }
                summary("Uptime", "clock", health.uptimeStatus, health.uptimeLabel) {
                    Text(uptime.detail)
                    if health.uptimeStatus == .attention { Text("A restart may speed up your Mac.").foregroundStyle(.orange) }
                }
                summary("Battery", battery.snapshot?.icon ?? "battery.100percent", battery.snapshot?.status(policy: health.quickActions.policy) ?? .unknown, battery.snapshot?.headline ?? "No reading") {
                    Text(battery.snapshot?.headline ?? "Not available")
                    Text(battery.snapshot?.cycleCount.map { "Cycle count: \($0)" } ?? "Cycle count unavailable")
                    if let health = battery.snapshot?.healthPercent {
                        Text("Capacity (estimate): \(health)%")
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    DeviceSupportCard(hardware: hardware, ram: MemoryService.bytes(memory.physicalMemory), makeReport: { supportReport })
                    StorageTile(snapshot: storage.snapshot, checking: storage.checking, policy: health.quickActions.policy)
                    MemoryTile(memory: memory)
                }.frame(width: 334)
                VStack(alignment: .leading, spacing: 12) {
                    NetworkServicesView(model: networkModel, internet: internet, policy: policy)
                    SoftwareUpdateCard(updates: updates, status: health.updatesStatus)
                }.frame(width: 334)
            }
            QuickActionsView(store: health.quickActions)
            Divider()
            HStack {
                Text("Device data refreshes every minute · Settings: \(health.quickActions.sourceDescription)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if policy.allowQuit {
                    Button("Quit \(policy.appTitle)") { NSApplication.shared.terminate(nil) }.font(.caption).buttonStyle(.plain)
                }
            }
        }
        .padding(20).frame(width: 720)
        .background(DashboardWindowReader())
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { health.start() }
        .task { await hardware.refresh() }
    }
    /// MARKETING_VERSION from the Xcode project, so the version is set in one place.
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private var supportReport: String {
        let unavailable = "Unavailable"
        let h = hardware.snapshot
        var lines = [
            "\(policy.appTitle) v\(Self.appVersion) — Support details",
            "Captured: \(Date().formatted(date: .abbreviated, time: .standard))",
            "Device: \(h?.deviceName ?? unavailable)",
            "Model: \(h?.model ?? unavailable)",
            "Model identifier: \(h?.identifier ?? unavailable)",
            "Chip: \(h?.chip ?? unavailable)",
            "RAM: \(MemoryService.bytes(memory.physicalMemory))",
            "Serial: \(h?.serial ?? unavailable)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "FileVault: \(security.state.label)",
            "Uptime: \(uptime.detail)",
            "Battery: \(battery.snapshot?.headline ?? unavailable)",
            "Battery cycles: \(battery.snapshot?.cycleCount.map(String.init) ?? unavailable)",
            "Battery capacity (estimate): \(battery.snapshot?.healthPercent.map { "\($0)%" } ?? unavailable)"
        ]
        if let disk = storage.snapshot {
            lines.append("Storage: \(StorageSnapshot.bytes(disk.used)) used, \(StorageSnapshot.bytes(disk.available)) free of \(StorageSnapshot.bytes(disk.capacity))")
        } else { lines.append("Storage: Unavailable") }
        lines += [
            "Memory used (estimate): \(memory.usedMemory.map(MemoryService.bytes) ?? unavailable) of \(MemoryService.bytes(memory.physicalMemory))",
            "Memory pressure: \(memory.pressure.label)",
            "Swap used: \(memory.swapUsed.map(MemoryService.bytes) ?? unavailable)",
            "Internet reachability: \(SpeedMath.reachabilityLabel(internet.reachable))",
            "Speed test: \(internet.speedLabel)",
            "Network services (address configured; internet access not verified):"
        ]
        if let services = networkModel.services {
            for service in services {
                lines.append("- \(service.name): \(service.status)")
                if service.isWiFi { lines.append("  Wi-Fi name: \(service.ssid ?? unavailable)") }
                if !service.addresses.isEmpty { lines.append("  IP: \(service.addresses.joined(separator: ", "))") }
            }
        } else { lines.append("Unavailable") }
        lines.append("Software Update: \(updates.summaryLabel)")
        if case .available(let names) = updates.state { lines += names.map { "- " + $0 } }
        lines.append("Update check: \(updates.checkedAt?.formatted(date: .abbreviated, time: .standard) ?? "Not checked")")
        if let reason = updates.failureReason { lines.append("Check note: " + reason) }
        return lines.joined(separator: "\n")
    }
    private func summary<Content: View>(_ title: String, _ icon: String, _ status: HealthStatus, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        DashboardCard(title: title, icon: icon, status: status, statusLabel: label, minimumContentHeight: 92) {
            content().font(.caption).foregroundStyle(.secondary)
        }
    }
    private func settings(_ title: String, _ target: String) -> some View {
        Button(title) {
            WindowPresentation.openSettings(target)
        }.buttonStyle(.plain).foregroundStyle(.blue)
    }
}

