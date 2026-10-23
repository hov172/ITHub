# IT Hub 1.0

A macOS menu bar app for IT support. It shows device health at a glance (FileVault, uptime, battery, storage, memory, software updates, network) and gives users one-click links, apps and scripts their IT team configures. Everything environment-specific comes from one JSON file or an MDM configuration profile. Requires macOS 13.6 or later.

Version 1.0 merges two earlier apps: IT Hub 0.9.6 (the health dashboard) and TopMenu (the JSON-driven launcher). The 0.9.x changelog is kept at the end of this file.

## Credits

This app is built on the IT-Hub work shared by Jorn de Koning on the Mac Admins Slack. His IT-Hub concept and implementation are the starting point for the health dashboard here; the configuration system, TopMenu merge, speed test and packaging were added on top of that foundation.

## Install

Build the installer and run it:

```
xcodebuild -scheme "IT Hub Direct Read" -configuration DirectRead build
./scripts/build-ithub-pkg.sh -a "path/to/IT Hub.app" -o build/ITHub.pkg
sudo installer -pkg build/ITHub.pkg -target /
```

The package places `IT Hub.app` in `/Applications`, a managed `menu.json` in `/Library/Application Support/IT Hub`, and a LaunchAgent in `/Library/LaunchAgents` that starts the app at login and keeps it running. Its postinstall restarts the app for every logged-in user, so an upgrade takes effect without a logout. `build/ITHubUninstall.pkg` (from `scripts/build-ithub-uninstall-pkg.sh`) removes all three; it does not touch per-user files or configuration profiles.

Upgrading from a 0.9.x build: those builds used a generated bundle identifier, and 1.0 uses the fixed `edu.slc.ithub`. macOS will not replace an app whose on-disk identifier differs, so the package carries a preinstall that removes the old copy and a postinstall that moves the new app into place if the installer had already planned around it. Because the identifier changed, macOS treats 1.0 as a new app for Location Services: users who had allowed the Wi-Fi name lookup see the prompt once more.

Two build schemes exist. **IT Hub Direct Read** runs outside App Sandbox and is the one to ship: it can read FileVault status and run update scans. **IT Hub** is sandboxed; FileVault and software-update checks show as unavailable there. Always pass `-configuration DirectRead` with the Direct Read scheme; `-configuration Release` silently swaps in the sandboxed entitlements. Builds are ad-hoc signed; Developer ID signing and notarization are the deployer's responsibility.

## How settings load

All settings live in one document with this shape:

```json
{
  "functionIdentifier": "public.submenu",
  "settings": {
    "title": "Quick Actions",
    "branding": { "title": "IT Hub", "subtitle": "Device Health" },
    "policy": { "fileVaultOff": "critical", "uptimeWarningDays": 14 },
    "content": [ ...quick action groups... ]
  }
}
```

The app takes the first source that exists and parses, highest priority first, and uses it for everything (quick actions, policy and branding together; sources are not merged):

| Source | Who edits it | Scripts allowed |
|---|---|---|
| Configuration profile, preference domain `edu.slc.ithub` | MDM | Yes |
| `/Library/Application Support/IT Hub/menu.json` | Admin (root) | Yes |
| `~/Library/Application Support/IT Hub/menu.json` | The user | No |
| `menu.json` inside the app bundle | Ships with the app | Yes |

"Scripts allowed" means `public.script` rows are honoured; from the other sources they are silently dropped, so a user cannot add commands by editing their own file. A plain `defaults write edu.slc.ithub ...` is honoured for everything except scripts, because macOS does not report such values as managed.

Changes apply live. Both file folders and the files themselves are watched, so an in-place rewrite (`cp`, an MDM file push) and an editor that replaces the file both trigger a reload within about half a second. Profile installs and removals arrive through the preferences system and reload the same way. As a fallback, the configuration is re-read on the one-minute device refresh. The dashboard footer shows the active source: Configuration profile, Managed file, User file or Built-in defaults. A document that is not a JSON object is skipped and the next source is tried; a missing or invalid individual value keeps its default.

