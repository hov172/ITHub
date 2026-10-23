import SwiftUI

struct SoftwareUpdateCard: View {
    @ObservedObject var updates: UpdateService
    let status: HealthStatus
    var body: some View {
        DashboardCard(title: "Software Update", icon: "arrow.down.circle", status: status, statusLabel: updates.summaryLabel) {
            Text(updates.summaryLabel).font(.caption.weight(.medium))
            if updates.isChecking && updates.state != .checking { Text("Checking for updates…").font(.caption).foregroundStyle(.secondary) }
            if case .available(let names) = updates.state {
                Text(names.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = updates.failureReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy check details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(updates.diagnosticText, forType: .string)
                }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
            }
            if let date = updates.checkedAt {
                Text("Last check: \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Check now") { Task { await updates.refresh() } }.disabled(updates.isChecking)
                Spacer()
                Button("Open Settings") {
                    WindowPresentation.openSettings("com.apple.Software-Update-Settings.extension")
                }
            }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
        }
    }
}
