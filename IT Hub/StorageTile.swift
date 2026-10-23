import SwiftUI

struct StorageTile: View {
    let snapshot: StorageSnapshot?
    let checking: Bool
    let policy: HealthPolicy
    var body: some View {
        DashboardCard(title: "Storage", icon: "internaldrive", status: snapshot?.status(policy: policy) ?? .unknown, statusLabel: snapshot.map { "\(StorageSnapshot.bytes($0.available)) free" } ?? "Storage unavailable") {
            if let disk = snapshot {
                HStack(alignment: .firstTextBaseline) {
                    Text(disk.name)
                    Spacer(minLength: 8)
                    Text("\(StorageSnapshot.bytes(disk.available)) free")
                }.font(.caption).foregroundStyle(.secondary)
                StorageBar(snapshot: disk, policy: policy)
                Text("\(StorageSnapshot.bytes(disk.used)) of \(StorageSnapshot.bytes(disk.capacity)) used")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(checking ? "Checking storage…" : "Storage unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