`examples/menu-slc.json` is a complete filled-in configuration for one campus. The bundled default contains only placeholders (`example.com` links, a `555` phone number) so the generic package can ship anywhere.

## Quick Actions

`settings.content` is an array of groups. Each group is a `public.submenu` whose own `settings.content` holds rows. Rows placed directly at the top level are collected into one group named after the root `settings.title`. A group with no visible rows is not shown.

| `functionIdentifier` | `settings` keys | What it does |
|---|---|---|
| `public.submenu` | `title`, `content`, optional `hidden` | A titled group of rows |
| `public.title` | `template` | A plain text row (hours, phone, email). Rows containing `{value}` are skipped: TopMenu used them for live values the health cards already show. |
| `public.link` | `url`, optional `title` (defaults to the URL), `icon`, `hidden` | Opens the URL in its default handler. The URL must have a scheme (`https:`, `mailto:` and so on). |
| `public.open.application` | `bundleIdentifier` and/or `name`, optional `title` (defaults to the name), `icon`, `hidden` | Opens the app and brings it to the foreground. The bundle identifier is tried first, then `name.app` in the user, local and system Applications folders. A missing app shows an alert. |
| `public.script` | `command`, `title`, optional `showOutput` (default `true`), `icon`, `hidden` | Runs the command with `/bin/zsh -c` from a trusted source only. One script runs at a time; others are disabled while it runs. Output is shown in an alert when `showOutput` is true, and always when the command fails or times out. The timeout is 60 seconds, after which the script's whole process group is stopped, including background jobs it started. |

Common keys: `icon` is an SF Symbol name; the defaults are `info.circle`, `link`, `app` and `terminal` by row type. `"hidden": true` on any group or row keeps it in the file but out of the panel; remove the key or set it to `false` to show it again. New groups and rows are added by appending entries in the same format.

TopMenu keys and plugins not carried over: `arguments`, `runOnStart`, `iconKind`, `badgeLabel`, `badgeColor`, `valueProvider`, and the `public.separator`, `public.quit`, `public.network.state` and `public.cloudflare.speed` identifiers. They are ignored if present. Network state and the speed test are built into the Services card instead.

## Health policy

`settings.policy` tunes the health rules. Every key is optional; a missing, negative or non-numeric value keeps the default. Severity words are `critical` (red), `warning` (orange) and `ignore` (no notice, no icon change); `attention` is accepted for warning, and `off` or `none` for ignore. Where a key says `0` disables a check, the card still shows the measured reading, it just never colours the icon or appears under Needs attention.

| Key | Default | Meaning |
|---|---|---|
| `fileVaultOff` | `critical` | What FileVault being off does to the menu bar icon and Needs attention. The FileVault card always shows the measured state with a red dot when off, whatever this says. `warning` and `ignore` cannot be applied to the card itself. |
| `uptimeWarningDays` | 14 | Days of uptime before the restart reminder. `0` disables it; the card then reads "Uptime check disabled". Fractional days work. |
| `storageWarningGB` | 20 | Free space (decimal GB) below which storage is orange. `0` disables. |
| `storageCriticalGB` | 5 | Free space below which storage is red. `0` disables. |
| `batteryWarningPercent` | 20 | Charge at or below this while on battery is orange. `0` disables. |
| `batteryCriticalPercent` | 10 | Charge at or below this while on battery is red. `0` disables. |
| `batteryHealthWarningPercent` | 80 | Maximum capacity below this percent of design capacity is orange. `0` disables. Cycle count is informational only. |
| `softwareUpdates` | `warning` | Severity of an available macOS update or upgrade. `ignore` for fleets where MDM owns updates. `critical` is not accepted. The Software Update card still shows the result. |
| `networkOffline` | `warning` | Severity when no network service has an address. `critical` or `ignore`. This is the configured-address check; the separate "Internet: Online/Offline" line in the Services card is informational and never affects the icon. |
| `updateScanMinutes` | 30 | Minutes between automatic `softwareupdate` scans. Minimum 1. Scans also run at launch, on wake if due, and on Check now. |
| `expectedWiFiSSID` | empty | Wi-Fi network name to compare the current connection against; shows "Expected Wi-Fi" or "Different from expected Wi-Fi" in the Services card. Empty disables the comparison. |
| `wifiNameLookup` | `true` | `false` hides the Wi-Fi name and the expected-network comparison, and the app never asks for Location Services permission. |
| `speedTestEnabled` | `true` | `false` hides Run speed test. |
| `speedTestSeconds` | 5 | Seconds per phase (download, then upload), clamped 2 to 20. Each phase runs at full link rate, so 5 s on a 200/40 Mbps link moves about 150 MB. |
| `allowQuit` | `true` | `false` hides the Quit button, for fleets where the LaunchAgent keeps the app running anyway. |

