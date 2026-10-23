import Foundation


precondition(UpdateState.parse(.init(output: "No new software available.\n", code: 0)) == .current)
precondition(UpdateState.parse(.init(output: "No new software available.", code: 1)) == .unavailable)
precondition(UpdateState.parse(.init(output: "No new software available.\nError: scan failed", code: 0)) == .unavailable)
precondition(UpdateState.parse(.init(output: "Finding available software", code: 0)) == .unavailable)
precondition(UpdateState.parse(.init(output: "* Label: macOS Update-27.0.2\n", code: 0)) == .available(["macOS Update-27.0.2"]))
precondition(UpdateState.parse(.init(output: "* Label: macOS Update-27.0.2", code: -2)) == .unavailable)
precondition(FileVaultState.parse("FileVault is On.", exitCode: 0) == .enabled)
precondition(FileVaultState.parse("FileVault is On.", exitCode: 1) == .unknown)
precondition(FileVaultState.parse("FileVault is Off.", exitCode: 0) == .disabled)
precondition(FileVaultState.parse("Permission denied", exitCode: 0) == .unknown)
precondition(ReadOnlyCommand.run("/usr/bin/true", [], timeout: 1).code == 0)
precondition(ReadOnlyCommand.run("/bin/sleep", ["5"], timeout: 0.2).code == -2)
print("Passed 12 parser and bounded-command checks")
precondition(UptimePolicy.status(for: nil) == .unknown)
precondition(UptimePolicy.status(for: -1) == .unknown)
precondition(UptimePolicy.status(for: 14 * 86400 - 1) == .good)
precondition(UptimePolicy.status(for: 14 * 86400) == .attention)
precondition(UptimePolicy.status(for: 30 * 86400) == .attention)
let disk = StorageSnapshot.validated(capacity: 494_380_000_000, available: 196_200_000_000, name: "Test")!
precondition(disk.used == 298_180_000_000)
precondition(disk.status == .good)
precondition(abs(disk.fraction - 0.6031393) < 0.00001)
print("Passed 8 uptime-boundary and storage checks")
precondition(MemoryPressure.fromFlags(1) == .normal)
precondition(MemoryPressure.fromFlags(2) == .warning)
precondition(MemoryPressure.fromFlags(4) == .critical)
precondition(MemoryPressure.fromFlags(0) == .unknown)
precondition(MemoryPressure.fromFlags(3) == .unknown)
precondition(MemoryPressure.fromFlags(99) == .unknown)
precondition(MemoryPressure.fromEvent([.normal, .warning]) == .warning)
precondition(MemoryPressure.fromEvent([.warning, .critical]) == .critical)
precondition(MemoryPressure.fromEvent([]) == .unknown)
print("Passed 9 memory pressure mapping checks")
precondition(MemoryUsage.usedBytes(internalPages: 100, purgeablePages: 20, wiredPages: 30, compressedPages: 10, pageSize: 4096, total: 1_000_000) == 491_520)
precondition(MemoryUsage.usedBytes(internalPages: 10, purgeablePages: 20, wiredPages: 2, compressedPages: 1, pageSize: 4096, total: 1_000_000) == 12_288)
precondition(MemoryUsage.usedBytes(internalPages: 100, purgeablePages: 0, wiredPages: 30, compressedPages: 10, pageSize: 4096, total: 1000) == 1000)
precondition(MemoryUsage.usedBytes(internalPages: 1, purgeablePages: 0, wiredPages: 0, compressedPages: 0, pageSize: 0, total: 1000) == nil)
precondition(MemoryUsage.usedBytes(internalPages: UInt64.max, purgeablePages: 0, wiredPages: 1, compressedPages: 0, pageSize: 4096, total: 1000) == nil)
precondition(UpdateState.parse(.init(output: "* No new software available.", code: 0)) == .current)
precondition(UpdateState.parse(.init(output: "Label: macOS Example 27.1", code: 0)) == .available(["macOS Example 27.1"]))
precondition(UpdateState.parse(.init(output: "* Label: macOS Example 27.1\nError: scan failed", code: 0)) == .unavailable)
precondition(UpdateDiagnostic.reason(.init(output: "", code: -2)).contains("timed out"))
precondition(UpdateDiagnostic.reason(.init(output: "", code: 7)).contains("7"))
print("Passed 10 memory usage and update-diagnostic checks")
precondition(HealthSummary.status([]) == .good)
let missing = HealthNotice(id: "missing", status: .unknown, message: "Unavailable")
let warning = HealthNotice(id: "warning", status: .attention, message: "Action needed")
let critical = HealthNotice(id: "critical", status: .critical, message: "Critical")
precondition(HealthSummary.status([missing]) == .unknown)
precondition(HealthSummary.status([missing, warning]) == .attention)
precondition(HealthSummary.status([missing, critical]) == .critical)
precondition(HealthSummary.status([warning, critical, missing]) == .critical)
precondition(UpdateNotice.message(["macOS Sequoia 15.7-24G"], currentMajor: 15) == "macOS update available")
precondition(UpdateNotice.message(["macOS Tahoe 26.1-25B"], currentMajor: 15) == "macOS upgrade available")
precondition(UpdateNotice.message(["Unrecognized name"], currentMajor: 15) == "macOS update or upgrade available")
print("Passed 8 health-summary and update-name checks")

