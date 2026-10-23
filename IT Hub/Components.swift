import SwiftUI

nonisolated enum HealthStatus: Sendable {
    case good, attention, critical, unknown
    var color: Color {
        switch self { case .good: .green; case .attention: .orange; case .critical: .red; case .unknown: .secondary }
    }
    var symbol: String {
        switch self { case .good: "checkmark.circle.fill"; case .attention: "exclamationmark.circle.fill"; case .critical: "exclamationmark.octagon.fill"; case .unknown: "questionmark.circle" }
    }
}
struct StatusIndicator: View {
    let status: HealthStatus
    let label: String
    var body: some View {
        Image(systemName: status.symbol).foregroundStyle(status.color).accessibilityLabel(label).help(label)
    }
}
struct StorageBar: View {
    let snapshot: StorageSnapshot
    var policy: HealthPolicy = .default
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(snapshot.status(policy: policy).color)
                    .frame(width: geometry.size.width * min(1, max(0, snapshot.fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage used")
        .accessibilityValue("\(Int(snapshot.fraction * 100)) percent")
    }
}