Fixed in code, on purpose: device readings refresh every minute, memory is sampled every 10 seconds, a clean update result older than one hour becomes unknown, memory-pressure severity follows the kernel's own levels, and the dashboard is 720 points wide.

## Branding

`settings.branding` sets `title` (default `IT Hub`) and `subtitle` (default `Device Health`). The title also appears in the menu bar hover text, on the Quit button and as the support report heading. Blank values keep the defaults.

## Configuration profile (Jamf and other MDM)

A profile delivers the same settings without a file and outranks every file. Generate one from any configuration:

```
python3 scripts/make-profile.py examples/menu-slc.json build/ITHub-SLC.mobileconfig --org "Sarah Lawrence College" --name "IT Hub (SLC)"
```

The profile sets the `edu.slc.ithub` preference domain with a `settings` dictionary holding `branding`, `policy` and `content` exactly as in the JSON. The app also accepts those three keys at the top level of the domain. In Jamf Pro upload it under Computers → Configuration Profiles → Upload and scope it; the app switches to it within a second of it landing and falls back to the files when it is removed. Generated profiles are written to `build/`, which is not committed; regenerate from the JSON when it changes.

## Services card: reachability and speed test

The Internet line uses `NWPathMonitor`: Online, Offline or Checking, with the card's dot following it. It is informational only. Run speed test measures the link the way WifiDiag's SpeedTestManager does: a warm-up request so TLS and HTTP/2 setup are not charged to the result, ten small latency probes reduced to a trimmed mean, six parallel download streams and eight parallel upload streams with adaptive chunk sizes, each phase bounded by `speedTestSeconds`, and a ramp-up window excluded from the figure. It runs against `speed.cloudflare.com` with browser-style headers, which Cloudflare requires for large transfers. Results show download, upload and latency with the time of measurement, appear in the support report, and are not kept across restarts. The test runs only on demand, never at launch.

## Packaging scripts

