import Foundation
import Combine

nonisolated struct StorageSnapshot: Sendable {
    let capacity: Int64
    let available: Int64
    let name: String
    var used: Int64 { capacity - available }
    var fraction: Double { Double(used) / Double(capacity) }
    var status: HealthStatus { status(policy: .default) }
    func status(policy: HealthPolicy) -> HealthStatus {
        let free = Double(available)
        if policy.storageCriticalGB > 0, free < policy.storageCriticalGB * 1e9 { return .critical }
        if policy.storageWarningGB > 0, free < policy.storageWarningGB * 1e9 { return .attention }
        return .good
    }
    static func validated(capacity: Int64, available: Int64, name: String) -> Self? {
        guard capacity > 0, available >= 0, available <= capacity else { return nil }
        return Self(capacity: capacity, available: available, name: name)
    }
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}

@MainActor final class StorageService: ObservableObject {
    @Published private(set) var snapshot: StorageSnapshot?
    @Published private(set) var checking = true
    func refresh() async {
        checking = true
        snapshot = await Task.detached(priority: .utility) {
            do {
                // The writable Data volume contains user data on modern macOS.
                let url = URL(fileURLWithPath: "/System/Volumes/Data")
                let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey])
                guard let total = values.volumeTotalCapacity,
                      let free = values.volumeAvailableCapacity else { return Optional<StorageSnapshot>.none }
                return StorageSnapshot.validated(capacity: Int64(total), available: Int64(free), name: values.volumeName ?? "Startup disk")
            } catch { return nil }
        }.value
        checking = false
    }
}