let checked = Date(timeIntervalSince1970: 10_000)
precondition(UpdateFreshness.status(.current, checkedAt: checked, now: checked.addingTimeInterval(3600)) == .good)
precondition(UpdateFreshness.status(.current, checkedAt: checked, now: checked.addingTimeInterval(3601)) == .unknown)
precondition(UpdateFreshness.status(.current, checkedAt: nil, now: checked) == .unknown)
precondition(UpdateFreshness.status(.current, checkedAt: checked, now: checked.addingTimeInterval(-1)) == .unknown)
precondition(UpdateFreshness.status(.available(["macOS Update"]), checkedAt: checked, now: checked.addingTimeInterval(7200)) == .attention)
precondition(NetworkHealth.status(nil) == .unknown)
precondition(NetworkHealth.status([]) == .attention)
let unreadable = NetworkServiceInfo(id: "test", name: "Wi-Fi", addresses: [], isWiFi: true, ssid: nil, primary: false, enabled: true, stateReadable: false, kind: .wifi)
precondition(NetworkHealth.status([unreadable]) == .unknown)
let connected = NetworkServiceInfo(id: "test2", name: "Ethernet", addresses: ["192.0.2.1"], isWiFi: false, ssid: nil, primary: true, enabled: true, stateReadable: true, kind: .ethernet)
precondition(NetworkHealth.status([unreadable, connected]) == .good)
print("Passed 9 freshness and network uncertainty checks")
let menu = """
{"functionIdentifier":"public.submenu","settings":{"title":"Root","content":[
 {"functionIdentifier":"public.submenu","settings":{"title":"Help","content":[
   {"functionIdentifier":"public.title","settings":{"template":"Call 555-0100"}},
   {"functionIdentifier":"public.title","settings":{"template":"OS: {value}"}},
   {"functionIdentifier":"public.link","settings":{"title":"Portal","url":"https://example.test/"}},
   {"functionIdentifier":"public.link","settings":{"title":"Bad","url":"not a url"}},
   {"functionIdentifier":"public.open.application","settings":{"title":"Safari","bundleIdentifier":"com.apple.Safari"}},
   {"functionIdentifier":"public.script","settings":{"title":"Flush DNS","command":"echo hi"}},
   {"functionIdentifier":"public.cloudflare.speed","settings":{"title":"Speed"}}
 ]}},
 {"functionIdentifier":"public.submenu","settings":{"title":"Empty","content":[{"functionIdentifier":"public.separator"}]}},
 {"functionIdentifier":"public.link","settings":{"url":"mailto:help@example.test"}}
]}}
""".data(using: .utf8)!
let trusted = QuickActionConfig.parse(menu, allowScripts: true)!
precondition(trusted.map(\.title) == ["Help", "Root"])
precondition(trusted[0].actions.map(\.title) == ["Call 555-0100", "Portal", "Safari", "Flush DNS"])
precondition(trusted[0].actions[0].kind == .info("Call 555-0100"))
precondition(trusted[0].actions[1].kind == .link(URL(string: "https://example.test/")!))
precondition(trusted[0].actions[2].kind == .app(bundleID: "com.apple.Safari", name: nil))
precondition(trusted[0].actions[3].kind == .script(command: "echo hi", showOutput: true))
precondition(trusted[1].actions[0].title == "mailto:help@example.test")
let untrusted = QuickActionConfig.parse(menu, allowScripts: false)!
precondition(untrusted[0].actions.map(\.title) == ["Call 555-0100", "Portal", "Safari"])
precondition(QuickActionConfig.parse("[1,2]".data(using: .utf8)!, allowScripts: true) == nil)
precondition(QuickActionConfig.parse("{}".data(using: .utf8)!, allowScripts: true) == [])
precondition(QuickActionConfig.sources().count >= 2 && QuickActionConfig.sources()[0].trusted && !QuickActionConfig.sources()[1].trusted)
print("Passed 11 quick-action configuration checks")

