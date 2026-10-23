import Foundation
import SystemConfiguration
import CoreWLAN

struct NetworkInfo {
    let connection: String
    let ipAddress: String
    let interface: String
    var wifiName: String? = nil
}

enum NetworkService {

    static func current() -> NetworkInfo {
        guard
            let store = SCDynamicStoreCreate(
                nil,
                "ITHub" as CFString,
                nil,
                nil
            ),
            let primary = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/IPv4" as CFString
            ) as? [String: Any],
            let interface = primary["PrimaryInterface"] as? String
        else {
            return NetworkInfo(
                connection: "Disconnected",
                ipAddress: "Not available",
                interface: "—"
            )
        }

        let ipv4 = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Interface/\(interface)/IPv4" as CFString
        ) as? [String: Any]

        let addresses = ipv4?["Addresses"] as? [String]
        let ipAddress = addresses?.first ?? "Not available"

        // CoreWLAN can withhold interfaces before privacy authorization.
        // Determine the connection type through SystemConfiguration instead.
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let primaryInterface = interfaces.first {
            (SCNetworkInterfaceGetBSDName($0) as String?) == interface
        }
        let type = primaryInterface.flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
        let connection: String
        if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
            connection = "Wi-Fi"
        } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
            connection = "Ethernet"
        } else {
            connection = "Connected"
        }

        return NetworkInfo(
            connection: connection,
            ipAddress: ipAddress,
            interface: interface,
            wifiName: CWWiFiClient.shared().interfaces()?.first(where: { $0.interfaceName == interface })?.ssid()
        )
    }
}

nonisolated enum NetworkServiceKind: Sendable { case wifi, ethernet, thunderbolt, phone, other }

nonisolated struct NetworkServiceInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let addresses: [String]
    let isWiFi: Bool
    let ssid: String?
    let primary: Bool
    let enabled: Bool
    let stateReadable: Bool
    let kind: NetworkServiceKind

    var isConnected: Bool { enabled && stateReadable && !addresses.isEmpty }
    var connectionText: String {
        if !enabled { return "Disabled" }
        if !stateReadable { return "Status unavailable" }
        return addresses.isEmpty ? "Not connected" : "Connected"
    }
    var status: String { primary && isConnected ? "\(connectionText) · Primary" : connectionText }
    var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .thunderbolt: "bolt.horizontal"
        case .phone: "iphone"
        case .other: "network"
        }
    }
    /// IPv4 first; the dashboard shows a single address.
    var primaryAddress: String? { addresses.first { !$0.contains(":") } ?? addresses.first }
}

extension NetworkService {
    static func services() -> [NetworkServiceInfo]? {
        guard let prefs = SCPreferencesCreate(nil, "ITHub" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService],
              let store = SCDynamicStoreCreate(nil, "ITHubServices" as CFString, nil, nil)
        else { return nil }
        let order = SCNetworkSetGetServiceOrder(set) as? [String] ?? []
        func value(_ key: String) -> [String: Any]? {
            SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        }
        let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/.*" as CFString) as? [String]
        let primaryIDs = [value("State:/Network/Global/IPv4")?["PrimaryService"] as? String,
                          value("State:/Network/Global/IPv6")?["PrimaryService"] as? String].compactMap { $0 }
        return services.compactMap { service -> NetworkServiceInfo? in
            guard let id = SCNetworkServiceGetServiceID(service) as String? else { return nil }
            let iface = SCNetworkServiceGetInterface(service)
            let bsd = iface.flatMap { SCNetworkInterfaceGetBSDName($0) as String? }
            let type = iface.flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
            let wifi = type == (kSCNetworkInterfaceTypeIEEE80211 as String)
            let addresses = ["IPv4", "IPv6"].flatMap { family -> [String] in
                let values = value("State:/Network/Service/\(id)/\(family)")
                return values?["Addresses"] as? [String] ?? []
            }.filter { $0 != "0.0.0.0" && $0 != "::" && !$0.hasPrefix("fe80:") && !$0.hasPrefix("169.254.") }
            let ssid = wifi ? CWWiFiClient.shared().interfaces()?.first(where: { $0.interfaceName == bsd })?.ssid() : nil
            let readableSSID = ssid.flatMap { $0.isEmpty || $0 == "<redacted>" || $0 == "<SSID Redacted>" ? nil : $0 }
            let name = SCNetworkServiceGetName(service) as String? ?? "Network service"
            let lower = name.lowercased()
            let kind: NetworkServiceKind
            if wifi { kind = .wifi }
            else if lower.contains("iphone") || lower.contains("ipad") { kind = .phone }   // tethering shows up as "Ethernet"
            else if lower.contains("thunderbolt") { kind = .thunderbolt }
            else if type == (kSCNetworkInterfaceTypeEthernet as String) { kind = .ethernet }
            else { kind = .other }
            return NetworkServiceInfo(id: id, name: name, addresses: addresses, isWiFi: wifi, ssid: readableSSID, primary: primaryIDs.contains(id), enabled: SCNetworkServiceGetEnabled(service), stateReadable: keys != nil, kind: kind)
        }.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max
            let b = order.firstIndex(of: $1.id) ?? Int.max
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
        }
    }
}

nonisolated enum NetworkHealth {
    static func status(_ services: [NetworkServiceInfo]?) -> HealthStatus {
        guard let services else { return .unknown }
        if services.contains(where: { $0.isConnected }) { return .good }
        if services.contains(where: { !$0.stateReadable }) { return .unknown }
        return .attention
    }
}