`scripts/build-ithub-pkg.sh` options: `-a` app bundle (required), `-j` menu.json to ship as the managed file (default `IT Hub/menu.json`; validated as JSON first), `-v` version (default: the app's `CFBundleShortVersionString`), `-i` package identifier (`edu.slc.ithub`), `-l` LaunchAgent label (`edu.slc.ithub.launcher`), `-o` output (`build/ITHub.pkg`). The package is built non-relocatable with the preinstall and postinstall described under Install.

`scripts/build-ithub-uninstall-pkg.sh` options: `-v`, `-i` (`edu.slc.ithub.uninstall`), `-l`, `-o` (`build/ITHubUninstall.pkg`). It verifies that its removal script was registered in the package and fails the build otherwise.

`scripts/make-profile.py source.json output.mobileconfig [--org NAME] [--name NAME]` as above.

## Validation

`python3 Validation/run.py` compiles the app sources with the Xcode toolchain for macOS 13 and runs 132 checks in 16 groups: command parsing and bounded execution, process-group timeout, uptime boundaries and storage arithmetic, memory pressure and usage, health priority and update naming, update freshness and network uncertainty, quick-action parsing (grouping, `{value}` skipping, URL validation, script filtering by trust, hidden flags, source ordering), speed maths and reachability labels, every policy key (FileVault, Wi-Fi, uptime, storage, battery, updates, network, feature switches, branding), and configuration-profile parsing. Both Xcode schemes build. The speed engine was also run end to end from a command-line harness, and the installed app was checked live for reachability, speed, hot reload of files, and profile precedence through staged managed preferences.

## 1.0.0 changelog

- Merged TopMenu's JSON-driven quick actions, hot reload and installer packaging into IT Hub. TopMenu's info rows are dropped because the health cards show the same data.
- Every environment-specific rule moved into configuration: quick actions with add and hide, all health thresholds and severities, update scan interval, feature switches, branding, expected Wi-Fi.
- Configuration profile support with a generator for Jamf; stable `edu.slc.ithub` bundle identifier.
- Speed test rebuilt on WifiDiag's method; the previous single 2 MB request under-reported download about five-fold.
- Deployment target lowered from 14.6 to 13.6.
- Installer: non-relocatable package, old-identifier migration, agent restart after upgrade; uninstaller now actually registers its removal script.
- Script timeouts stop the whole process group; a managed config rewritten in place now triggers a reload.
- Sandboxed scheme gained the outgoing-network entitlement.

## 0.9.6 — reliability audit

Preserves known warnings during refresh, expires stale update results, distinguishes unreadable network state, removes the universal battery-cycle warning, and protects temporary command output. See [AUDIT.md](AUDIT.md) for checks and remaining limitations.

# IT Hub v0.9 — Menu bar health summary

## Install

Open IT-Hub-0.9.dmg, quit any running IT Hub, and drag IT Hub into Applications to replace the previous app. Launch from Applications and confirm v0.9. The DMG is the DirectRead development build, locally ad-hoc signed and not Developer ID signed/notarized. macOS may require approval. It runs outside App Sandbox.

To build from source, open IT Hub.xcodeproj and select IT Hub Direct Read / My Mac. The regular IT Hub scheme remains sandboxed, where some checks intentionally show unavailable. The startup location permission flow, uptime menu dot/badge, battery cycle display, resource cards, and software-update check behavior are retained.

## Device & Support

The new card below Memory displays the computer name, model, chip, installed RAM and serial number. HardwareService runs system_profiler SPHardwareDataType -json -detailLevel full off the UI thread with a 20-second timeout, parses the hardware section, and uses unavailable for missing values. Intel cpu_type is supported when chip_type is absent. Model identifier is included in the support report. No serial-number lookup is performed: macOS supplies the hardware information. Exact model/year descriptions beyond what macOS supplies are not invented. RAM is read from ProcessInfo.

The serial-number copy action copies only the serial. Copy Support Details copies a current plain-text report to the local clipboard. Preview opens a selectable report sheet; its Copy report action copies that same frozen preview text. No report is sent or uploaded automatically.

Reports include device name/model/identifier/chip/RAM/serial, macOS and build, FileVault result, uptime, battery charge/cycles/estimated capacity, storage, estimated memory usage/pressure/swap, configured services with primary status and available Wi-Fi names/IP addresses, and software-update result/names/check time. Missing or blocked information remains unavailable. No Wi-Fi passwords or FileVault recovery keys are collected. A capture timestamp identifies when the report was assembled; individual sources retain their existing refresh intervals. The software-update result includes its own last-check timestamp.

Zero memory/swap formatting now explicitly uses 0 KB, as requested; nonzero values retain numeric units. This supersedes v0.7.2's unitless zero.

## Verification

DirectRead macOS app-target build passed with Xcode, signing disabled. The packaged app's local signature and disk-image checksum were checked. Hardware JSON parsing was checked with representative model/chip/serial fields, missing-field and invalid-root fixtures; zero formatting was checked against 0 KB. No fixture values are shipped into the dashboard.

A full dashboard render verified the new card's position and separation from other cards. The render harness does not run dashboard task refreshes, so its unavailable/loading fields do not establish runtime hardware access. Native controls in ImageRenderer are limited; actual preview-sheet behavior, clipboard actions, signed runtime SSID access and hardware results should be checked after installation. Current app data services otherwise retain their previously tested behavior; no claim of a new comprehensive regression run is made.

The existing ITHub-IconFix project was updated in place. Archive sources supplied by the user remain unchanged. Validation lives outside the app's synchronized source group.

## v0.9 — Quiet health summary

DeviceHealthModel now owns the shared security, storage, battery, uptime, memory, update and network models. Dashboard and menu label observe the same values. Monitoring starts with the app, without requiring the dashboard to open. Device data refreshes every minute; memory keeps its existing 10-second sampling; available macOS updates are scanned at launch and about every 30 minutes, and via Check now. No installation is performed. The update scan is bounded by the existing timeout. These are read-only operations.

The menu bar laptop outline itself is tinted, rather than showing the previous uptime-only dot:
- Red: a confirmed critical monitored condition (e.g. FileVault reported off, critically low disk or battery, critical memory pressure).
- Orange: an actionable warning, including an offered update/upgrade, uptime at or beyond 14 days, low disk/battery thresholds, or no configured network address detected.
- Grey: one or more required readings are unavailable or still checking, with no known warning/critical condition.
- Green: all applicable monitored checks have usable passing readings.

Priority is red > orange > grey > green. Known problems remain visible even when unrelated checks are unknown. Green is not a company-compliance guarantee. Battery is excluded only when the system successfully reports no internal battery; a failed battery read stays unknown. Network state is based on configured addresses, not an internet-connectivity test. Hardware identifiers and swap accounting are informational rather than pressure/health thresholds.

Hover text lists the reasons. Needs attention appears above the dashboard cards when there are reasons; confirmed issues are listed individually, and multiple unavailable checks are grouped into one compact line with full hover detail. At 14+ days the exact reminder is A restart may speed up your Mac. There are no notification-center APIs, authorization requests, banners in the upper-right corner, or notification pop-ups in this feature.

Update labels are distinguished as macOS update / upgrade only when a recognizable major version is present; otherwise the wording remains update or upgrade available. Office presence detection is not implemented or assumed: merely using home Wi-Fi, Ethernet or a VPN does not trigger an office-network warning. No office rule is configured in this release. Existing expected-SSID information remains in the Services card.

Validation: DirectRead and sandboxed app-target builds passed with signing disabled. Ten focused status/update/uptime checks passed in an offscreen-render harness; the source validation suite was also run. The rendered startup/unavailable dashboard was inspected for separation of the attention summary and cards. Signed native menu-bar tint/hover behavior and ongoing service access must still be verified after installation. The new status monitor replaces the old uptime-only menu icon path; it does not grant new permissions or introduce simulated statuses.

## v0.9.1 — Visible Wi-Fi permission flow

Adds WiFiPermissionView and a retained native onboarding window. For this onboarding revision, a notDetermined/denied/restricted installation sees the window once at startup. When authorization is notDetermined, the automatic system request waits for IT Hub to be active and that window to be key. The explicit Allow Wi-Fi Name button can reopen the window and retry. Previously denied/restricted access gets an explanation and Location Settings action; allowed access gets Refresh Wi-Fi Name. The Services card shows the current authorization explanation if the SSID remains unavailable. macOS retains permission decisions, and no privacy reset is performed.

The per-user onboarding key is wifiPermissionWelcomeShownV1. The app does not show the welcome window repeatedly after Later, a previous decision, or a user dismissal; the Services action remains available. Existing authorized installations do not get another first-time OS prompt. No app implementation can force macOS to display its original prompt for a stored Allow/Deny decision. The helper window is an in-app setup window, not a notification-center banner, and does not start coordinate updates.

Validation: DirectRead macOS app-target build and local signature verification passed. This environment cannot validate a fresh signed installation's native permission prompt without changing user privacy state; that state was not reset or altered. Test notDetermined, denied and authorized paths on the intended installation. This revision preserves the v0.9 health monitor and all earlier device/support behavior.

## v0.9.2 — Left-column order

The three left-column sections now appear in the requested order: Device & Support, Storage, Memory. Other sections, health/status rules and the first-launch Wi-Fi permission flow remain unchanged. DirectRead build is checked before packaging; this revision is a presentation-only reorder.

## v0.9.3 — Shared computer symbol

ComputerMark.swift is now the single definition of the computer shape, symbol rendering mode, regular weight, 14-point size, and 22x18-point frame. The dashboard header displays that view directly; DeviceHealthModel renders that same view through SwiftUI ImageRenderer for the menu bar, preserving the status colour without stretching an AppKit symbol into a different rectangle. The previous custom AppKit draw/tint path was removed from the health menu icon. This resolves the inconsistent shape introduced by separate rendering paths.

Validation: DirectRead app-target build passed with signing disabled. An offscreen comparison verified matching rendered dimensions and per-pixel alpha masks for the neutral header and green status icon, and the two rendered icons were visually inspected. Real native menu-bar appearance remains to be checked after installation. Health priority and other behavior are unchanged.

## v0.9.4 — Foreground destinations

WindowPresentation.swift centralizes destination activation and tracks the actual dashboard NSWindow through DashboardWindowReader. Settings deep links use NSWorkspace.OpenConfiguration with activates enabled and explicitly activate the returned Settings process. Activity Monitor uses the same foreground policy. The dashboard orders out before external destinations open so its menu-panel level cannot cover them.

Support Details Preview is now an independent, retained NSWindow instead of a SwiftUI sheet attached to the menu-bar panel. It is placed one window level above the dashboard (at least floating), made key/front, and IT Hub is activated. Its hidesOnDeactivate flag prevents it staying above other apps after switching away. Closing releases its hosting view and controller reference; reopening shows a fresh snapshot. The Wi-Fi permission window uses the same foreground preparation, while retaining its existing authorization logic. Copy-only actions still use inline feedback and do not open a window. In-panel service selection and update scans do not create separate destination windows.

Validation: DirectRead macOS app-target build and local signature check passed; all external-app opening call sites were checked to use WindowPresentation. No external apps were opened on the user's desktop for automated testing. Live focus, Spaces behavior, and clicking/reopening the menu panel after returning from Settings must be checked in the installed app. This is not a guarantee that macOS will permit every activation in every desktop arrangement. Health monitoring, permissions, and layout remain otherwise unchanged.

## v0.9.5 — External-app activation retry

Settings and Activity Monitor now explicitly receive cooperative activation authority via NSApplication.yieldActivation before LaunchServices opens them. IT Hub hides all its windows instead of relying solely on a weak reference to the dashboard panel. The completion is handled on the main actor, unhides the destination and activates it from the current application, requesting all destination windows. On pre-macOS-14 systems the legacy activation flags are used. Launch failure unhides IT Hub and displays the returned error instead of silently leaving the app hidden. Preview/Wi-Fi in-app window handling is unchanged.

Validation: DirectRead app-target build, local signature and packaged version check passed. Actual cross-application foreground behavior could not be verified in the build environment; test Open Settings and Activity Monitor in the installed v0.9.5 app and verify the dashboard no longer covers them. The previous v0.9.4 build succeeded but did not establish that live activation behavior worked.
