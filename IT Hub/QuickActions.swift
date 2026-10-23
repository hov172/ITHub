import Foundation

// Quick Actions are driven by a TopMenu-compatible JSON document:
// {"functionIdentifier":"public.submenu","settings":{"title":"...","content":[...]}}
// Supported leaves: public.title (info text), public.link, public.open.application, public.script.
// Submenus become titled groups. Unknown identifiers and runtime {value} rows are skipped.

nonisolated enum QuickActionKind: Equatable, Sendable {
    case info(String)
    case link(URL)
    case app(bundleID: String?, name: String?)
    case script(command: String, showOutput: Bool)
    var defaultIcon: String {
        switch self { case .info: "info.circle"; case .link: "link"; case .app: "app"; case .script: "terminal" }
    }
}

nonisolated struct QuickAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: String
    let kind: QuickActionKind
}

nonisolated struct QuickActionGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let actions: [QuickAction]
}

/// Admin-tunable health rules, read from the root `settings.policy` object of menu.json.
nonisolated struct HealthPolicy: Equatable, Sendable {
    var fileVaultOff: HealthStatus = .critical
    /// Wi-Fi name the Services card compares against; empty disables the comparison.
    var expectedWiFiSSID: String = ""
    /// Days of uptime before the restart reminder; 0 disables it.
    var uptimeWarningDays: Double = UptimePolicy.defaultWarningDays
    /// Free-space thresholds in GB (decimal); 0 disables that tier.
    var storageWarningGB: Double = 20
    var storageCriticalGB: Double = 5
    /// Charge thresholds in percent while on battery, and the capacity-health floor; 0 disables that tier.
    var batteryWarningPercent: Double = 20
    var batteryCriticalPercent: Double = 10
    var batteryHealthWarningPercent: Double = 80
    /// Severity for available macOS updates (warning or ignore) and for no active network (warning, critical or ignore).
    var softwareUpdates: HealthStatus = .attention
    var networkOffline: HealthStatus = .attention
    /// Minutes between automatic softwareupdate scans.
    var updateScanMinutes: Double = 30
    /// Feature switches.
    var speedTestEnabled = true
    /// Seconds per speed-test phase (download, then upload); clamped to 2...20.
    var speedTestSeconds: Double = 5
    var wifiNameLookup = true
    /// Show the explanation window once at launch when permission is undecided; false leaves the
    /// request to the Services card button. MDM cannot pre-approve Location Services for an app.
    var locationPromptAtLaunch = true
    var allowQuit = true
    /// Branding shown in the dashboard header, hover text and support report.
    var appTitle = "IT Hub"
    var appSubtitle = "Device Health"
    static let `default` = HealthPolicy()
    static func parse(_ data: Data) -> HealthPolicy? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(root)
    }
    static func parse(_ root: [String: Any]) -> HealthPolicy {
        let policy = (root["settings"] as? [String: Any])?["policy"] as? [String: Any] ?? [:]
        var result = HealthPolicy()
        if let severity = severity(policy["fileVaultOff"]) { result.fileVaultOff = severity }
        result.expectedWiFiSSID = (policy["expectedWiFiSSID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        result.uptimeWarningDays = number(policy["uptimeWarningDays"]) ?? result.uptimeWarningDays
        result.storageWarningGB = number(policy["storageWarningGB"]) ?? result.storageWarningGB
        result.storageCriticalGB = number(policy["storageCriticalGB"]) ?? result.storageCriticalGB
        result.batteryWarningPercent = number(policy["batteryWarningPercent"]) ?? result.batteryWarningPercent
        result.batteryCriticalPercent = number(policy["batteryCriticalPercent"]) ?? result.batteryCriticalPercent
        result.batteryHealthWarningPercent = number(policy["batteryHealthWarningPercent"]) ?? result.batteryHealthWarningPercent
        if let severity = severity(policy["softwareUpdates"]), severity != .critical { result.softwareUpdates = severity }
        if let severity = severity(policy["networkOffline"]) { result.networkOffline = severity }
        if let minutes = number(policy["updateScanMinutes"]), minutes >= 1 { result.updateScanMinutes = minutes }
        result.speedTestEnabled = policy["speedTestEnabled"] as? Bool ?? result.speedTestEnabled
        if let seconds = number(policy["speedTestSeconds"]) { result.speedTestSeconds = min(20, max(2, seconds)) }
        result.wifiNameLookup = policy["wifiNameLookup"] as? Bool ?? result.wifiNameLookup
        result.locationPromptAtLaunch = policy["locationPromptAtLaunch"] as? Bool ?? result.locationPromptAtLaunch
        result.allowQuit = policy["allowQuit"] as? Bool ?? result.allowQuit
        let branding = (root["settings"] as? [String: Any])?["branding"] as? [String: Any] ?? [:]
        result.appTitle = text(branding["title"]) ?? result.appTitle
        result.appSubtitle = text(branding["subtitle"]) ?? result.appSubtitle
        return result
    }
    static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }
    /// Finite, non-negative numbers only; anything else keeps the default.
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? Double, number.isFinite, number >= 0 else { return nil }
        return number
    }
    /// "critical" (red), "warning" (orange) or "ignore" (no notice). Unknown values keep the default.
    static func severity(_ value: Any?) -> HealthStatus? {
        switch (value as? String)?.lowercased() {
        case "critical": .critical
        case "warning", "attention": .attention
        case "ignore", "off", "none": .good
        default: nil
        }
    }
}

