import SwiftUI

struct MemoryTile: View {
    @ObservedObject var memory: MemoryService
    var body: some View {
        DashboardCard(title: "Memory", icon: "memorychip", status: memory.pressure.status, statusLabel: memory.pressure.label) {
            HStack {
                Text(memory.pressure.label).font(.caption.weight(.medium))
                Spacer()
                Text("\(MemoryService.bytes(memory.physicalMemory)) RAM").font(.caption).foregroundStyle(.secondary)
            }
            Text(memory.usedMemory.map { "Used (estimate): \(MemoryService.bytes($0)) of \(MemoryService.bytes(memory.physicalMemory))" } ?? "Memory usage unavailable")
                .font(.caption).foregroundStyle(.secondary)
                .help("Estimate: non-purgeable internal memory + wired memory + compressed memory. May differ from Activity Monitor.")
            HStack {
                Text(memory.swapUsed.map { "Swap used: \(MemoryService.bytes($0))" } ?? "Swap unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Activity Monitor") {
                    WindowPresentation.openApplication(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }.buttonStyle(.plain).foregroundStyle(.blue).font(.caption)
            }
        }
    }
}
