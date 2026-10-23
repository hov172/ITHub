## 1.0.0 — TopMenu merge

IT Hub now absorbs TopMenu. The Device Health dashboard is unchanged; the previous placeholder Quick Actions row is replaced by groups driven by a TopMenu-compatible `menu.json`. TopMenu's info rows (OS, serial, disk, IP) are dropped because the health cards already show them. The deployment target is lowered from 14.6 to 13.6 to match TopMenu's reach.

### Internet reachability and speed test

The Services card now opens with an Internet line driven by `NWPathMonitor`, ported from TopMenu's network-state plugin: Online, Offline, or Checking, with the card's status dot following it. This is informational and does not feed the Needs attention summary or the menu bar colour, because a satisfied network path is not proof of working internet. Below it, Run speed test measures the link the way WifiDiag's SpeedTestManager does: a warm-up request so TLS and HTTP/2 setup are not charged to the result, ten small latency probes reduced to a trimmed mean, then six parallel download streams and eight parallel upload streams with adaptive chunk sizes, each phase time-bounded by `speedTestSeconds`, with a ramp-up window excluded from the figure. Results show download, upload and latency with the time of measurement. The test runs only on demand, never at launch. All three values appear in the support report.

### Quick Actions configuration

The first file found wins: `/Library/Application Support/IT Hub/menu.json` (managed by IT), then `~/Library/Application Support/IT Hub/menu.json` (per user), then the bundled default. Both folders are watched and the panel reloads about half a second after a change. The format is TopMenu's: a root `public.submenu` whose `settings.content` holds `public.submenu` groups, and inside each group:

| `functionIdentifier` | `settings` keys | Result |
|---|---|---|
| `public.title` | `template` | Plain text row. Rows containing `{value}` are skipped. |
| `public.link` | `title`, `url`, optional `icon` | Opens the URL in the default handler. |
| `public.open.application` | `title`, `bundleIdentifier` and/or `name`, optional `icon` | Opens the app, brought to the foreground. Missing apps show an alert. |
| `public.script` | `title`, `command`, optional `showOutput` (default true), `icon` | Runs the command with `/bin/zsh -c`, 60-second timeout, output in an alert. |

The bundled default contains no organisation-specific values. It ships a Help Desk group (Create Ticket, My IT Tickets, Knowledge Base as `example.com` links, Self Service launching Jamf Self Service by bundle identifier), a Contact IT group (hours, phone, email, remote support link and app, all placeholders), and Browsers and Mail groups. Each environment sets its own values by editing the managed file; the app reloads within a second and no rebuild is needed. `examples/menu-slc.json` is a filled-in example for one campus; copy and adapt it, then pass it to the package script with `-j`.

### Configuration profile (Jamf and other MDM)

The same settings can be delivered as a configuration profile instead of a file, and a profile wins over every file. The app reads the `edu.slc.ithub` preference domain; a profile carries the `branding`, `policy` and `content` keys exactly as they appear under `settings` in `menu.json`. Generate one from any JSON config:

```
python3 scripts/make-profile.py examples/menu-slc.json build/ITHub-SLC.mobileconfig --org "Sarah Lawrence College"
```

Upload the result in Jamf Pro under Computers → Configuration Profiles → Upload, scope it, and the app switches to it within a second of the profile landing, no restart needed. Removing the profile falls back to the files. Profile-delivered values count as trusted, so `public.script` entries are honoured; a plain `defaults write` to the same domain is honoured for everything except scripts. The dashboard footer names the active source: Configuration profile, Managed file, User file or Built-in defaults.

Precedence, highest first: configuration profile, `/Library/Application Support/IT Hub/menu.json`, `~/Library/Application Support/IT Hub/menu.json`, bundled default.

### Health policy

The root `settings.policy` object in the same file tunes health rules. `fileVaultOff` accepts `critical` (red, the default), `warning` (orange) or `ignore` (no notice, no colour change). The FileVault card still shows the measured state in words whatever the policy. Unknown values keep the default. `expectedWiFiSSID` names the Wi-Fi network the Services card compares the current connection against; leave it empty (the default) to disable the comparison. This replaces the previous hard-coded preference. `uptimeWarningDays` sets how many days of uptime trigger the restart reminder (default 14); `0` disables the uptime check, and negative or non-numeric values keep the default.

Storage and battery thresholds follow the same rules, each with `0` disabling that tier and bad values keeping the default:

| Key | Default | Meaning |
|---|---|---|
| `storageWarningGB` | 20 | Free space below this is orange |
| `storageCriticalGB` | 5 | Free space below this is red |
| `batteryWarningPercent` | 20 | Charge at or below this while on battery is orange |
| `batteryCriticalPercent` | 10 | Charge at or below this while on battery is red |
| `batteryHealthWarningPercent` | 80 | Maximum capacity below this percent of design capacity is orange |

Further policy keys:

| Key | Default | Meaning |
|---|---|---|
| `softwareUpdates` | `warning` | `ignore` stops available updates colouring the icon, for fleets where MDM owns updates. The card still shows the result. |
| `networkOffline` | `warning` | `critical` or `ignore` for the no-active-network notice |
| `updateScanMinutes` | 30 | Minutes between automatic update scans (minimum 1) |
| `speedTestEnabled` | `true` | `false` hides the Cloudflare speed test |
| `speedTestSeconds` | 5 | Seconds per phase, clamped 2–20. Each phase runs at full link rate, so 5 s on a 200/40 Mbps link moves about 150 MB |
| `wifiNameLookup` | `true` | `false` hides the Wi-Fi name and never asks for location permission |
| `allowQuit` | `true` | `false` hides the Quit button, for fleets where the LaunchAgent keeps the app running |

### Branding

A root `settings.branding` object sets the dashboard header: `title` (default `IT Hub`, also used in the hover text, the Quit button and the support report heading) and `subtitle` (default `Device Health`). Blank values keep the defaults.

Any group or row may carry `"hidden": true` in its `settings` to keep it in the file but out of the panel; remove the key or set it to `false` to show it again. New rows and groups are added by appending entries in the same format.

`public.script` entries are honoured only from the managed `/Library` file and the bundled default, never from the per-user file, so a user cannot add commands to their own copy. `icon` is an SF Symbol name. Unknown identifiers are ignored.

### Packaging

Build the app with `xcodebuild -scheme "IT Hub Direct Read" -configuration DirectRead` (passing `-configuration Release` silently swaps in the sandboxed entitlements, which blocks FileVault reads). The sandboxed build now carries the outgoing-network entitlement so links and the speed test work there too. `scripts/build-ithub-pkg.sh -a "path/to/IT Hub.app"` builds an installer that places the app in `/Applications`, the managed `menu.json` in `/Library/Application Support/IT Hub`, and a `/Library/LaunchAgents` plist that starts IT Hub at login with KeepAlive. `scripts/build-ithub-uninstall-pkg.sh` builds a payload-free package that unloads the agent and removes all three. Both default to the `edu.slc.ithub` identifier family; override with `-i` and `-l`. Signing and notarization remain the installer's responsibility.

### Validation

Both Xcode schemes build. `python3 Validation/run.py` runs 77 checks, including 11 new parser checks and 10 speed-test and reachability checks: group flattening, `{value}` row skipping, invalid URL rejection, script filtering for untrusted files, non-object documents returning nil, and source trust ordering. Both packages were built and their payloads listed. The dashboard was rendered offscreen and the three bundled groups appear below the Memory card; live clicks on links, apps, and scripts should be checked in the installed app.

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