precondition(SpeedMath.megabitsPerSecond(bytes: 2_000_000, duration: 1) == 16)
precondition(SpeedMath.megabitsPerSecond(bytes: 1_000_000, duration: 0.5) == 16)
precondition(SpeedMath.megabitsPerSecond(bytes: 0, duration: 1) == nil)
precondition(SpeedMath.megabitsPerSecond(bytes: 10, duration: 0) == nil)
precondition(SpeedMath.label(download: nil, upload: nil) == "Not measured")
precondition(SpeedMath.label(download: 85.25, upload: nil) == "85.2 Mbps down")
precondition(SpeedMath.label(download: 85.25, upload: 12.04) == "85.2 Mbps down · 12.0 Mbps up")
precondition(SpeedMath.label(download: 85.25, upload: 12.04, latencyMs: 23.6) == "85.2 Mbps down · 12.0 Mbps up · 24 ms")
precondition(SpeedMath.aggregate(bytesAfterRamp: 12_500_000, elapsed: 5.5, rampUp: 0.5) == 20)
precondition(SpeedMath.aggregate(bytesAfterRamp: 0, elapsed: 5, rampUp: 0.5) == nil)
precondition(SpeedMath.aggregate(bytesAfterRamp: 100, elapsed: 0.5, rampUp: 0.5) == nil)
precondition(SpeedMath.trimmedMean([]) == nil)
precondition(SpeedMath.trimmedMean([10, 20, 30]) == 20)
precondition(SpeedMath.trimmedMean([1, 10, 10, 10, 10, 10, 10, 10, 10, 1000]) == 10)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"speedTestSeconds":60}}}"#.data(using: .utf8)!)?.speedTestSeconds == 20)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"speedTestSeconds":1}}}"#.data(using: .utf8)!)?.speedTestSeconds == 2)
precondition(HealthPolicy.parse("{}".data(using: .utf8)!)?.speedTestSeconds == 5)
precondition(SpeedMath.reachabilityLabel(nil) == "Checking…")
precondition(SpeedMath.reachabilityLabel(true) == "Online")
precondition(SpeedMath.reachabilityLabel(false) == "Offline")
print("Passed 20 speed-test and reachability checks")

let hiddenMenu = """
{"functionIdentifier":"public.submenu","settings":{"content":[
 {"functionIdentifier":"public.submenu","settings":{"title":"Shown","content":[
   {"functionIdentifier":"public.link","settings":{"title":"Keep","url":"https://a.test/"}},
   {"functionIdentifier":"public.link","settings":{"title":"Hide me","url":"https://b.test/","hidden":true}},
   {"functionIdentifier":"public.link","settings":{"title":"Not hidden","url":"https://c.test/","hidden":false}}
 ]}},
 {"functionIdentifier":"public.submenu","settings":{"title":"Hidden group","hidden":true,"content":[
   {"functionIdentifier":"public.link","settings":{"title":"Never","url":"https://d.test/"}}
 ]}}
]}}
""".data(using: .utf8)!
let visible = QuickActionConfig.parse(hiddenMenu, allowScripts: false)!
precondition(visible.map(\.title) == ["Shown"])
precondition(visible[0].actions.map(\.title) == ["Keep", "Not hidden"])
print("Passed 2 hidden-flag checks")