nonisolated enum QuickActionConfig {
    static let folderName = "IT Hub"
    static let fileName = "menu.json"

    /// Returns nil when the document is not a JSON object. `allowScripts` is false for
    /// files a non-admin user can edit, so a user-level override cannot inject commands.
    static func parse(_ data: Data, allowScripts: Bool) -> [QuickActionGroup]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(root, allowScripts: allowScripts)
    }
    static func parse(_ root: [String: Any], allowScripts: Bool) -> [QuickActionGroup] {
        let rootSettings = root["settings"] as? [String: Any] ?? [:]
        let rootTitle = rootSettings["title"] as? String ?? "Actions"
        let content = rootSettings["content"] as? [[String: Any]] ?? []
        var groups: [QuickActionGroup] = []
        var loose: [QuickAction] = []
        for (index, node) in content.enumerated() {
            let settings = node["settings"] as? [String: Any] ?? [:]
            if settings["hidden"] as? Bool == true { continue }
            if node["functionIdentifier"] as? String == "public.submenu" {
                let title = settings["title"] as? String ?? "Group \(index + 1)"
                let children = settings["content"] as? [[String: Any]] ?? []
                let actions = children.enumerated().compactMap { leaf("g\(index)-\($0.offset)", $0.element, allowScripts) }
                if !actions.isEmpty { groups.append(.init(id: "g\(index)", title: title, actions: actions)) }
            } else if let action = leaf("root-\(index)", node, allowScripts) {
                loose.append(action)
            }
        }
        if !loose.isEmpty { groups.append(.init(id: "root", title: rootTitle, actions: loose)) }
        return groups
    }

    private static func leaf(_ id: String, _ node: [String: Any], _ allowScripts: Bool) -> QuickAction? {
        let settings = node["settings"] as? [String: Any] ?? [:]
        if settings["hidden"] as? Bool == true { return nil }
        let kind: QuickActionKind
        var title = settings["title"] as? String
        switch node["functionIdentifier"] as? String {
        case "public.title":
            guard let template = settings["template"] as? String, !template.contains("{value}") else { return nil }
            kind = .info(template); title = template
        case "public.link":
            guard let text = settings["url"] as? String, let url = URL(string: text), url.scheme != nil else { return nil }
            kind = .link(url); title = title ?? text
        case "public.open.application":
            let bundleID = settings["bundleIdentifier"] as? String
            let name = settings["name"] as? String
            guard bundleID != nil || name != nil else { return nil }
            kind = .app(bundleID: bundleID, name: name); title = title ?? name
        case "public.script":
            guard allowScripts, let command = settings["command"] as? String, !command.isEmpty else { return nil }
            kind = .script(command: command, showOutput: settings["showOutput"] as? Bool ?? true)
        default:
            return nil
        }
        guard let title, !title.isEmpty else { return nil }
        return .init(id: id, title: title, icon: settings["icon"] as? String ?? kind.defaultIcon, kind: kind)
    }

    /// Managed (/Library) config wins, then the user's own file, then the bundled default.
    static func sources() -> [(url: URL, trusted: Bool)] {
        var list: [(URL, Bool)] = []
        if let managed = support(.localDomainMask) { list.append((managed, true)) }
        if let user = support(.userDomainMask) { list.append((user, false)) }
        if let bundled = Bundle.main.url(forResource: "menu", withExtension: "json") { list.append((bundled, true)) }
        return list
    }

    /// The preference domain an MDM configuration profile targets. The profile carries the same
    /// `branding`, `policy` and `content` keys as menu.json, under a `settings` dictionary or at top level.
    static let preferenceDomain = "edu.slc.ithub"
    static let preferenceKeys = ["settings", "branding", "policy", "content", "title"]

    /// A managed profile wins over every file. Values are trusted (scripts allowed) only when
    /// macOS reports them as forced, which is how profile-delivered preferences arrive; a plain
    /// `defaults write` by the user is honoured but may not add commands.
    static func preferenceDocument() -> (root: [String: Any], trusted: Bool)? {
        let domain = preferenceDomain as CFString
        var root: [String: Any] = [:]
        var forced = true
        for key in preferenceKeys {
            guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { continue }
            root[key] = value
            if !CFPreferencesAppValueIsForced(key as CFString, domain) { forced = false }
        }
        guard !root.isEmpty else { return nil }
        if let settings = root["settings"] as? [String: Any] { return (["settings": settings], forced) }
        return (["settings": root], forced)
    }

    static func load() -> [QuickActionGroup] {
        if let preferences = preferenceDocument() { return parse(preferences.root, allowScripts: preferences.trusted) }
        for source in sources() {
            guard let data = try? Data(contentsOf: source.url) else { continue }
            if let groups = parse(data, allowScripts: source.trusted) { return groups }
        }
        return []
    }

    static func loadPolicy() -> HealthPolicy {
        if let preferences = preferenceDocument() { return HealthPolicy.parse(preferences.root) }
        for source in sources() {
            guard let data = try? Data(contentsOf: source.url), let policy = HealthPolicy.parse(data) else { continue }
            return policy
        }
        return .default
    }

    /// Where the active configuration comes from, for the dashboard footer.
    static func activeSourceDescription() -> String {
        if preferenceDocument() != nil { return "Configuration profile" }
        for source in sources() where FileManager.default.fileExists(atPath: source.url.path) {
            if source.url.path.hasPrefix(Bundle.main.bundlePath) { return "Built-in defaults" }
            return source.url.path.hasPrefix("/Library") ? "Managed file" : "User file"
        }
        return "Built-in defaults"
    }

    static func watchedDirectories() -> [URL] {
        sources().filter { !$0.url.path.hasPrefix(Bundle.main.bundlePath) }.map { $0.url.deletingLastPathComponent() }
    }

    private static func support(_ domain: FileManager.SearchPathDomainMask) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: domain).first?
            .appendingPathComponent(folderName).appendingPathComponent(fileName)
    }
}
