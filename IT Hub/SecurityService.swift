import Foundation
import Combine

nonisolated enum FileVaultState: Equatable, Sendable {
    case checking, enabled, disabled, transitioning, unknown
    static func parse(_ output: String, exitCode: Int32) -> Self {
        guard exitCode == 0 else { return .unknown }
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "FileVault is On." { return .enabled }
        if value == "FileVault is Off." { return .disabled }
        if value.localizedCaseInsensitiveContains("in progress") { return .transitioning }
        return .unknown
    }
    var label: String {
        switch self {
        case .checking: "Checking FileVault…"
        case .enabled: "FileVault is on"
        case .disabled: "FileVault is off"
        case .transitioning: "FileVault change in progress"
        case .unknown: "FileVault status unavailable"
        }
    }
    var status: HealthStatus {
        switch self {
        case .enabled: .good
        case .disabled: .critical
        case .transitioning: .attention
        case .checking, .unknown: .unknown
        }
    }
}

@MainActor final class SecurityService: ObservableObject {
    @Published private(set) var state: FileVaultState = .checking
    func refresh() async {
        #if ITHUB_SANDBOX
        // fdesetup can return a misleading Off result in this sandboxed target.
        // A trusted external service is required before reporting a state.
        state = .unknown
        return
        #else
        // Keep the last measured state visible until the new reading completes.
        state = await Task.detached(priority: .utility) {
            let result = ReadOnlyCommand.run("/usr/bin/fdesetup", ["status"], timeout: 10)
            return FileVaultState.parse(result.output, exitCode: result.code)
        }.value
        #endif
    }
}