precondition(HealthPolicy.parse("{}".data(using: .utf8)!) == .default)
precondition(HealthPolicy.parse("[]".data(using: .utf8)!) == nil)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"fileVaultOff":"warning"}}}"#.data(using: .utf8)!)?.fileVaultOff == .attention)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"fileVaultOff":"IGNORE"}}}"#.data(using: .utf8)!)?.fileVaultOff == .good)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"fileVaultOff":"bogus"}}}"#.data(using: .utf8)!)?.fileVaultOff == .critical)
precondition(HealthPolicy.severity("critical") == .critical && HealthPolicy.severity(7) == nil)
print("Passed 6 health-policy checks")

precondition(HealthPolicy.parse("{}".data(using: .utf8)!)?.expectedWiFiSSID == "")
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"expectedWiFiSSID":"  Campus-Secure "}}}"#.data(using: .utf8)!)?.expectedWiFiSSID == "Campus-Secure")
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"expectedWiFiSSID":42}}}"#.data(using: .utf8)!)?.expectedWiFiSSID == "")
print("Passed 3 expected-Wi-Fi policy checks")

precondition(UptimePolicy.status(for: 7 * 86400, warningDays: 7) == .attention)
precondition(UptimePolicy.status(for: 7 * 86400 - 1, warningDays: 7) == .good)
precondition(UptimePolicy.status(for: 400 * 86400, warningDays: 0) == .good)
precondition(UptimePolicy.status(for: nil, warningDays: 0) == .unknown)
precondition(UptimePolicy.label(.good, warningDays: 0) == "Uptime check disabled")
precondition(UptimePolicy.label(.good, warningDays: 7) == "Uptime below 7 days")
precondition(UptimePolicy.label(.good, warningDays: 2.5) == "Uptime below 2.5 days")
precondition(HealthPolicy.parse("{}".data(using: .utf8)!)?.uptimeWarningDays == 14)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"uptimeWarningDays":30}}}"#.data(using: .utf8)!)?.uptimeWarningDays == 30)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"uptimeWarningDays":0}}}"#.data(using: .utf8)!)?.uptimeWarningDays == 0)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"uptimeWarningDays":-3}}}"#.data(using: .utf8)!)?.uptimeWarningDays == 14)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"uptimeWarningDays":"ten"}}}"#.data(using: .utf8)!)?.uptimeWarningDays == 14)
print("Passed 12 uptime-policy checks")

