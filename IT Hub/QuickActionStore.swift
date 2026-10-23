import AppKit
import Combine
import Darwin

@MainActor final class QuickActionStore: ObservableObject {
    @Published private(set) var groups: [QuickActionGroup] = []
    @Published private(set) var policy: HealthPolicy = .default
    @Published private(set) var sourceDescription = ""
    @Published private(set) var runningScript: String?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadScheduled = false
    nonisolated private static let scriptTimeout: TimeInterval = 60
    private static let reloadDebounce: TimeInterval = 0.5

    private var preferenceObserver: AnyCancellable?
    init() {
        reload()
        // Managed preferences arrive through the defaults system; a profile install or removal posts this.
        preferenceObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.scheduleReload() }
    }

    deinit { watchers.forEach { $0.cancel() } }

    /// Re-arms the watchers on every reload: editors that replace the file leave a stale descriptor,
    /// and in-place rewrites (cp, MDM) never touch the directory entry, so both paths are watched.
    func reload() {
        groups = QuickActionConfig.load()
        policy = QuickActionConfig.loadPolicy()
        sourceDescription = QuickActionConfig.activeSourceDescription()
        watchConfiguration()
    }

    func perform(_ action: QuickAction) {
        switch action.kind {
        case .info: return
        case .link(let url): NSWorkspace.shared.open(url)
        case .app(let bundleID, let name): openApplication(bundleID: bundleID, name: name, title: action.title)
        case .script(let command, let showOutput): runScript(command, showOutput: showOutput, title: action.title)
        }
    }

    private func openApplication(bundleID: String?, name: String?, title: String) {
        let byID = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        guard let url = byID ?? name.flatMap(Self.applicationURL(named:)) else {
            Self.alert(title, "\(name ?? bundleID ?? "The app") is not installed on this Mac.")
            return
        }
        WindowPresentation.openApplication(url)
    }

    private func runScript(_ command: String, showOutput: Bool, title: String) {
        guard runningScript == nil else { return }
        runningScript = title
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ReadOnlyCommand.run("/bin/zsh", ["-c", command], timeout: Self.scriptTimeout)
            }.value
            runningScript = nil
            let failed = result.code != 0
            guard showOutput || failed else { return }
            let note = result.code == -2 ? "Timed out after \(Int(Self.scriptTimeout)) seconds.\n" : failed ? "Exit code \(result.code).\n" : ""
            Self.alert(title, note + result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func applicationURL(named name: String) -> URL? {
        let directories = FileManager.default.urls(for: .applicationDirectory, in: [.userDomainMask, .localDomainMask, .systemDomainMask])
        return directories.map { $0.appendingPathComponent("\(name).app") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text.isEmpty ? "No output." : text
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func watchConfiguration() {
        watchers.forEach { $0.cancel() }
        watchers = []
        let directories = QuickActionConfig.watchedDirectories()
        directories.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        let files = directories.map { $0.appendingPathComponent(QuickActionConfig.fileName) }
        for path in directories + files {
            let descriptor = Darwin.open(path.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { Darwin.close(descriptor) }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDebounce) { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }
}
