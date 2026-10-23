import Foundation
import Combine

nonisolated struct HardwareSnapshot: Sendable {
    let deviceName: String
    let model: String?
    let identifier: String?
    let chip: String?
    let serial: String?
    static func parse(_ data: Data, deviceName: String) -> Self? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hardware = (json["SPHardwareDataType"] as? [[String: Any]])?.first else { return nil }
        func value(_ key: String) -> String? {
            guard let text = hardware[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
        return Self(deviceName: deviceName, model: value("machine_name"), identifier: value("machine_model"), chip: value("chip_type") ?? value("cpu_type"), serial: value("serial_number"))
    }
}
@MainActor final class HardwareService: ObservableObject {
    @Published private(set) var snapshot: HardwareSnapshot?
    @Published private(set) var checking = true
    func refresh() async {
        checking = true
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        snapshot = await Task.detached(priority: .utility) {
            let result = ReadOnlyCommand.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json", "-detailLevel", "full"], timeout: 20)
            guard result.code == 0 else { return Optional<HardwareSnapshot>.none }
            return HardwareSnapshot.parse(Data(result.output.utf8), deviceName: name)
        }.value
        checking = false
    }
}