var strict = HealthPolicy(); strict.storageWarningGB = 250; strict.storageCriticalGB = 100
let disk2 = StorageSnapshot.validated(capacity: 500_000_000_000, available: 196_000_000_000, name: "T")!
precondition(disk2.status == .good && disk2.status(policy: strict) == .attention)
var tight = HealthPolicy(); tight.storageCriticalGB = 200
precondition(disk2.status(policy: tight) == .critical)
var noStorage = HealthPolicy(); noStorage.storageWarningGB = 0; noStorage.storageCriticalGB = 0
precondition(StorageSnapshot.validated(capacity: 500_000_000_000, available: 1_000_000, name: "T")!.status(policy: noStorage) == .good)
let cell = BatterySnapshot(percent: 15, isCharging: false, onACPower: false, minutesRemaining: nil, cycleCount: nil, healthPercent: 85)
precondition(cell.status == .attention)
var lax = HealthPolicy(); lax.batteryWarningPercent = 10; lax.batteryCriticalPercent = 5
precondition(cell.status(policy: lax) == .good)
var harsh = HealthPolicy(); harsh.batteryCriticalPercent = 30
precondition(cell.status(policy: harsh) == .critical)
var healthStrict = HealthPolicy(); healthStrict.batteryHealthWarningPercent = 90
precondition(BatterySnapshot(percent: 90, isCharging: true, onACPower: true, minutesRemaining: nil, cycleCount: nil, healthPercent: 85).status(policy: healthStrict) == .attention)
var noHealth = HealthPolicy(); noHealth.batteryHealthWarningPercent = 0
precondition(BatterySnapshot(percent: 90, isCharging: true, onACPower: true, minutesRemaining: nil, cycleCount: nil, healthPercent: 50).status(policy: noHealth) == .good)
let parsed = HealthPolicy.parse(#"{"settings":{"policy":{"storageWarningGB":50,"storageCriticalGB":10,"batteryWarningPercent":25,"batteryCriticalPercent":15,"batteryHealthWarningPercent":70}}}"#.data(using: .utf8)!)!
precondition(parsed.storageWarningGB == 50 && parsed.storageCriticalGB == 10 && parsed.batteryWarningPercent == 25 && parsed.batteryCriticalPercent == 15 && parsed.batteryHealthWarningPercent == 70)
let bad = HealthPolicy.parse(#"{"settings":{"policy":{"storageWarningGB":-1,"batteryCriticalPercent":"low"}}}"#.data(using: .utf8)!)!
precondition(bad.storageWarningGB == 20 && bad.batteryCriticalPercent == 10)
print("Passed 10 storage and battery threshold checks")

let full = HealthPolicy.parse(#"{"settings":{"branding":{"title":" Acme IT ","subtitle":"Mac Health"},"policy":{"softwareUpdates":"ignore","networkOffline":"critical","updateScanMinutes":120,"speedTestEnabled":false,"wifiNameLookup":false,"allowQuit":false}}}"#.data(using: .utf8)!)!
precondition(full.appTitle == "Acme IT" && full.appSubtitle == "Mac Health")
precondition(full.softwareUpdates == .good && full.networkOffline == .critical && full.updateScanMinutes == 120)
precondition(!full.speedTestEnabled && !full.wifiNameLookup && !full.allowQuit)
let defaults = HealthPolicy.parse(#"{"settings":{"branding":{"title":"   "},"policy":{"softwareUpdates":"critical","updateScanMinutes":0,"speedTestEnabled":"no"}}}"#.data(using: .utf8)!)!
precondition(defaults.appTitle == "IT Hub" && defaults.appSubtitle == "Device Health")
precondition(defaults.softwareUpdates == .attention && defaults.updateScanMinutes == 30 && defaults.speedTestEnabled)
print("Passed 6 feature and branding policy checks")

let orphanTag = "ithub-orphan-\(getpid())"
// A background grandchild shell tagged in its argv, plus a foreground sleep: both must die with the group.
let timedOut = ReadOnlyCommand.run("/bin/zsh", ["-c", "/bin/zsh -c 'sleep 30; true' \(orphanTag) & sleep 30"], timeout: 0.3)
precondition(timedOut.code == -2)
precondition(ReadOnlyCommand.run("/usr/bin/pgrep", ["-f", orphanTag], timeout: 2).code == 1, "a child of the timed-out script survived")
print("Passed 2 process-group timeout checks")

let profileDoc: [String: Any] = ["settings": ["branding": ["title": "Profile Co"], "policy": ["fileVaultOff": "warning"], "content": [
    ["functionIdentifier": "public.submenu", "settings": ["title": "Links", "content": [["functionIdentifier": "public.link", "settings": ["title": "Portal", "url": "https://p.test/"]]]]]]]]
precondition(HealthPolicy.parse(profileDoc).appTitle == "Profile Co" && HealthPolicy.parse(profileDoc).fileVaultOff == .attention)
precondition(QuickActionConfig.parse(profileDoc, allowScripts: false).map(\.title) == ["Links"])
precondition(QuickActionConfig.preferenceDocument() == nil || QuickActionConfig.activeSourceDescription() == "Configuration profile")
precondition(QuickActionConfig.preferenceDomain == "edu.slc.ithub")
print("Passed 4 configuration-profile checks")

precondition(HealthPolicy.parse("{}".data(using: .utf8)!)?.locationPromptAtLaunch == true)
precondition(HealthPolicy.parse(#"{"settings":{"policy":{"locationPromptAtLaunch":false}}}"#.data(using: .utf8)!)?.locationPromptAtLaunch == false)
print("Passed 2 location-prompt policy checks")
