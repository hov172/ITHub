import Foundation
import Combine
import IOKit
import IOKit.ps

nonisolated struct BatterySnapshot: Sendable {
    let percent: Int
    let isCharging: Bool
    let onACPower: Bool
    let minutesRemaining: Int?   // to empty (on battery) or to full (charging)
    let cycleCount: Int?
    let healthPercent: Int?      // maximum capacity vs. design capacity

    var status: HealthStatus { status(policy: .default) }
    func status(policy: HealthPolicy) -> HealthStatus {
        let charge = Double(percent)
        if !onACPower, policy.batteryCriticalPercent > 0, charge <= policy.batteryCriticalPercent { return .critical }
        // Apple recommends service once maximum capacity drops below 80%; admins may relax or disable this.
        if let health = healthPercent, policy.batteryHealthWarningPercent > 0, Double(health) < policy.batteryHealthWarningPercent { return .attention }
        // Cycle count is informational; Apple's rated limit varies by Mac model.
        if !onACPower, policy.batteryWarningPercent > 0, charge <= policy.batteryWarningPercent { return .attention }
        return .good
    }

    var icon: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var headline: String {
        if isCharging { return "\(percent)% · Charging" }
        if onACPower { return "\(percent)% · Plugged in" }
        return "\(percent)% · On battery"
    }

    /// Answers the two most common questions: "how long left?" and "why isn't it charging?"
    var chargeDetail: String? {
        if let minutes = minutesRemaining {
            let text = "\(minutes / 60)h \(minutes % 60)m"
            return isCharging ? "\(text) until full" : "\(text) remaining"
        }
        if onACPower && !isCharging {
            return percent >= 99 ? "Fully charged" : "Not charging — Optimized Charging may be holding it"
        }
        return nil
    }

    var healthDetail: String? {
        switch (healthPercent, cycleCount) {
        case let (h?, c?): return "Health \(h)% · \(c) cycles"
        case let (h?, nil): return "Health \(h)%"
        case let (nil, c?): return "\(c) charge cycles"
        default: return nil
        }
    }

    static func internalBatteryPresent() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var unknownSource = false
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { unknownSource = true; continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { return true }
        }
        return unknownSource ? nil : false
    }

    /// Returns nil on Macs without an internal battery (Mac mini, Studio, iMac…).
    static func read() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let timeKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = d[timeKey] as? Int    // -1 while macOS is still calculating
            let registry = registryProperties()

            guard current >= 0 else { continue }
            let percent = Int(min(100, Swift.max(0, Double(current) / Double(max) * 100)))
            return BatterySnapshot(
                percent: percent,
                isCharging: charging,
                onACPower: onAC,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil,
                cycleCount: registry?["CycleCount"] as? Int,
                healthPercent: healthPercent(from: registry)
            )
        }
        return nil
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    private static func healthPercent(from registry: [String: Any]?) -> Int? {
        guard let registry, let design = registry["DesignCapacity"] as? Int, design > 0 else { return nil }
        // Apple Silicon reports the real maximum under one of these keys; "MaxCapacity" is a
        // percentage there, but a raw mAh value on Intel Macs.
        let maxCapacity = (registry["NominalChargeCapacity"] as? Int)
            ?? (registry["AppleRawMaxCapacity"] as? Int)
            ?? ((registry["MaxCapacity"] as? Int).flatMap { $0 > 100 ? $0 : nil })
        guard let maxCapacity, maxCapacity > 0 else { return nil }
        return Swift.min(100, maxCapacity * 100 / design)
    }
}

@MainActor final class BatteryService: ObservableObject {
    /// nil means no internal battery or an unreadable snapshot; presence is tracked separately.
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var internalBatteryPresent: Bool?
    func refresh() async {
        let result = await Task.detached(priority: .utility) {
            (BatterySnapshot.read(), BatterySnapshot.internalBatteryPresent())
        }.value
        snapshot = result.0
        internalBatteryPresent = result.1
    }
}
