import Foundation
import Combine
import Dispatch
import Darwin
import AppKit

nonisolated enum MemoryPressure: Equatable, Sendable {
    case unknown, normal, warning, critical
    // The sysctl exports dispatch flags (1/2/4), not XNU's internal 0/1/2/3 levels.
    static func fromFlags(_ flags: UInt) -> Self {
        switch flags {
        case DispatchSource.MemoryPressureEvent.normal.rawValue: .normal
        case DispatchSource.MemoryPressureEvent.warning.rawValue: .warning
        case DispatchSource.MemoryPressureEvent.critical.rawValue: .critical
        default: .unknown
        }
    }
    static func fromEvent(_ flags: DispatchSource.MemoryPressureEvent) -> Self {
        if flags.contains(.critical) { return .critical }
        if flags.contains(.warning) { return .warning }
        if flags.contains(.normal) { return .normal }
        return .unknown
    }
    var status: HealthStatus {
        switch self { case .normal: .good; case .warning: .attention; case .critical: .critical; case .unknown: .unknown }
    }
    var label: String {
        switch self { case .normal: "Normal pressure"; case .warning: "Elevated pressure"; case .critical: "Critical pressure"; case .unknown: "Pressure unavailable" }
    }
}

nonisolated enum MemoryUsage {
    static func usedBytes(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64, pageSize: UInt64, total: UInt64) -> UInt64? {
        guard pageSize > 0, total > 0 else { return nil }
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let (sum, overflow1) = app.addingReportingOverflow(wiredPages)
        let (pages, overflow2) = sum.addingReportingOverflow(compressedPages)
        let (bytes, overflow3) = pages.multipliedReportingOverflow(by: pageSize)
        guard !overflow1, !overflow2, !overflow3 else { return nil }
        return min(bytes, total)
    }
    static func read(total: UInt64) -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return usedBytes(internalPages: UInt64(statistics.internal_page_count), purgeablePages: UInt64(statistics.purgeable_count), wiredPages: UInt64(statistics.wire_count), compressedPages: UInt64(statistics.compressor_page_count), pageSize: UInt64(pageSize), total: total)
    }
}

@MainActor final class MemoryService: ObservableObject {
    @Published private(set) var pressure: MemoryPressure = .unknown
    @Published private(set) var swapUsed: UInt64?
    @Published private(set) var usedMemory: UInt64?
    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    private var source: (any DispatchSourceMemoryPressure)?
    private var lastEventPressure: MemoryPressure?
    private var timer: AnyCancellable?
    private var wake: AnyCancellable?
    init() {
        let monitor = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source = monitor
        monitor.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                self.pressure = MemoryPressure.fromEvent(source.data)
                self.lastEventPressure = self.pressure
                self.refreshSwap()
            }
        }
        monitor.activate()
        refresh()
        timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pressure = .unknown
                self?.lastEventPressure = nil
                self?.refresh()
            }
        }
    }
    deinit { source?.cancel() }
    func refresh() {
        var flags: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        // Best-effort startup/current state; this key is not a guaranteed public API.
        // On failure keep unknown, or the last real dispatch notification's state.
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &flags, &size, nil, 0) == 0,
           size == MemoryLayout<UInt32>.size {
            let current = MemoryPressure.fromFlags(UInt(flags))
            pressure = current == .unknown ? lastEventPressure ?? .unknown : current
        } else {
            pressure = lastEventPressure ?? .unknown
        }
        refreshSwap()
    }
    private func refreshSwap() {
        usedMemory = MemoryUsage.read(total: physicalMemory)
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
              size == MemoryLayout<xsw_usage>.size else { swapUsed = nil; return }
        swapUsed = usage.xsu_used
    }
    static func bytes(_ value: UInt64) -> String {
        guard value != 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }
}
