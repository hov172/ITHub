import SwiftUI
import Combine

struct NetworkServicesView: View {
    @ObservedObject var model: NetworkModel
    @ObservedObject var internet: InternetService
    let policy: HealthPolicy
    private var expectedSSID: String { policy.expectedWiFiSSID }
    @StateObject private var selection = ServiceSelection()
    /// Keep active connections visible; expand to inspect inactive services.
    @StateObject private var disclosure = ServiceDisclosure()

    private var services: [NetworkServiceInfo] { model.services ?? [] }
    private var selected: NetworkServiceInfo? {
        services.first { $0.id == selection.id } ?? services.first { $0.primary } ?? services.first
    }
    private var connectedCount: Int { services.filter(\.isConnected).count }

    var body: some View {
        DashboardCard(title: "Services", icon: "network", status: internet.reachabilityStatus, statusLabel: "Internet: " + SpeedMath.reachabilityLabel(internet.reachable)) {
            HStack(spacing: 6) {
                Text("Internet: " + SpeedMath.reachabilityLabel(internet.reachable)).font(.caption.weight(.medium))
                if model.services != nil {
                    Text("· \(connectedCount) connected").font(.caption).foregroundStyle(.secondary)
                }
            }
            if policy.speedTestEnabled { speedTest }
            activeSummary
            if model.services == nil {
                note("Network services unavailable")
            } else if services.isEmpty {
                note("No configured services")
            } else {
                selector
                if disclosure.expanded { serviceList }
                if let service = selected { details(for: service) }
            }
        }
    }

    private var activeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(services.filter { $0.isConnected }) { service in
                HStack(alignment: .top) {
                    Image(systemName: service.symbol).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.isWiFi ? "Wi-Fi" : service.kind == .ethernet ? "Ethernet" : service.name).font(.caption.weight(.medium))
                        if service.isWiFi, policy.wifiNameLookup {
                            Text(service.ssid ?? "Wi-Fi name unavailable").font(.caption)
                            if let ssid = service.ssid, !expectedSSID.isEmpty {
                                Label(ssid == expectedSSID ? "Expected Wi-Fi" : "Different from expected Wi-Fi", systemImage: ssid == expectedSSID ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.caption2).foregroundStyle(ssid == expectedSSID ? Color.green : Color.orange)
                            } else if service.ssid == nil {
                                Text(model.permissionDescription).font(.caption2).foregroundStyle(.secondary)
                                Button(model.permissionActionTitle) { model.requestLocation() }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Text(service.primary ? "Primary" : "Secondary").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var speedTest: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speed test: " + internet.speedLabel).font(.caption)
                if let failure = internet.failure {
                    Text(failure).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if let at = internet.measuredAt {
                    Text("Cloudflare, \(at.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if internet.testing {
                ProgressView().controlSize(.small)
                Text(internet.phase).font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Run speed test") { internet.runSpeedTest(seconds: policy.speedTestSeconds) }.font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
            }
        }
        .help("Runs \(SpeedMath.formattedSeconds(policy.speedTestSeconds)) of download and \(SpeedMath.formattedSeconds(policy.speedTestSeconds)) of upload at full speed against speed.cloudflare.com")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Selector + list

    private var selector: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { disclosure.expanded.toggle() }
        } label: {
            HStack {
                Text("Service details").font(.subheadline)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(disclosure.expanded ? 180 : 0))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Services, \(selected?.name ?? "Select a service")")
        .accessibilityValue(disclosure.expanded ? "Expanded" : "Collapsed")
    }

    private var serviceList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(services) { service in row(service) }
            }
        }
        .frame(height: min(CGFloat(services.count) * 58, 210))
        .padding(4)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    private func row(_ service: NetworkServiceInfo) -> some View {
        let isSelected = service.id == selected?.id
        return Button {
            selection.id = service.id
            withAnimation(.easeInOut(duration: 0.15)) { disclosure.expanded = false }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: service.symbol).foregroundStyle(.blue).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.kind == .ethernet ? "Ethernet" : service.name).font(.subheadline)
                    Text(subtitle(service)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if service.isConnected {
                    Text(service.primary ? "Primary" : "Secondary").font(.caption2.weight(.medium)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ service: NetworkServiceInfo) -> String {
        if service.isWiFi, service.isConnected, let ssid = service.ssid { return "\(ssid) · Connected" }
        return service.connectionText
    }

    // MARK: Details for the selected service

    private func details(for service: NetworkServiceInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Active Wi-Fi details and its permission action appear once, in activeSummary.
            if !service.isWiFi {
                Text(service.kind == .ethernet ? "Ethernet" : service.name).font(.subheadline.bold())
            }
            if !service.isConnected {
                Text(service.connectionText).font(.caption).foregroundStyle(.secondary)
            }
            if let ip = service.primaryAddress {
                Divider().padding(.vertical, 2)
                HStack {
                    Text("IP address").foregroundStyle(.secondary)
                    Spacer()
                    Text(ip).textSelection(.enabled).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }.font(.caption)
            }
        }
        .padding(.horizontal, 2)
    }


}

@MainActor final class ServiceSelection: ObservableObject {
    @Published var id: String?
}

@MainActor final class ServiceDisclosure: ObservableObject {
    @Published var expanded = false
}
