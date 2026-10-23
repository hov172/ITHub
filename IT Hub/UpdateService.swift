import Foundation
import Combine

nonisolated enum UpdateState: Equatable, Sendable {
    case notChecked, checking, current, available([String]), unavailable
    static func parse(_ result: CommandResult) -> Self {
        guard result.code == 0 else { return .unavailable }
        let lines = result.output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if result.output.localizedCaseInsensitiveContains("error") || result.output.localizedCaseInsensitiveContains("failed") { return .unavailable }
        let labels = lines.compactMap { line -> String? in
            let cleaned = line.hasPrefix("*") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
            guard cleaned.hasPrefix("Label:") else { return nil }
            let label = String(cleaned.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? nil : label
        }
        if !labels.isEmpty { return .available(labels) }
        if lines.contains(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: "* ")).lowercased() == "no new software available." }) { return .current }
        return .unavailable
    }
    var status: HealthStatus {
        switch self { case .current: .good; case .available: .attention; default: .unknown }
    }
    var label: String {
        switch self {
        case .notChecked: "Not checked"
        case .checking: "Checking for updates…"
        case .current: "No updates available"
        case .available: "Update or upgrade available"
        case .unavailable: "Unable to check"
        }
    }
}
nonisolated enum UpdateDiagnostic {
    static func reason(_ result: CommandResult) -> String {
        if result.code == -2 { return "The update scan timed out. Try again or check in System Settings." }
        if result.code == -1 { return "The update checker could not start or read its result." }
        if result.code != 0 { return "macOS update checker exited with code \(result.code)." }
        return "macOS returned a result the app could not verify. Open Settings to confirm."
    }
}

nonisolated enum UpdateFreshness {
    static func status(_ state: UpdateState, checkedAt: Date?, now: Date = Date()) -> HealthStatus {
        if state == .current {
            guard let checkedAt else { return .unknown }
            let age = now.timeIntervalSince(checkedAt)
            return age >= 0 && age <= 3600 ? .good : .unknown
        }
        return state.status
    }
}

@MainActor final class UpdateService: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var state: UpdateState = .notChecked
    @Published private(set) var checkedAt: Date?
    @Published private(set) var failureReason: String?
    @Published private(set) var diagnosticText = ""
    var healthStatus: HealthStatus { UpdateFreshness.status(state, checkedAt: checkedAt) }
    var summaryLabel: String {
        state == .current && healthStatus == .unknown ? "Software update check is out of date" : state.label
    }
    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        #if ITHUB_SANDBOX
        failureReason = "This is the sandboxed build. Run the IT Hub Direct Read scheme for a live check."
        diagnosticText = failureReason ?? ""
        checkedAt = Date()
        state = .unavailable
        #else
        failureReason = nil
        diagnosticText = ""
        if state == .notChecked { state = .checking }
        let result = await Task.detached(priority: .utility) {
            ReadOnlyCommand.run("/usr/sbin/softwareupdate", ["--list", "--product-types", "macOS"], timeout: 180)
        }.value
        state = .parse(result)
        if state == .unavailable {
            failureReason = UpdateDiagnostic.reason(result)
            diagnosticText = "Exit code: \(result.code)\n" + String(result.output.suffix(6000))
        }
        checkedAt = Date()
        #endif
    }
}
